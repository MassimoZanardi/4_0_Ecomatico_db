/*
Deploy produzione 2026-10-09 - Fatturazione > Prima nota (elenco dei movimenti, dettaglio, esportazione CSV,
saldo iniziale delle banche e casse, movimenti manuali)

Da eseguire DOPO deploy_produzione_2026-10-08_fatturazione_dati_fiscali.sql (posizioni del menu Fatturazione).
Rieseguibile. Eseguire con sqlcmd -f 65001 -I.

1. Pagina e voce di menu Prima nota (funzione FTT), dopo Scadenziario fornitori.
2. Colonne nuove: tblBancheCasse.SaldoIniziale e DataSaldoIniziale; tblPagamenti.IdConto con la sua chiave
   esterna verso tblFattureConti (conto di un movimento manuale).
3. ufnPagamenti_get_PrimaNota: movimenti, saldo della banca o cassa dal saldo iniziale, fatture e soggetto
   (la funzione va prima delle SP che la usano).
4. uspPagamenti_get_PrimaNota_List: elenco paginato.
5. uspPagamenti_get_PrimaNota_Esportazione: righe e intestazioni del file di esportazione.
6. uspPagamenti_get_Rate_List: rate coperte da un movimento.
7. uspPagamenti_upd_Manuale, uspPagamenti_del_Manuale: movimenti non legati a fatture.
8. uspBancheCasse_get, uspBancheCasse_upd: saldo iniziale.
9. uspFattureConti_del: un conto usato in un movimento manuale attivo non si cancella.

I movimenti sono i pagamenti registrati dallo scadenziario più quelli manuali (tblPagamenti senza quote in
tblFattureRatePagamenti). Va deployato insieme all'app.

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

PRINT 'Colonne del saldo iniziale e dei movimenti manuali';
GO
-- Fatturazione > Prima nota, saldo iniziale e movimenti manuali.
-- tblBancheCasse.SaldoIniziale e DataSaldoIniziale: saldo della banca o cassa all'inizio del giorno indicato; il
-- saldo progressivo della prima nota parte da lì (i movimenti precedenti non lo modificano).
-- tblPagamenti.IdConto: conto facoltativo di un movimento manuale, cioè di un pagamento non legato a rate di
-- fatture (nessuna riga in tblFattureRatePagamenti): spese bancarie, prelievi, versamenti, stipendi.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già le colonne.
SET NOCOUNT ON;
GO
IF COL_LENGTH('dbo.tblBancheCasse', 'SaldoIniziale') IS NULL
	ALTER TABLE dbo.tblBancheCasse ADD SaldoIniziale DECIMAL(18, 2) NULL;
IF COL_LENGTH('dbo.tblBancheCasse', 'DataSaldoIniziale') IS NULL
	ALTER TABLE dbo.tblBancheCasse ADD DataSaldoIniziale DATE NULL;
IF COL_LENGTH('dbo.tblPagamenti', 'IdConto') IS NULL
	ALTER TABLE dbo.tblPagamenti ADD IdConto CHAR(16) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblPagamenti_tblFattureConti')
BEGIN
	ALTER TABLE dbo.tblPagamenti WITH CHECK ADD CONSTRAINT FK_tblPagamenti_tblFattureConti FOREIGN KEY (IdConto) REFERENCES dbo.tblFattureConti (Id);
	ALTER TABLE dbo.tblPagamenti CHECK CONSTRAINT FK_tblPagamenti_tblFattureConti;
END
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
			t.IdModalita,
			t.ModalitaNome,
			t.IdConto,
			t.ContoNome,
			t.Manuale,
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
			[Conto] = t.ContoNome,
			[Entrata] = t.Entrata,
			[Uscita] = t.Uscita,
			[Saldo] = t.Saldo,
			[Fatture] = t.Fatture,
			[Cliente o fornitore] = t.NomeCompleto,
			[Origine] = IIF(t.Manuale = 1, 'Movimento manuale', 'Fattura'),
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

PRINT 'uspPagamenti_upd_Manuale';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Prima nota: salva un movimento manuale, cioè un'entrata o un'uscita dell'azienda non legata a rate di fatture
-- (spese bancarie, prelievi, versamenti, stipendi; un giroconto sono due movimenti). Con @Id vuoto lo
-- inserisce, altrimenti lo modifica. @Tipo: E entrata, U uscita.
-- Si modificano solo i movimenti manuali: i pagamenti delle fatture (quelli con quote in tblFattureRatePagamenti)
-- si registrano e si annullano nello scadenziario.
-- Restituisce l'Id del movimento.
CREATE OR ALTER PROCEDURE dbo.uspPagamenti_upd_Manuale
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@DataRegistrazione DATE = NULL,
	@DataContabile DATE = NULL,
	@IdBancaCassa CHAR(16) = NULL,
	@IdModalita CHAR(4) = NULL,
	@IdConto CHAR(16) = NULL,
	@Causale VARCHAR(150) = NULL,
	@Importo DECIMAL(18, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Le select propongono come prima voce "(Selezionare)" con Id a zeri: vale come non indicato
		SET @Id = NULLIF(NULLIF(LTRIM(RTRIM(@Id)), ''), REPLICATE('0', 16));
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @IdBancaCassa = NULLIF(NULLIF(LTRIM(RTRIM(@IdBancaCassa)), ''), REPLICATE('0', 16));
		SET @IdModalita = NULLIF(NULLIF(LTRIM(RTRIM(@IdModalita)), ''), REPLICATE('0', 4));
		SET @IdConto = NULLIF(NULLIF(LTRIM(RTRIM(@IdConto)), ''), REPLICATE('0', 16));
		SET @Causale = dbo.ufnStringhe_get_SenzaSpazi(@Causale, 0, 1);
		SET @DataRegistrazione = ISNULL(@DataRegistrazione, CAST(GETDATE() AS DATE));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('E', 'U')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare se il movimento è un''entrata o un''uscita';
			GOTO BRANCH_END;
		END
		IF @DataContabile IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data contabile del movimento';
			GOTO BRANCH_END;
		END
		IF @IdBancaCassa IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la banca o la cassa';
			GOTO BRANCH_END;
		END
		IF ISNULL(@Importo, 0) <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo del movimento deve essere maggiore di zero';
			GOTO BRANCH_END;
		END
		IF @Causale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la causale del movimento';
			GOTO BRANCH_END;
		END
		IF LEN(@Causale) > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La causale non può superare i 100 caratteri';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il movimento appartiene all'azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		-- Movimento esistente: attivo, dell'azienda e manuale. Banca, cassa e conto già sul movimento restano
		-- validi anche se nel frattempo sono stati cancellati
		DECLARE @idBancaCassaAttuale CHAR(16);
		DECLARE @idContoAttuale CHAR(16);
		IF @Id IS NOT NULL
		BEGIN
			DECLARE @trovato BIT = 0;
			SELECT
				@trovato = 1,
				@idBancaCassaAttuale = IdBancaCassa,
				@idContoAttuale = IdConto
			FROM dbo.tblPagamenti
			WHERE
				Id = @Id
				AND IdSede = @idAzienda
				AND Lock = 0;

			IF @trovato = 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari, o il movimento non esiste o è già stato cancellato';
				GOTO BRANCH_END;
			END
			IF EXISTS (SELECT 1 FROM dbo.tblFattureRatePagamenti WHERE IdPagamento = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il pagamento di una fattura si registra e si annulla nello scadenziario';
				GOTO BRANCH_END;
			END
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblBancheCasse
			WHERE
				Id = @IdBancaCassa
				AND IdSede = @idAzienda
				AND (Lock = 0 OR Id = @idBancaCassaAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La banca o cassa indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @IdModalita IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = @IdModalita)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La modalità di pagamento indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @IdConto IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblFattureConti
			WHERE
				Id = @IdConto
				AND IdSede = @idAzienda
				AND (Lock = 0 OR Id = @idContoAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il conto indicato non esiste';
			GOTO BRANCH_END;
		END

		IF @Id IS NULL
		BEGIN
			-- uspId_get FUORI dalla transazione
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @Id OUTPUT;

			BEGIN TRANSACTION;
				INSERT dbo.tblPagamenti (Id, IdSede, IdBancaCassa, IdModalita, IdConto, Tipo, Causale, DataRegistrazione, DataContabile, Importo, Lock)
				VALUES (@Id, @idAzienda, @IdBancaCassa, @IdModalita, @IdConto, @Tipo, @Causale, @DataRegistrazione, @DataContabile, @Importo, 0);
			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			BEGIN TRANSACTION;
				UPDATE dbo.tblPagamenti
				SET
					IdBancaCassa = @IdBancaCassa,
					IdModalita = @IdModalita,
					IdConto = @IdConto,
					Tipo = @Tipo,
					Causale = @Causale,
					DataRegistrazione = @DataRegistrazione,
					DataContabile = @DataContabile,
					Importo = @Importo
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Movimento non trovato o già cancellato';
					GOTO BRANCH_END;
				END
			COMMIT TRANSACTION;

			-- Log FUORI dalla transazione
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';
		END

		SELECT Id = @Id;

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

PRINT 'uspPagamenti_del_Manuale';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Prima nota: cancella un movimento manuale. Come per i pagamenti annullati, il movimento resta in archivio
-- come cancellato (Lock = 4) e non c'è ripristino: va inserito di nuovo.
-- Solo i movimenti manuali: il pagamento di una fattura si annulla nello scadenziario (uspPagamenti_del).
CREATE OR ALTER PROCEDURE dbo.uspPagamenti_del_Manuale
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
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il movimento deve essere attivo e dell'azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblPagamenti p
				INNER JOIN dbo.tblSessioni e ON p.IdSede = e.IdAzienda
			WHERE
				p.Id = @Id
				AND e.Id = @IdSessione
				AND p.Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il movimento non esiste o è già stato cancellato';
			GOTO BRANCH_END;
		END
		IF EXISTS (SELECT 1 FROM dbo.tblFattureRatePagamenti WHERE IdPagamento = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il pagamento di una fattura si annulla nello scadenziario';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblPagamenti
			SET Lock = 4
			WHERE
				Id = @Id
				AND Lock = 0;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Movimento non trovato o già cancellato';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';

		SELECT ReturnValue = @returnValue;

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

PRINT 'uspBancheCasse_get';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_get
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
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblBancheCasse c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblBancheCasse WHERE Id = @Id AND Lock <= 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Banca o cassa non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			b.Id,
			b.IdSede,
			b.Tipo,
			b.Nome,
			b.Iban,
			b.CodiceSia,
			b.Bic,
			b.SaldoIniziale,
			b.DataSaldoIniziale,
			b.Lock
		FROM dbo.tblBancheCasse b
		WHERE
			b.Id = @Id
			AND b.Lock <= 2;

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

PRINT 'uspBancheCasse_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Iban VARCHAR(50) = NULL,
	@CodiceSia VARCHAR(20) = NULL,
	@Bic VARCHAR(20) = NULL,
	@SaldoIniziale DECIMAL(18, 2) = NULL,
	@DataSaldoIniziale DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		-- IBAN, codice SIA e BIC: maiuscolo e senza spazi interni
		SET @Iban = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@Iban)), ' ', '')), '');
		SET @CodiceSia = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@CodiceSia)), ' ', '')), '');
		SET @Bic = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@Bic)), ' ', '')), '');

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
		IF @Tipo IS NULL OR @Tipo NOT IN ('B', 'C')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il tipo (banca o cassa)';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL OR LEN(@Nome) < 3
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@Tipo = 'B', 'Indicare il nome della banca (almeno 3 caratteri)', 'Indicare il nome della cassa (almeno 3 caratteri)');
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = c.IdSede
		FROM
			dbo.tblBancheCasse c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Una cassa non ha coordinate bancarie
		IF @Tipo = 'C'
		BEGIN
			SET @Iban = NULL;
			SET @CodiceSia = NULL;
			SET @Bic = NULL;
		END

		-- Banca: IBAN obbligatorio. Il formato di IBAN, BIC e codice SIA è controllato dall'applicazione
		-- (Strings.cs): qui si protegge solo la lunghezza delle colonne
		IF @Tipo = 'B' AND @Iban IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il codice IBAN';
			GOTO BRANCH_END;
		END
		IF LEN(@Iban) > 34
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''IBAN non può superare i 34 caratteri';
			GOTO BRANCH_END;
		END
		IF LEN(@Bic) > 11
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice BIC non può superare gli 11 caratteri';
			GOTO BRANCH_END;
		END
		IF LEN(@CodiceSia) > 5
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice SIA non può superare i 5 caratteri';
			GOTO BRANCH_END;
		END

		-- Saldo iniziale, per la prima nota: importo (anche negativo) e data si indicano insieme. È il saldo
		-- all'inizio del giorno indicato: il saldo progressivo parte da lì
		IF (@SaldoIniziale IS NULL AND @DataSaldoIniziale IS NOT NULL) OR (@SaldoIniziale IS NOT NULL AND @DataSaldoIniziale IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Per il saldo iniziale indicare sia l''importo sia la data';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un'altra banca o cassa attiva con lo stesso nome nella stessa azienda
		IF EXISTS (
			SELECT 1
			FROM dbo.tblBancheCasse
			WHERE
				Id <> @Id
				AND IdSede = @idAzienda
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra banca o cassa con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblBancheCasse
			SET
				Lock = 0,
				Tipo = @Tipo,
				Nome = @Nome,
				Iban = @Iban,
				CodiceSia = @CodiceSia,
				Bic = @Bic,
				SaldoIniziale = @SaldoIniziale,
				DataSaldoIniziale = @DataSaldoIniziale
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Banca o cassa non trovata o già eliminata';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

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

PRINT 'uspFattureConti_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureConti_del
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureConti WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblFattureConti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock FROM dbo.tblFattureConti WHERE Id = @Id);

		-- ── CASO 1: conto attivo (Lock = 0) → soft delete ────────────────────
		IF @lock = 0
		BEGIN
			-- Un conto usato nelle righe di una fattura non cancellata resta
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblFattureRigheImporti i
					INNER JOIN dbo.tblFattureRighe r ON i.Id = r.Id
					INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				WHERE
					i.IdConto = @Id
					AND f.Lock IN (0, 2)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un conto usato nelle righe di una fattura non può essere cancellato';
				GOTO BRANCH_END;
			END
			-- Lo stesso per un conto indicato in un movimento manuale attivo della prima nota
			IF EXISTS (SELECT 1 FROM dbo.tblPagamenti WHERE IdConto = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un conto usato in un movimento della prima nota non può essere cancellato';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblFattureConti
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Conto non trovato o già eliminato';
					GOTO BRANCH_END;
				END

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END

		-- ── CASO 2: conto in bozza (Lock = 2) → hard delete ──────────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblFattureConti
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellato (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il conto è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
			GOTO BRANCH_END;
		END

		END

		SELECT @returnValue AS ReturnValue;

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
