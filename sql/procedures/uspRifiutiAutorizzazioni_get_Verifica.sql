SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiAutorizzazioni_get_Verifica]
	@IdSessione CHAR(16) = NULL,
	@Data DATE = NULL,
	@IdEer CHAR(6) = NULL,
	@IdAutorizzazioneProduttoreDetentore CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore1 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore2 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore3 CHAR(16) = NULL,
	@IdAutorizzazioneDestinatario CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario1 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario2 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario3 CHAR(16) = NULL,
	@IdAttivitaRs CHAR(2) = NULL,
	@IdTipoTrasporto1 CHAR(1) = NULL,
	@TargaMotrice VARCHAR(20) = NULL,
	@TargaRimorchio VARCHAR(20) = NULL,
	@ConducenteNome VARCHAR(50) = NULL,
	@ConducenteCognome VARCHAR(50) = NULL,
	@TrasportoAdr BIT = 0,
	@ControlloScadenze BIT = 1,
	@ControlloTarghe BIT = 1,
	@ControlloConducenti BIT = 1,
	@ControlloPatenti BIT = 1,
	@ControlloAttivita BIT = 1
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdAutorizzazioneProduttoreDetentore = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneProduttoreDetentore)), '');
		SET @IdAutorizzazioneTrasportatore1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore1)), '');
		SET @IdAutorizzazioneTrasportatore2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore2)), '');
		SET @IdAutorizzazioneTrasportatore3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore3)), '');
		SET @IdAutorizzazioneDestinatario = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneDestinatario)), '');
		SET @IdAutorizzazioneIntermediario1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario1)), '');
		SET @IdAutorizzazioneIntermediario2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario2)), '');
		SET @IdAutorizzazioneIntermediario3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario3)), '');
		SET @IdAttivitaRs = NULLIF(LTRIM(RTRIM(@IdAttivitaRs)), '');
		SET @IdTipoTrasporto1 = NULLIF(LTRIM(RTRIM(@IdTipoTrasporto1)), '');
		SET @TargaMotrice = dbo.ufnStringhe_get_SenzaSpazi(@TargaMotrice, 0, 1);
		SET @TargaRimorchio = dbo.ufnStringhe_get_SenzaSpazi(@TargaRimorchio, 0, 1);
		SET @ConducenteNome = dbo.ufnStringhe_get_SenzaSpazi(@ConducenteNome, 0, 1);
		SET @ConducenteCognome = dbo.ufnStringhe_get_SenzaSpazi(@ConducenteCognome, 0, 1);
		SET @TrasportoAdr = ISNULL(@TrasportoAdr, 0);
		SET @ControlloScadenze = ISNULL(@ControlloScadenze, 1);
		SET @ControlloTarghe = ISNULL(@ControlloTarghe, 1);
		SET @ControlloConducenti = ISNULL(@ControlloConducenti, 1);
		SET @ControlloPatenti = ISNULL(@ControlloPatenti, 1);
		SET @ControlloAttivita = ISNULL(@ControlloAttivita, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Data IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Data non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @sediZeri CHAR(16) = REPLICATE('0', 16);
		-- Delimitatore (non stampabile) usato per marcare il "soggetto" di ogni messaggio,
		-- così il livello di presentazione (Razor) puo' evidenziarlo in grassetto senza dover
		-- fare parsing testuale ne' inserire HTML qui (mai HTML diretto su dati utente: XSS).
		DECLARE @b CHAR(1) = CHAR(2);
		DECLARE @messaggi TABLE (Ordine INT IDENTITY(1,1), Messaggio VARCHAR(300));

		-- 1) Scadenza delle autorizzazioni associate (tutte quelle valorizzate)
		IF @ControlloScadenze = 1
		BEGIN
			DECLARE @ruoli TABLE (RuoloLabel VARCHAR(30), IdAutorizzazione CHAR(16));
			INSERT INTO @ruoli (RuoloLabel, IdAutorizzazione)
			SELECT * FROM (VALUES
				('Produttore/Detentore', @IdAutorizzazioneProduttoreDetentore),
				('1° Trasportatore', @IdAutorizzazioneTrasportatore1),
				('2° Trasportatore', @IdAutorizzazioneTrasportatore2),
				('3° Trasportatore', @IdAutorizzazioneTrasportatore3),
				('Destinatario', @IdAutorizzazioneDestinatario),
				('1° Intermediario', @IdAutorizzazioneIntermediario1),
				('2° Intermediario', @IdAutorizzazioneIntermediario2),
				('3° Intermediario', @IdAutorizzazioneIntermediario3)
			) AS v(RuoloLabel, IdAutorizzazione)
			WHERE v.IdAutorizzazione IS NOT NULL AND v.IdAutorizzazione <> @sediZeri;

			INSERT INTO @messaggi (Messaggio)
			SELECT
				'L''autorizzazione ' + @b + r.RuoloLabel + ' (n. ' + ISNULL(a.Numero, '') + ')' + @b + ' è scaduta il ' + CONVERT(VARCHAR(10), a.DataFine, 103)
			FROM
				@ruoli r
				INNER JOIN dbo.tblRifiutiAutorizzazioni a ON r.IdAutorizzazione = a.Id
			WHERE
				a.DataFine IS NOT NULL
				AND a.DataFine < @Data;
		END

		-- Solo per il 1° trasportatore con trasporto "G" (Terrestre) ha senso verificare targhe/conducente/patenti
		DECLARE @isTerrestre BIT = CAST(IIF(@IdTipoTrasporto1 = 'G' AND @IdAutorizzazioneTrasportatore1 IS NOT NULL AND @IdAutorizzazioneTrasportatore1 <> @sediZeri, 1, 0) AS BIT);
		DECLARE @trasportatoreTarghe BIT = 0;
		DECLARE @trasportatoreConducenti BIT = 0;
		IF @isTerrestre = 1
		BEGIN
			SELECT
				@trasportatoreTarghe = ISNULL(ru.Targhe, 0),
				@trasportatoreConducenti = ISNULL(ru.Conducenti, 0)
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblRifiutiRuoli ru ON a.IdRuolo = ru.Id
			WHERE a.Id = @IdAutorizzazioneTrasportatore1;
		END

		-- 2) Targa motrice
		IF @ControlloTarghe = 1 AND @isTerrestre = 1 AND @trasportatoreTarghe = 1 AND @TargaMotrice IS NOT NULL
		BEGIN
			IF NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioniTarghe WHERE Id = @IdAutorizzazioneTrasportatore1 AND Rimorchio = 0 AND Targa = @TargaMotrice)
			BEGIN
				INSERT INTO @messaggi (Messaggio) VALUES ('La targa motrice ' + @b + @TargaMotrice + @b + ' non è presente nell''autorizzazione del trasportatore');
			END
			ELSE IF @IdEer IS NOT NULL AND (
				NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioniEer WHERE Id = @IdAutorizzazioneTrasportatore1 AND IdEer = @IdEer)
				OR EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id = @IdAutorizzazioneTrasportatore1 AND Targa = @TargaMotrice AND IdEer = @IdEer)
			)
			BEGIN
				INSERT INTO @messaggi (Messaggio) VALUES ('La targa motrice ' + @b + @TargaMotrice + @b + ' non è abilitata per il codice EER ' + @IdEer);
			END
		END

		-- 3) Targa rimorchio
		IF @ControlloTarghe = 1 AND @isTerrestre = 1 AND @trasportatoreTarghe = 1 AND @TargaRimorchio IS NOT NULL
		BEGIN
			IF NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioniTarghe WHERE Id = @IdAutorizzazioneTrasportatore1 AND Rimorchio = 1 AND Targa = @TargaRimorchio)
			BEGIN
				INSERT INTO @messaggi (Messaggio) VALUES ('La targa rimorchio ' + @b + @TargaRimorchio + @b + ' non è presente nell''autorizzazione del trasportatore');
			END
			ELSE IF @IdEer IS NOT NULL AND (
				NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioniEer WHERE Id = @IdAutorizzazioneTrasportatore1 AND IdEer = @IdEer)
				OR EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id = @IdAutorizzazioneTrasportatore1 AND Targa = @TargaRimorchio AND IdEer = @IdEer)
			)
			BEGIN
				INSERT INTO @messaggi (Messaggio) VALUES ('La targa rimorchio ' + @b + @TargaRimorchio + @b + ' non è abilitata per il codice EER ' + @IdEer);
			END
		END

		-- 4/5/6) Conducente e patenti
		IF (@ControlloConducenti = 1 OR @ControlloPatenti = 1) AND @isTerrestre = 1 AND @trasportatoreConducenti = 1 AND @ConducenteNome IS NOT NULL AND @ConducenteCognome IS NOT NULL
		BEGIN
			DECLARE @scadenzaPatente DATE;
			DECLARE @scadenzaPatenteAdr DATE;
			DECLARE @conducenteTrovato BIT = 0;

			SELECT
				@conducenteTrovato = 1,
				@scadenzaPatente = ScadenzaPatente,
				@scadenzaPatenteAdr = ScadenzaPatenteAdr
			FROM dbo.tblRifiutiAutorizzazioniConducenti
			WHERE Id = @IdAutorizzazioneTrasportatore1 AND Nome = @ConducenteNome AND Cognome = @ConducenteCognome;

			IF @ControlloConducenti = 1 AND @conducenteTrovato = 0
			BEGIN
				INSERT INTO @messaggi (Messaggio) VALUES ('Il conducente ' + @b + @ConducenteNome + ' ' + @ConducenteCognome + @b + ' non è presente nell''autorizzazione del trasportatore');
			END

			IF @ControlloPatenti = 1 AND @conducenteTrovato = 1
			BEGIN
				IF @scadenzaPatente IS NULL
				BEGIN
					INSERT INTO @messaggi (Messaggio) VALUES ('Non è indicata la scadenza della patente del conducente ' + @b + @ConducenteNome + ' ' + @ConducenteCognome + @b);
				END
				ELSE IF @scadenzaPatente < @Data
				BEGIN
					INSERT INTO @messaggi (Messaggio) VALUES ('La patente del conducente ' + @b + @ConducenteNome + ' ' + @ConducenteCognome + @b + ' è scaduta il ' + CONVERT(VARCHAR(10), @scadenzaPatente, 103));
				END

				IF @TrasportoAdr = 1
				BEGIN
					IF @scadenzaPatenteAdr IS NULL
					BEGIN
						INSERT INTO @messaggi (Messaggio) VALUES ('Non è indicata la scadenza della patente ADR del conducente ' + @b + @ConducenteNome + ' ' + @ConducenteCognome + @b);
					END
					ELSE IF @scadenzaPatenteAdr < @Data
					BEGIN
						INSERT INTO @messaggi (Messaggio) VALUES ('La patente ADR del conducente ' + @b + @ConducenteNome + ' ' + @ConducenteCognome + @b + ' è scaduta il ' + CONVERT(VARCHAR(10), @scadenzaPatenteAdr, 103));
					END
				END
			END
		END

		-- 7) Attività di recupero/smaltimento del destinatario
		IF @ControlloAttivita = 1 AND @IdAttivitaRs IS NOT NULL AND @IdAutorizzazioneDestinatario IS NOT NULL AND @IdAutorizzazioneDestinatario <> @sediZeri
		BEGIN
			DECLARE @destinatarioAttivita BIT = 0;
			DECLARE @attivitaCodice VARCHAR(3);
			SELECT @attivitaCodice = Codice FROM dbo.tblRifiutiAttivitaRecuperoSmaltimento WHERE Id = @IdAttivitaRs;
			SELECT @destinatarioAttivita = ISNULL(ru.Attivita, 0)
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblRifiutiRuoli ru ON a.IdRuolo = ru.Id
			WHERE a.Id = @IdAutorizzazioneDestinatario;

			IF @destinatarioAttivita = 1 AND NOT EXISTS (
				SELECT 1 FROM dbo.tblRifiutiAutorizzazioniAttivita WHERE Id = @IdAutorizzazioneDestinatario AND IdAttivita = @IdAttivitaRs
			)
			BEGIN
				INSERT INTO @messaggi (Messaggio) VALUES ('L''attività di recupero/smaltimento ' + @b + ISNULL(@attivitaCodice, @IdAttivitaRs) + @b + ' non è compresa nell''autorizzazione del destinatario');
			END
		END

		SELECT Messaggio FROM @messaggi ORDER BY Ordine;

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
