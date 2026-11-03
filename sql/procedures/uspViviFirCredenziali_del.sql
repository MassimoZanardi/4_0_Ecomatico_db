SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirCredenziali_del]
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: un @Id mai esistito o già cancellato è trattato come cancellazione
		-- già avvenuta con successo, non come errore.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblViviFirCredenziali
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
					dbo.tblViviFirCredenziali c
					INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
				WHERE
					c.Id = @Id
					AND e.Id = @IdSessione
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			DECLARE @lock INT = (SELECT Lock
			FROM dbo.tblViviFirCredenziali
			WHERE Id = @Id);

			-- Una credenziale usata da un'azienda non si cancella: va prima tolta in Vivifir > Aziende
			IF EXISTS (SELECT 1
			FROM dbo.tblViviFirCredenzialiAziende
			WHERE IdCredenziale = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La credenziale è associata ad aziende: toglierla prima in Vivifir > Aziende';
				GOTO BRANCH_END;
			END

			-- ── CASO 1: credenziale attiva (Lock = 0) → soft delete ────────────────
			-- La riga hub resta (per l'Undo).
			IF @lock = 0
			BEGIN
				BEGIN TRANSACTION;
					UPDATE dbo.tblViviFirCredenziali
					SET Lock = 4
					WHERE
						Id = @Id
						AND Lock = 0;

					IF @@ROWCOUNT = 0
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Credenziale non trovata o già eliminata';
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

			-- ── CASO 2: credenziale in bozza (Lock = 2) → hard delete ──────────────
			-- Nessuna riga hub esiste ancora a questo punto (creata solo da _upd).
			ELSE IF @lock = 2
			BEGIN
				BEGIN TRANSACTION;
					DELETE dbo.tblViviFirCredenziali
					WHERE Id = @Id;
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;
					DELETE dbo.tblIdLog
					WHERE Id = @Id;
					DELETE dbo.tblId
					WHERE Id = @Id;
				COMMIT TRANSACTION;
			END

			-- ── CASO 3: Lock in stato non gestito ───────────────────────────────────
			ELSE
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La credenziale è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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
