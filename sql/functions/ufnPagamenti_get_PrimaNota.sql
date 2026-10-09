SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Prima nota: i movimenti (pagamenti attivi) dell'azienda interna corrente della sessione, con la banca o cassa,
-- le fatture pagate e il cliente o fornitore. Usata dall'elenco e dall'esportazione, che devono vedere gli
-- stessi movimenti (uspPagamenti_get_PrimaNota_List, uspPagamenti_get_PrimaNota_Esportazione).
-- Entrata / Uscita secondo il verso del movimento (Tipo E / U). Saldo = saldo della banca o cassa dopo il
-- movimento: il suo saldo iniziale (tblBancheCasse.SaldoIniziale, all'inizio del giorno DataSaldoIniziale) più
-- TUTTI i suoi movimenti da quella data fino a questo, anche precedenti al periodo o esclusi dalla ricerca;
-- un movimento precedente alla data del saldo iniziale non ha saldo. È valorizzato solo con @IdBancaCassa,
-- perché su più banche e casse insieme non ha significato.
-- Manuale = 1: movimento non legato a rate di fatture (nessuna quota), inserito dalla prima nota; può avere un conto.
-- Fatture = numeri delle fatture pagate (per un fornitore il numero del suo documento). Con più clienti o
-- fornitori nello stesso movimento il nome è "primo e altri N" e partita IVA e codice fiscale restano vuoti.
-- @Verso: E entrate, U uscite, NULL tutti. @Testo cerca in causale, nome e numeri delle fatture.
CREATE OR ALTER FUNCTION dbo.ufnPagamenti_get_PrimaNota
(
	@IdSessione CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@IdBancaCassa CHAR(16),
	@Verso CHAR(1),
	@Testo VARCHAR(50)
)
RETURNS TABLE
AS
RETURN
(
	WITH movimenti AS (
		SELECT
			p.Id,
			p.IdBancaCassa,
			p.IdModalita,
			p.IdConto,
			p.Tipo,
			p.Causale,
			p.DataContabile,
			p.DataRegistrazione,
			Importo = ISNULL(p.Importo, 0),
			BancaCassaNome = b.Nome,
			-- I movimenti precedenti alla data del saldo iniziale non entrano nel saldo e non ne hanno uno
			ConSaldo = CAST(IIF(b.DataSaldoIniziale IS NULL OR p.DataContabile >= b.DataSaldoIniziale, 1, 0) AS BIT),
			Saldo = IIF(b.DataSaldoIniziale IS NULL, 0, ISNULL(b.SaldoIniziale, 0))
				+ SUM(IIF(b.DataSaldoIniziale IS NULL OR p.DataContabile >= b.DataSaldoIniziale, IIF(p.Tipo = 'E', 1, -1) * ISNULL(p.Importo, 0), 0)) OVER (
					PARTITION BY p.IdBancaCassa
					ORDER BY p.DataContabile, p.DataRegistrazione, p.Id
					ROWS UNBOUNDED PRECEDING)
		FROM
			dbo.tblPagamenti p
			INNER JOIN dbo.tblSessioni e ON p.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblBancheCasse b ON p.IdBancaCassa = b.Id
		WHERE
			e.Id = @IdSessione
			AND p.Lock = 0
	)
	SELECT
		m.Id,
		m.IdBancaCassa,
		m.BancaCassaNome,
		m.IdModalita,
		ModalitaNome = o.Nome,
		m.IdConto,
		ContoNome = k.Nome,
		Manuale = CAST(IIF(EXISTS (SELECT 1 FROM dbo.tblFattureRatePagamenti q WHERE q.IdPagamento = m.Id), 0, 1) AS BIT),
		m.Tipo,
		m.Causale,
		m.DataContabile,
		m.DataRegistrazione,
		Entrata = CAST(IIF(m.Tipo = 'E', m.Importo, NULL) AS DECIMAL(18, 2)),
		Uscita = CAST(IIF(m.Tipo = 'E', NULL, m.Importo) AS DECIMAL(18, 2)),
		Saldo = CAST(IIF(@IdBancaCassa IS NULL OR m.ConSaldo = 0, NULL, m.Saldo) AS DECIMAL(18, 2)),
		x.Fatture,
		NomeCompleto = CAST(x.NomeCompleto + IIF(x.Soggetti > 1, ' e altri ' + CAST(x.Soggetti - 1 AS VARCHAR(10)), '') AS VARCHAR(300)),
		PartitaIva = IIF(x.Soggetti = 1, x.PartitaIva, NULL),
		CodiceFiscale = IIF(x.Soggetti = 1, x.CodiceFiscale, NULL)
	FROM
		movimenti m
		LEFT JOIN dbo.tblPagamentiModalita o ON m.IdModalita = o.Id
		LEFT JOIN dbo.tblFattureConti k ON m.IdConto = k.Id
		OUTER APPLY
			(
				SELECT
					Fatture = STRING_AGG(d.Numero, ', ') WITHIN GROUP (ORDER BY d.DataEmissione, d.Numero),
					Soggetti = COUNT(DISTINCT d.IdClienteFornitore),
					NomeCompleto = MIN(d.NomeCompleto),
					PartitaIva = MIN(d.PartitaIva),
					CodiceFiscale = MIN(d.CodiceFiscale)
				FROM
					(
						SELECT DISTINCT
							f.Id,
							Numero = CAST(ISNULL(IIF(f.Tipo = 'F', NULLIF(f.NumeroFornitore, ''), NULL), CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, '')) AS VARCHAR(40)),
							f.DataEmissione,
							f.IdClienteFornitore,
							s.NomeCompleto,
							s.PartitaIva,
							s.CodiceFiscale
						FROM
							dbo.tblFattureRatePagamenti rp
							INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
							INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
							LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
							LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
						WHERE rp.IdPagamento = m.Id
					) d
			) x
	WHERE
		(@DataDa IS NULL OR m.DataContabile >= @DataDa)
		AND (@DataA IS NULL OR m.DataContabile <= @DataA)
		AND (@IdBancaCassa IS NULL OR m.IdBancaCassa = @IdBancaCassa)
		AND (@Verso IS NULL OR m.Tipo = @Verso)
		AND
			(
			@Testo IS NULL
			OR m.Causale LIKE '%' + @Testo + '%'
			OR x.NomeCompleto LIKE '%' + @Testo + '%'
			OR x.Fatture LIKE '%' + @Testo + '%'
			)
);
GO
