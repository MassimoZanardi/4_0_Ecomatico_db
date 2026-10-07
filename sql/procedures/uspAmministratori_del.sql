SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAmministratori_del
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

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblAmministratori WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità): scope azienda interna corrente della sessione
		DECLARE @lock INT;
		DECLARE @trovato BIT = 0;
		SELECT
			@trovato = 1,
			@lock = c.Lock
		FROM
			dbo.tblAmministratori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @trovato = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANM',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- ── CASO 1: scheda attiva (Lock = 0) → soft delete ───────────────────
		-- I soggetti amministrati restano sulla scheda per il ripristino; da subito possono
		-- essere assegnati a un altro amministratore
		IF @lock = 0
		BEGIN
			BEGIN TRANSACTION;
				UPDATE dbo.tblAmministratori
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Amministratore non trovato o già eliminato';
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

		-- ── CASO 2: scheda in bozza (Lock = 2) → hard delete ─────────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblAmministratoriSedi
				WHERE Id = @Id;
				DELETE dbo.tblAmministratori
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellata (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La scheda è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
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
