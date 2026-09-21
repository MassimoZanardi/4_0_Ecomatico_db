SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_del
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
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWLotti
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEoWLotti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblEoWLotti
		WHERE Id = @Id);

		-- ── CASO 1: lotto attivo (Lock = 0) → soft delete ────────────────────
		IF @lock = 0
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdLotto = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un lotto con registrazioni associate non può essere cancellato';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni
				WHERE IdLotto = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un lotto usato in una configurazione di allocazione non può essere cancellato';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblEoWLotti
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Lotto non trovato o già eliminato';
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

		-- ── CASO 2: lotto in bozza (Lock = 2) → hard delete ──────────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdLotto = @Id;
				DELETE dbo.tblEoWLottiAllocazioni
				WHERE IdLotto = @Id;
				DELETE dbo.tblEoWLotti
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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
