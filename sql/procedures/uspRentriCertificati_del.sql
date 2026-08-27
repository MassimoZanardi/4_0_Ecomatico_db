SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriCertificati_del]
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
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: un @Id mai esistito o già cancellato è trattato come cancellazione
		-- già avvenuta con successo, non come errore.
		IF NOT EXISTS (SELECT 1 FROM dbo.tblRentriCertificati WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

			-- Controlla il permesso sul record (titolarità)
			IF NOT EXISTS (
				SELECT 1
				FROM
					dbo.tblRentriCertificati c
					INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
				WHERE
					c.Id = @Id
					AND e.Id = @IdSessione)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			-- Blocca la cancellazione se esistono Credenziali attive collegate
			IF EXISTS (
				SELECT 1
				FROM dbo.tblRentriCredenziali
				WHERE
					IdCertificato = @Id
					AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Impossibile eliminare: il certificato è usato da almeno una credenziale';
				GOTO BRANCH_END;
			END

			DECLARE @lock INT = (SELECT Lock FROM dbo.tblRentriCertificati WHERE Id = @Id);

			-- ── CASO 1: certificato attivo (Lock = 0) → soft delete ────────────────
			-- La riga hub NON viene toccata: resta l'unica copia dei dati (File/Password)
			-- e permette l'Undo senza perdita di dati.
			IF @lock = 0
			BEGIN
				BEGIN TRANSACTION;
					UPDATE dbo.tblRentriCertificati
					SET Lock = 4
					WHERE
						Id = @Id
						AND Lock = 0;

					IF @@ROWCOUNT = 0
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Certificato non trovato o già eliminato';
						GOTO BRANCH_END;
					END

					IF @Reset = 1
						DELETE dbo.tblIdCancellati WHERE IdSessione = @IdSessione;
					ELSE
						DELETE dbo.tblIdCancellati WHERE Id = @Id;

					INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
					VALUES (@Id, @IdSessione, GETDATE());
				COMMIT TRANSACTION;

				EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
			END

			-- ── CASO 2: certificato in bozza (Lock = 2) → hard delete ──────────────
			-- Nessuna riga hub esiste ancora a questo punto (creata solo da _upd).
			ELSE IF @lock = 2
			BEGIN
				BEGIN TRANSACTION;
					DELETE dbo.tblRentriCertificati WHERE Id = @Id;
					DELETE dbo.tblIdCancellati WHERE Id = @Id;
					DELETE dbo.tblIdLog WHERE Id = @Id;
					DELETE dbo.tblId WHERE Id = @Id;
				COMMIT TRANSACTION;
			END

			-- ── CASO 3: Lock in stato non gestito ───────────────────────────────────
			ELSE
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il certificato è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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
