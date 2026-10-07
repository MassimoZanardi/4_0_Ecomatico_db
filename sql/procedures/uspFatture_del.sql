SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFatture_del
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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistita o già cancellata viene trattata come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFatture WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità): scope azienda interna corrente della sessione
		DECLARE @lock INT;
		DECLARE @solaLettura BIT;
		SELECT
			@lock = f.Lock,
			@solaLettura = ISNULL(f.SolaLettura, 0)
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			f.Id = @Id
			AND e.Id = @IdSessione;

		IF @lock IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- ── CASO 1: fattura attiva (Lock = 0) → soft delete ──────────────────
		-- Righe e rate restano sulla fattura cancellata, per il ripristino
		IF @lock = 0
		BEGIN
			IF @solaLettura = 1
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una fattura in sola lettura non può essere cancellata';
				GOTO BRANCH_END;
			END
			IF EXISTS (SELECT 1 FROM dbo.tblFatture WHERE IdFatturaRiferimento = @Id AND Lock IN (0, 2))
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una fattura a cui si riferisce una nota di credito non può essere cancellata';
				GOTO BRANCH_END;
			END
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblFattureRate r
					INNER JOIN dbo.tblFattureRatePagamenti p ON r.Id = p.IdRata
				WHERE r.IdFattura = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una fattura con rate già pagate non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblFatture
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Fattura non trovata o già eliminata';
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

		-- ── CASO 2: fattura in bozza (Lock = 2) → hard delete con righe e rate ─
		ELSE IF @lock = 2
		BEGIN
			DECLARE @figli TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);

			BEGIN TRANSACTION;
				INSERT @figli (Id)
				SELECT Id
				FROM dbo.tblFattureRighe
				WHERE IdFattura = @Id
				UNION
				SELECT Id
				FROM dbo.tblFattureRate
				WHERE IdFattura = @Id;

				DELETE i
				FROM
					dbo.tblFattureRigheImporti i
					INNER JOIN dbo.tblFattureRighe r ON i.Id = r.Id
				WHERE r.IdFattura = @Id;
				DELETE dbo.tblFattureRighe
				WHERE IdFattura = @Id;
				DELETE p
				FROM
					dbo.tblFattureRatePagamenti p
					INNER JOIN dbo.tblFattureRate r ON p.IdRata = r.Id
				WHERE r.IdFattura = @Id;
				DELETE dbo.tblFattureRate
				WHERE IdFattura = @Id;
				DELETE dbo.tblFatture
				WHERE Id = @Id;

				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE
					Id = @Id
					OR Id IN (SELECT Id FROM @figli);
				DELETE dbo.tblId
				WHERE
					Id = @Id
					OR Id IN (SELECT Id FROM @figli);
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
			SET @returnMessage = 'La fattura è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
			GOTO BRANCH_END;
		END

		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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
