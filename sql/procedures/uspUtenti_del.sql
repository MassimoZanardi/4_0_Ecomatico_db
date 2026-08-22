CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametri
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

		-- Controllo permesso sulla funzione (UTE = Gestione Utenti)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'UTE',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idDominioSessione CHAR(16);
		SELECT @idDominioSessione = a.IdDominio
		FROM dbo.tblSessioni s INNER JOIN dbo.tblUtenti a ON a.Id = s.IdUtente
		WHERE s.Id = @IdSessione;

		-- Idempotenza: verifica prima di tutto se l'utente esiste, indipendentemente dalla
		-- titolarità sottostante — mai esistito o già cancellato (es. doppio invio della
		-- richiesta di annullamento lato UI) viene trattato come cancellazione già avvenuta con
		-- successo, non come errore.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblUtenti
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Titolarità: Admin dello stesso Dominio dell'utente target, oppure Admin di un Dominio Master.
		-- Il bypass Master è intenzionale (stesso schema di uspSedi_*): un Master-admin deve poter
		-- gestire utenti di qualsiasi dominio, non solo del proprio.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblUtenti
		WHERE
			Id = @Id
			AND IdDominio = @idDominioSessione
		)
		AND NOT EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE
			Id = @idDominioSessione
			AND [Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Legge Lock dentro la transazione con UPDLOCK:
		-- impedisce che un altro processo modifichi il record
		-- tra la lettura e i DML successivi
		BEGIN TRANSACTION;

			DECLARE @lock INT;
			SELECT @lock = Lock
			FROM dbo.tblUtenti WITH (UPDLOCK)
			WHERE Id = @Id;

			IF @lock IS NULL
			BEGIN
				-- Idempotenza (race condition): l'utente è stato cancellato da un'altra sessione
				-- tra il controllo di esistenza sopra e questa lettura con UPDLOCK — stesso
				-- trattamento, successo silenzioso (il COMMIT sottostante chiude una transazione
				-- senza modifiche, innocuo).
				SET @returnValue = 0;
			END

			-- ── CASO 1: utente attivo (Lock = 0) → soft delete ──────────────
			ELSE IF @lock = 0
			BEGIN
				-- Il master non può essere cancellato
				-- Controllo su tabelle base invece di viewUtenti
				IF EXISTS (
					SELECT 1
					FROM dbo.tblUtenti u
					INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
					WHERE
						u.Id = @Id
						AND u.Lock = 0
						AND d.[Master] = 1 -- dominio Master = visibilità globale
				)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'L''utente Master non può essere cancellato';
					GOTO BRANCH_END;
				END

				-- L'utente connesso non può cancellare se stesso
				IF EXISTS (
					SELECT 1
					FROM dbo.tblSessioni
					WHERE
						Id = @IdSessione
						AND IdUtente = @Id
				)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'L''utente connesso non può cancellare se stesso';
					GOTO BRANCH_END;
				END

				-- Soft delete: marca l'utente come cancellato
				UPDATE dbo.tblUtenti
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock <= 2;
				--                            ↑ Lock = 4 = cancellato logicamente

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			END

			-- ── CASO 2: utente in bozza (Lock = 2) → hard delete ────────────
			ELSE IF @lock = 2
			BEGIN
				-- Cancellazione fisica a cascata di tutti i dati dell'utente
				DELETE dbo.tblEventiUtenti
				WHERE IdUtente = @Id;
				DELETE dbo.tblUtentiDefault
				WHERE Id = @Id;
				DELETE dbo.tblUtentiFunzioni
				WHERE Id = @Id;
				DELETE dbo.tblUtentiSediInterne
				WHERE Id = @Id;
				DELETE dbo.tblUtentiPassword
				WHERE Id = @Id;
				DELETE dbo.tblUtenti
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			END

			-- ── CASO 3: Lock in stato non gestito ────────────────────────────
			ELSE
			BEGIN
				-- Lock = 4 (già cancellato) o qualsiasi altro valore imprevisto
				SET @returnValue = -1;
				SET @returnMessage = 'L''utente è già in uno stato non modificabile (Lock = '
									 + CAST(@lock AS VARCHAR(5)) + ')';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		IF @lock = 0
			EXEC dbo.uspId_upd
				@Id = @Id,
				@IdSessione = @IdSessione,
				@Operazione = 'D';

		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;


