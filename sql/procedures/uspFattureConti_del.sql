SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureConti_del
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
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureConti WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblFattureConti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock FROM dbo.tblFattureConti WHERE Id = @Id);
		DECLARE @idAzienda CHAR(16) = (SELECT IdSede FROM dbo.tblFattureConti WHERE Id = @Id);

		-- ── CASO 1: conto attivo (Lock = 0) → soft delete ────────────────────
		IF @lock = 0
		BEGIN
			-- Un conto usato nelle righe di una fattura non cancellata resta
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblFattureRigheImporti i
					INNER JOIN dbo.tblFattureRighe r ON i.Id = r.Id
					INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				WHERE
					i.IdConto = @Id
					AND f.Lock IN (0, 2)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un conto usato nelle righe di una fattura non può essere cancellato';
				GOTO BRANCH_END;
			END
			-- Lo stesso per un conto indicato in un movimento manuale attivo della prima nota. IdSede (l'azienda
			-- del conto, la stessa dei suoi movimenti) permette la ricerca nell'indice dei pagamenti
			IF EXISTS (SELECT 1 FROM dbo.tblPagamenti WHERE IdSede = @idAzienda AND IdConto = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un conto usato in un movimento della prima nota non può essere cancellato';
				GOTO BRANCH_END;
			END
			-- Modulo Offerte e contratti: lo stesso per le righe di un importo non cancellato
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblImportiRigheDettagli d
					INNER JOIN dbo.tblImportiRighe g ON d.Id = g.Id
					INNER JOIN dbo.tblImporti i ON g.IdImporto = i.Id
				WHERE
					d.IdConto = @Id
					AND i.Lock IN (0, 2)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un conto usato nelle righe di un importo non può essere cancellato';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblFattureConti
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Conto non trovato o già eliminato';
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

		-- ── CASO 2: conto in bozza (Lock = 2) → hard delete ──────────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblFattureConti
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellato (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il conto è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
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
