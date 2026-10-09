/*
Deploy produzione 2026-10-09 - Fatturazione > Prima nota (elenco dei movimenti, dettaglio, esportazione CSV)

Da eseguire DOPO deploy_produzione_2026-10-08_fatturazione_dati_fiscali.sql (posizioni del menu Fatturazione).
Rieseguibile. Eseguire con sqlcmd -f 65001 -I.

1. Pagina e voce di menu Prima nota (funzione FTT), dopo Scadenziario fornitori.
2. ufnPagamenti_get_PrimaNota: movimenti, saldo della banca o cassa, fatture e soggetto (la funzione va prima
   delle SP che la usano).
3. uspPagamenti_get_PrimaNota_List: elenco paginato.
4. uspPagamenti_get_PrimaNota_Esportazione: righe e intestazioni del file CSV.
5. uspPagamenti_get_Rate_List: rate coperte da un movimento.

Nessuna modifica alle tabelle: i movimenti sono i pagamenti registrati dallo scadenziario. Va deployato
insieme all'app.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

PRINT 'Pagina e menu della prima nota';
GO
-- Fatturazione > Prima nota: pagina e voce di menu (funzione FTT, la stessa di fatture e scadenziario).
-- Non servono tabelle nuove: i movimenti sono i pagamenti registrati dallo scadenziario (tblPagamenti).
-- Script idempotente: rieseguibile senza effetti su un DB che ha già la registrazione.
SET NOCOUNT ON;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTN')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTN', 'FTT', 'Prima nota', 'prima-nota', NULL);

-- Menu Fatturazione: Fatture clienti, Fatture fornitori, Scadenziario clienti, Scadenziario fornitori,
-- Prima nota, Conti, Banche e casse, Aliquote IVA, Dati fiscali
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ9')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ9', 'AJ0', NULL, 'FTN', 4);

UPDATE dbo.tblMenu SET Pos = 4 WHERE Id = 'AJ9' AND Pos <> 4;
UPDATE dbo.tblMenu SET Pos = 5 WHERE Id = 'AJ5' AND Pos <> 5;
UPDATE dbo.tblMenu SET Pos = 6 WHERE Id = 'AJ1' AND Pos <> 6;
UPDATE dbo.tblMenu SET Pos = 7 WHERE Id = 'AJ2' AND Pos <> 7;
UPDATE dbo.tblMenu SET Pos = 8 WHERE Id = 'AJ8' AND Pos <> 8;
GO

PRINT 'ufnPagamenti_get_PrimaNota';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Prima nota: i movimenti (pagamenti attivi) dell'azienda interna corrente della sessione, con la banca o cassa,
-- le fatture pagate e il cliente o fornitore. Usata dall'elenco e dall'esportazione, che devono vedere gli
-- stessi movimenti (uspPagamenti_get_PrimaNota_List, uspPagamenti_get_PrimaNota_Esportazione).
-- Entrata / Uscita secondo il verso del movimento (Tipo E / U). Saldo = saldo della banca o cassa dopo il
-- movimento: somma di TUTTI i suoi movimenti fino a quello, anche precedenti al periodo o esclusi dalla ricerca;
-- è valorizzato solo con @IdBancaCassa, perché su più banche e casse insieme non ha significato.
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
			p.Tipo,
			p.Causale,
			p.DataContabile,
			p.DataRegistrazione,
			Importo = ISNULL(p.Importo, 0),
			Saldo = SUM(IIF(p.Tipo = 'E', 1, -1) * ISNULL(p.Importo, 0)) OVER (
				PARTITION BY p.IdBancaCassa
				ORDER BY p.DataContabile, p.DataRegistrazione, p.Id
				ROWS UNBOUNDED PRECEDING)
		FROM
			dbo.tblPagamenti p
			INNER JOIN dbo.tblSessioni e ON p.IdSede = e.IdAzienda
		WHERE
			e.Id = @IdSessione
			AND p.Lock = 0
	)
	SELECT
		m.Id,
		m.IdBancaCassa,
		BancaCassaNome = b.Nome,
		ModalitaNome = o.Nome,
		m.Tipo,
		m.Causale,
		m.DataContabile,
		m.DataRegistrazione,
		Entrata = CAST(IIF(m.Tipo = 'E', m.Importo, NULL) AS DECIMAL(18, 2)),
		Uscita = CAST(IIF(m.Tipo = 'E', NULL, m.Importo) AS DECIMAL(18, 2)),
		Saldo = CAST(IIF(@IdBancaCassa IS NULL, NULL, m.Saldo) AS DECIMAL(18, 2)),
		x.Fatture,
		NomeCompleto = CAST(x.NomeCompleto + IIF(x.Soggetti > 1, ' e altri ' + CAST(x.Soggetti - 1 AS VARCHAR(10)), '') AS VARCHAR(300)),
		PartitaIva = IIF(x.Soggetti = 1, x.PartitaIva, NULL),
		CodiceFiscale = IIF(x.Soggetti = 1, x.CodiceFiscale, NULL)
	FROM
		movimenti m
		LEFT JOIN dbo.tblBancheCasse b ON m.IdBancaCassa = b.Id
		LEFT JOIN dbo.tblPagamentiModalita o ON m.IdModalita = o.Id
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

PRINT 'uspPagamenti_get_PrimaNota_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Prima nota: elenco paginato dei movimenti (pagamenti attivi) dell'azienda del contesto, dal più vecchio, per
-- data contabile. Senza azienda nel contesto nessuna riga. Colonne e ricerca: ufnPagamenti_get_PrimaNota.
-- Il saldo progressivo c'è solo con una banca o cassa selezionata.
CREATE OR ALTER PROCEDURE dbo.uspPagamenti_get_PrimaNota_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdBancaCassa CHAR(16) = NULL,
	@Verso CHAR(1) = NULL,
	@Testo VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdBancaCassa = NULLIF(NULLIF(LTRIM(RTRIM(@IdBancaCassa)), ''), REPLICATE('0', 16));
		SET @Verso = UPPER(NULLIF(LTRIM(RTRIM(@Verso)), ''));
		SET @Testo = dbo.ufnStringhe_get_SenzaSpazi(@Testo, 0, 1);
		SET @PageNumber = IIF(ISNULL(@PageNumber, 0) < 1, 1, @PageNumber);
		SET @RowsPerPage = IIF(ISNULL(@RowsPerPage, 0) < 1, 50, @RowsPerPage);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Verso IS NOT NULL AND @Verso NOT IN ('E', 'U')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Verso deve essere E (entrate) o U (uscite)';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			t.Id,
			[Data] = t.DataContabile,
			t.DataRegistrazione,
			t.IdBancaCassa,
			t.BancaCassaNome,
			t.ModalitaNome,
			t.Tipo,
			t.Causale,
			t.Entrata,
			t.Uscita,
			t.Saldo,
			t.Fatture,
			t.NomeCompleto,
			RowsCount = COUNT(*) OVER ()
		FROM dbo.ufnPagamenti_get_PrimaNota(@IdSessione, @DataDa, @DataA, @IdBancaCassa, @Verso, @Testo) t
		ORDER BY
			t.DataContabile,
			t.DataRegistrazione,
			t.Id
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspPagamenti_get_PrimaNota_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Prima nota: righe per l'esportazione in CSV (Azioni > Esporta). Stessi movimenti e stessa ricerca
-- dell'elenco (ufnPagamenti_get_PrimaNota), tutti e senza paginazione, con più colonne di quelle a video.
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (CsvService) scrive le colonne
-- così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo questa SP.
CREATE OR ALTER PROCEDURE dbo.uspPagamenti_get_PrimaNota_Esportazione
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdBancaCassa CHAR(16) = NULL,
	@Verso CHAR(1) = NULL,
	@Testo VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdBancaCassa = NULLIF(NULLIF(LTRIM(RTRIM(@IdBancaCassa)), ''), REPLICATE('0', 16));
		SET @Verso = UPPER(NULLIF(LTRIM(RTRIM(@Verso)), ''));
		SET @Testo = dbo.ufnStringhe_get_SenzaSpazi(@Testo, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Verso IS NOT NULL AND @Verso NOT IN ('E', 'U')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Verso deve essere E (entrate) o U (uscite)';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			[Data contabile] = t.DataContabile,
			[Data registrazione] = t.DataRegistrazione,
			[Banca o cassa] = t.BancaCassaNome,
			[Movimento] = IIF(t.Tipo = 'E', 'Entrata', 'Uscita'),
			[Pagamento tramite] = t.ModalitaNome,
			[Causale] = t.Causale,
			[Entrata] = t.Entrata,
			[Uscita] = t.Uscita,
			[Saldo] = t.Saldo,
			[Fatture] = t.Fatture,
			[Cliente o fornitore] = t.NomeCompleto,
			[Partita IVA] = t.PartitaIva,
			[Codice fiscale] = t.CodiceFiscale
		FROM dbo.ufnPagamenti_get_PrimaNota(@IdSessione, @DataDa, @DataA, @IdBancaCassa, @Verso, @Testo) t
		ORDER BY
			t.DataContabile,
			t.DataRegistrazione,
			t.Id
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspPagamenti_get_Rate_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rate coperte da un pagamento, per il dettaglio del movimento nella prima nota: fattura (Tipo C cliente,
-- F fornitore; Numero = quello che si legge sul documento, per un fornitore il numero del suo documento),
-- cliente o fornitore, scadenza della rata e Quota, la parte del pagamento attribuita alla rata.
-- Scope: pagamento dell'azienda interna corrente della sessione.
CREATE OR ALTER PROCEDURE dbo.uspPagamenti_get_Rate_List
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			Id = r.Id,
			r.IdFattura,
			f.Tipo,
			Numero = CAST(ISNULL(IIF(f.Tipo = 'F', NULLIF(f.NumeroFornitore, ''), NULL), CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, '')) AS VARCHAR(40)),
			f.DataEmissione,
			NotaCredito = CAST(IIF(f.IdTipo = 'TD04', 1, 0) AS BIT),
			s.NomeCompleto,
			r.DataScadenza,
			Quota = CAST(rp.Importo AS DECIMAL(18, 2))
		FROM
			dbo.tblPagamenti p
			INNER JOIN dbo.tblSessioni e ON p.IdSede = e.IdAzienda
			INNER JOIN dbo.tblFattureRatePagamenti rp ON p.Id = rp.IdPagamento
			INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE
			p.Id = @Id
			AND e.Id = @IdSessione
			AND p.Lock = 0
		ORDER BY
			r.DataScadenza,
			f.DataEmissione,
			r.Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO
