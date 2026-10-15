CREATE OR ALTER PROCEDURE [dbo].[uspServiziAssegnati_del]
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

		-- Controllo permesso: SRV (Gestione Servizi) O SRA (Servizi Assegnati)
		DECLARE @permessoSrv TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		DECLARE @permessoSra TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		IF 2 > @permessoSrv AND 2 > @permessoSra
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: verifica prima di tutto se il servizio esiste, indipendentemente dalla
		-- titolarità sottostante — mai esistito o già cancellato (es. doppio invio della
		-- richiesta di annullamento lato UI) viene trattato come cancellazione già avvenuta con
		-- successo, non come errore.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblServizi
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Verifica che il servizio appartenga a un calendario accessibile dalla sessione e sia assegnato all'utente
		-- della sessione: in Servizi > Assegnati ognuno vede e gestisce solo i propri servizi
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			INNER JOIN dbo.tblEventiUtenti u ON e.Id = u.Id
			INNER JOIN dbo.tblSessioni ss ON u.IdUtente = ss.IdUtente AND ss.Id = @IdSessione
			WHERE s.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT;
		SELECT @lock = e.Lock
		FROM dbo.tblServizi s
		INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
		WHERE s.Id = @Id;

		-- ── CASO 1: servizio attivo (Lock = 0) → soft delete ─────────────
		IF @lock = 0
		BEGIN
			BEGIN TRANSACTION;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				UPDATE e
				SET Lock = 4
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.Id = @Id
					AND e.Lock = 0;

				UPDATE e
				SET Lock = 4
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblRicorrenzeEccezioni e ON s.IdEvento = e.Id
				WHERE
					s.Id = @Id
					AND e.Lock = 0;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());

			COMMIT TRANSACTION;

			-- Log FUORI dalla transazione
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END

		-- ── CASO 2: servizio in bozza (Lock = 2) → hard delete ───────────
		ELSE IF @lock = 2
		BEGIN
			-- Legge tutti i dati necessari FUORI dalla transazione
			DECLARE @IdEvento CHAR(16);
			SELECT @IdEvento = IdEvento
			FROM dbo.tblServizi
			WHERE Id = @Id;

			DECLARE @idFirmaRichiedente UNIQUEIDENTIFIER;
			DECLARE @idFirmaEsecutore UNIQUEIDENTIFIER;

			SELECT @idFirmaRichiedente = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'R';

			SELECT @idFirmaEsecutore = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'E';

			BEGIN TRANSACTION;
				-- Figlie di tblEventi (FK dirette) → prima di tblEventi
				DELETE dbo.tblEventiUtenti
				WHERE Id = @IdEvento;
				DELETE dbo.tblRicorrenzeEccezioni
				WHERE IdEvento = @IdEvento;
				DELETE dbo.tblRicorrenze
				WHERE Id = @IdEvento;
				DELETE dbo.tblEventiProprieta
				WHERE Id = @IdEvento;
				DELETE dbo.tblEventiFirme
				WHERE Id = @IdEvento;
				DELETE dbo.tblEventiEtichette
				WHERE Id = @IdEvento;

				-- Servizio e Osepe associati
				DELETE dbo.tblServiziOsepe
				WHERE Id = @Id;
				DELETE dbo.tblServizi
				WHERE Id = @Id;

				-- Firme (dopo aver eliminato tblEventiFirme)
				DELETE dbo.tblFirme
				WHERE Id IN (@idFirmaRichiedente, @idFirmaEsecutore);

				-- Evento
				DELETE dbo.tblEventi
				WHERE Id = @IdEvento;

				-- Pulizia log e Id
				DELETE dbo.tblIdCancellati
				WHERE Id IN (@Id, @IdEvento);
				DELETE dbo.tblIdLog
				WHERE Id IN (@Id, @IdEvento);
				DELETE dbo.tblId
				WHERE Id IN (@Id, @IdEvento);
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: Lock in stato non gestito ────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il servizio è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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
		THROW 50001, @returnMessage, 1
	END

END;


