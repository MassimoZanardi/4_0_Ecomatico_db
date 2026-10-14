SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione > Fatture clienti > Nuova > Tramite procedura automatica: riepilogo della verifica, mostrato nella
-- finestra "Verifica" prima di generare. Una riga con i conteggi di ciò che la generazione farebbe con gli stessi
-- criteri (stessi documenti e stessi gruppi di uspFatture_ins_Genera: ufnFattureGenera_get_Documenti), calcolati
-- su tutti i documenti, senza limite di righe.
--   Documenti: documenti del periodo non ancora fatturati (con @IncludiPreFatture anche quelli in pre-fattura).
--   Fatturabili, Fatture, Clienti, Imponibile: documenti che entrano in una fattura, fatture previste (una per
--        cliente e, secondo la scheda del cliente, per sede o per contratto), clienti e imponibile totale.
--   PreFatture, DocumentiPreFatture: pre-fatture che verrebbero convertite e loro documenti nel periodo.
--   ImportoStandard: fatturabili con l'importo standard perché il contratto non è valido alla data.
--   Annullati, NonFatturabili, SenzaImporto, SenzaCliente, SenzaRighe, SenzaIva: documenti che restano fuori,
--        per motivo (uno solo per documento, nell'ordine di ufnFattureGenera_get_Documenti.Esito).
--   GiaFatturati: documenti del periodo già in una fattura (solo informativo: non rientrano).
--   InPreFattura: documenti del periodo già in una pre-fattura, quando non si includono le pre-fatture.
--   DocumentiRifiuti, DocumentiMagazzino: i Documenti, divisi tra registrazioni dei rifiuti e DDT di magazzino.
-- @Rifiuti, @Magazzino: da quali documenti generare (registrazioni dei rifiuti, DDT di magazzino). I DDT entrano
-- solo con il modulo Magazzino attivo sul dominio.
-- Senza azienda nel contesto tutto a zero.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Genera_Riepilogo
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@Rifiuti BIT = 1,
	@Magazzino BIT = 0,
	@Servizi BIT = 0,
	@IncludiPreFatture BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @Rifiuti = ISNULL(@Rifiuti, 1);
		SET @Magazzino = ISNULL(@Magazzino, 0);
		SET @Servizi = ISNULL(@Servizi, 0);
		SET @IncludiPreFatture = ISNULL(@IncludiPreFatture, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataDa IS NULL OR @DataA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il periodo dei documenti da fatturare';
			GOTO BRANCH_END;
		END
		IF @DataA < @DataDa
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine del periodo non può precedere quella di inizio';
			GOTO BRANCH_END;
		END

		-- Permesso sulle fatture e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- I DDT entrano solo con il modulo Magazzino attivo sul dominio
		IF ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0) = 0
			SET @Magazzino = 0;
		-- I servizi entrano solo con il modulo Servizi attivo sul dominio
		IF ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('SRV', @IdSessione), 0) = 0
			SET @Servizi = 0;

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Documenti candidati, letti una volta sola
		DECLARE @doc TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IdModulo CHAR(3) COLLATE DATABASE_DEFAULT NOT NULL,
			IdClienteFornitore CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdPreFattura CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			GruppoSede CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			GruppoContratto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Imponibile DECIMAL(18, 2) NULL,
			Fatturabile BIT NOT NULL,
			Esito CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL
		);
		INSERT @doc (Id, IdModulo, IdClienteFornitore, IdPreFattura, GruppoSede, GruppoContratto, Imponibile, Fatturabile, Esito)
		SELECT
			d.Id,
			d.IdModulo,
			d.IdClienteFornitore,
			d.IdPreFattura,
			d.GruppoSede,
			d.GruppoContratto,
			d.Imponibile,
			d.Fatturabile,
			d.Esito
		FROM dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, NULL, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture, @Rifiuti, @Magazzino, @Servizi) d
		OPTION (RECOMPILE);

		-- Documenti del periodo già in una fattura o in una pre-fattura (stessa platea dei candidati:
		-- registrazioni confermate di un'operazione fatturabile, non rettifiche, dei registri che la sessione vede)
		DECLARE @giaFatturati INT = 0;
		DECLARE @inPreFattura INT = 0;
		SELECT
			@giaFatturati = ISNULL(SUM(IIF(f.IdTipo = 'TD00', 0, 1)), 0),
			@inPreFattura = ISNULL(SUM(IIF(f.IdTipo = 'TD00', 1, 0)), 0)
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi sr ON g.IdSede = sr.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON g.IdSede = x.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			INNER JOIN dbo.tblFattureDocumenti fd ON r.Id = fd.Id
			INNER JOIN dbo.tblFatture f ON fd.IdFattura = f.Id
		WHERE
			@Rifiuti = 1
			AND r.Lock = 0
			AND o.IsFatturabile = 1
			AND v.IsRettifica = 0
			AND f.Lock IN (0, 2)
			AND sr.IdAziendaInterna = @idAzienda
			AND r.[Data] >= @DataDa
			AND r.[Data] <= @DataA
			AND (@IdClienteFornitore IS NULL OR f.IdClienteFornitore = @IdClienteFornitore)
		OPTION (RECOMPILE);

		-- Lo stesso per i DDT di magazzino (stessa platea dei candidati: DDT emessi e confermati di un movimento di
		-- scarico con una causale fatturabile, delle sedi che la sessione vede)
		IF @Magazzino = 1
			SELECT
				@giaFatturati += ISNULL(SUM(IIF(f.IdTipo = 'TD00', 0, 1)), 0),
				@inPreFattura += ISNULL(SUM(IIF(f.IdTipo = 'TD00', 1, 0)), 0)
			FROM
				dbo.ufnImportiMagazzino_get_Documenti(NULL, @idAzienda, @DataDa, @DataA) doc
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON doc.IdSedeDdt = x.Id
				INNER JOIN dbo.tblFattureDocumenti fd ON doc.Id = fd.Id
				INNER JOIN dbo.tblFatture f ON fd.IdFattura = f.Id
			WHERE
				doc.Lock = 0
				AND doc.IsFatturabile = 1
				AND f.Lock IN (0, 2)
				AND (@IdClienteFornitore IS NULL OR f.IdClienteFornitore = @IdClienteFornitore)
			OPTION (RECOMPILE);

		SELECT
			Documenti = COUNT(*),
			DocumentiRifiuti = ISNULL(SUM(IIF(d.IdModulo = 'RIF', 1, 0)), 0),
			DocumentiMagazzino = ISNULL(SUM(IIF(d.IdModulo = 'MAG', 1, 0)), 0),
			Fatturabili = ISNULL(SUM(IIF(d.Fatturabile = 1, 1, 0)), 0),
			Fatture = (
				SELECT COUNT(*)
				FROM (SELECT DISTINCT IdClienteFornitore, GruppoSede, GruppoContratto FROM @doc WHERE Fatturabile = 1) q
			),
			Clienti = COUNT(DISTINCT IIF(d.Fatturabile = 1, d.IdClienteFornitore, NULL)),
			Imponibile = ISNULL(SUM(IIF(d.Fatturabile = 1, ISNULL(d.Imponibile, 0), 0)), 0),
			PreFatture = COUNT(DISTINCT d.IdPreFattura),
			DocumentiPreFatture = ISNULL(SUM(IIF(d.Esito = 'P', 1, 0)), 0),
			ImportoStandard = ISNULL(SUM(IIF(d.Esito = 'S', 1, 0)), 0),
			Annullati = ISNULL(SUM(IIF(d.Esito = 'A', 1, 0)), 0),
			NonFatturabili = ISNULL(SUM(IIF(d.Esito = 'N', 1, 0)), 0),
			SenzaImporto = ISNULL(SUM(IIF(d.Esito = 'I', 1, 0)), 0),
			SenzaCliente = ISNULL(SUM(IIF(d.Esito = 'C', 1, 0)), 0),
			SenzaRighe = ISNULL(SUM(IIF(d.Esito = 'R', 1, 0)), 0),
			SenzaIva = ISNULL(SUM(IIF(d.Esito = 'V', 1, 0)), 0),
			GiaFatturati = @giaFatturati,
			-- Con le pre-fatture incluse quei documenti sono già tra i candidati
			InPreFattura = IIF(@IncludiPreFatture = 1, 0, @inPreFattura)
		FROM @doc d;

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
