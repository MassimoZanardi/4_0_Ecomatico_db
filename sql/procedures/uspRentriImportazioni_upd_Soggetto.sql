SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: risoluzione di un soggetto letto da RENTRI (sezione "Soggetti" dell'anteprima).
--   @Azione 'A' abbina: @IdAutorizzazione (autorizzazione esistente del ruolo, usata com'è) oppure @IdSede (sede
--               esistente a cui aggiungere all'importazione l'autorizzazione con il numero di RENTRI);
--   @Azione 'C' completa: dati obbligatori per creare il soggetto che manca (nome, partita IVA, comune o località
--               estera, CAP, indirizzo). Valgono per tutti i soggetti con lo stesso codice fiscale ancora da
--               completare: il soggetto si crea una volta sola, con un'autorizzazione per ogni ruolo e numero;
--   @Azione 'R' ripristina l'abbinamento automatico.
-- Codice fiscale, denominazione e numeri restano quelli di RENTRI. Nessun dato viene scritto nell'anagrafica: lo fa
-- l'esecuzione dell'importazione. Subito dopo si rilancia l'analisi.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_upd_Soggetto]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdSoggetto INT = NULL,
	@Azione CHAR(1) = NULL,
	@IdAutorizzazione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@PartitaIva VARCHAR(20) = NULL,
	@IdNazione CHAR(3) = NULL,
	@IdComune VARCHAR(50) = NULL,
	@Localita VARCHAR(50) = NULL,
	@CAP VARCHAR(10) = NULL,
	@Indirizzo VARCHAR(50) = NULL,
	@NumeroCivico VARCHAR(10) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Azione = NULLIF(LTRIM(RTRIM(@Azione)), '');
		SET @IdAutorizzazione = NULLIF(LTRIM(RTRIM(@IdAutorizzazione)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdNazione = ISNULL(NULLIF(LTRIM(RTRIM(@IdNazione)), ''), '380');
		SET @Nome = NULLIF(LTRIM(RTRIM(@Nome)), '');
		SET @PartitaIva = NULLIF(UPPER(LTRIM(RTRIM(@PartitaIva))), '');
		SET @IdComune = NULLIF(LTRIM(RTRIM(@IdComune)), '');
		SET @Localita = NULLIF(LTRIM(RTRIM(@Localita)), '');
		SET @CAP = NULLIF(LTRIM(RTRIM(@CAP)), '');
		SET @Indirizzo = NULLIF(LTRIM(RTRIM(@Indirizzo)), '');
		SET @NumeroCivico = NULLIF(LTRIM(RTRIM(@NumeroCivico)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL OR @IdSoggetto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Azione IS NULL OR @Azione NOT IN ('A', 'C', 'R')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Azione non è valido';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		DECLARE @stato CHAR(1), @ruolo CHAR(1), @codiceFiscale VARCHAR(20), @idAziendaInterna CHAR(16);
		SELECT
			@stato = m.Stato,
			@ruolo = x.Ruolo,
			@codiceFiscale = x.CodiceFiscale,
			@idAziendaInterna = sr.IdAziendaInterna
		FROM
			dbo.tblRentriImportazioniSoggetti x
			INNER JOIN dbo.tblRentriImportazioni m ON x.IdImportazione = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi sr ON g.IdSede = sr.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			m.Id = @Id
			AND x.Id = @IdSoggetto;

		IF @ruolo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Soggetto non trovato';
			GOTO BRANCH_END;
		END
		IF @stato <> 'P'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importazione è già stata eseguita';
			GOTO BRANCH_END;
		END

		IF @Azione = 'A'
		BEGIN
			IF (@IdAutorizzazione IS NULL AND @IdSede IS NULL) OR (@IdAutorizzazione IS NOT NULL AND @IdSede IS NOT NULL)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Selezionare l''autorizzazione o la sede da abbinare';
				GOTO BRANCH_END;
			END

			-- Solo anagrafiche visibili all'azienda interna del registro
			DECLARE @idUtente CHAR(16) = (SELECT IdUtente FROM dbo.tblSessioni WHERE Id = @IdSessione);
			DECLARE @idSedeVerifica CHAR(16) = @IdSede;

			IF @IdAutorizzazione IS NOT NULL
				SELECT @idSedeVerifica = a.IdSede
				FROM dbo.tblRifiutiAutorizzazioni a
				WHERE a.Id = @IdAutorizzazione AND a.IdRuolo = @ruolo AND a.Disabilitata = 0 AND a.Lock < 2;

			IF @idSedeVerifica IS NULL OR NOT EXISTS (
				SELECT 1
				FROM
					dbo.ufnSedi_get_SediByUtente_List(@idUtente) u
					INNER JOIN dbo.tblSedi s ON u.Id = s.Id
				WHERE
					u.Id = @idSedeVerifica
					AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.Disabilitata = 0
					AND s.Lock < 2)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''autorizzazione o la sede selezionata non è disponibile';
				GOTO BRANCH_END;
			END
		END

		IF @Azione = 'C'
		BEGIN
			IF @Nome IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare il nome';
				GOTO BRANCH_END;
			END
			IF NOT EXISTS (SELECT 1 FROM dbo.tblNazioni WHERE Id = @IdNazione)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Nazione non valida';
				GOTO BRANCH_END;
			END
			IF @IdNazione = '380' AND (@IdComune IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.tblComuni WHERE Id = @IdComune))
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare il comune';
				GOTO BRANCH_END;
			END
			IF @IdNazione <> '380' AND @Localita IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare il paese estero';
				GOTO BRANCH_END;
			END
			IF @CAP IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare il CAP';
				GOTO BRANCH_END;
			END
			IF @IdNazione = '380' AND (LEN(@CAP) <> 5 OR @CAP LIKE '%[^0-9]%')
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'CAP non corretto';
				GOTO BRANCH_END;
			END
			IF @Indirizzo IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare l''indirizzo';
				GOTO BRANCH_END;
			END
			IF @IdNazione = '380' AND @PartitaIva IS NOT NULL AND (LEN(@PartitaIva) <> 11 OR @PartitaIva LIKE '%[^0-9]%')
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Partita Iva non corretta';
				GOTO BRANCH_END;
			END
		END

		BEGIN TRANSACTION;

			IF @Azione = 'A'
				UPDATE dbo.tblRentriImportazioniSoggetti
				SET
					Stato = 'U',
					IsModificato = 1,
					IdAutorizzazione = @IdAutorizzazione,
					IdSede = @IdSede
				WHERE IdImportazione = @Id AND Id = @IdSoggetto;

			-- Il completamento vale per tutti i soggetti con lo stesso codice fiscale ancora da completare (o già
			-- completati): un solo soggetto in anagrafica
			IF @Azione = 'C'
				UPDATE dbo.tblRentriImportazioniSoggetti
				SET
					Stato = 'C',
					IsModificato = 1,
					IdAutorizzazione = NULL,
					IdSede = NULL,
					Nome = @Nome,
					PartitaIva = @PartitaIva,
					IdNazione = @IdNazione,
					IdComune = IIF(@IdNazione = '380', @IdComune, NULL),
					Localita = IIF(@IdNazione = '380', NULL, @Localita),
					CAP = @CAP,
					Indirizzo = @Indirizzo,
					NumeroCivico = @NumeroCivico
				WHERE
					IdImportazione = @Id
					AND CodiceFiscale = @codiceFiscale
					AND (Id = @IdSoggetto OR Stato IN ('M', 'C'));

			IF @Azione = 'R'
				UPDATE dbo.tblRentriImportazioniSoggetti
				SET IsModificato = 0
				WHERE IdImportazione = @Id AND Id = @IdSoggetto;

		COMMIT TRANSACTION;

		EXEC dbo.uspRentriImportazioni_upd_Analisi @IdSessione = @IdSessione, @Id = @Id;

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
