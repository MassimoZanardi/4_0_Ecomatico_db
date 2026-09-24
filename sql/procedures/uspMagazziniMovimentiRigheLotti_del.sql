SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheLotti_del
	@Id CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdLotto non può essere vuoto';
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
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'allocazione è rimovibile mentre il movimento è in bozza o già confermato
		-- (non se eliminato, Lock = 4): la conferma non congela l'allocazione, salvo
		-- un vincolo reale verificato più sotto per i carichi.
		DECLARE @quantitaAllocazione DECIMAL(18, 2), @lockMovimento INT, @idOperazioneMovimento CHAR(1);
		SELECT
			@quantitaAllocazione = rl.Quantita,
			@lockMovimento = m.Lock,
			@idOperazioneMovimento = m.IdOperazione
		FROM
			dbo.tblMagazziniMovimentiRigheLotti rl
			INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rl.Id = r.Id
			INNER JOIN dbo.tblMagazziniMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
		WHERE
			rl.Id = @Id
			AND rl.IdLotto = @IdLotto
			AND e.Id = @IdSessione
			AND m.Lock IN (0, 2);

		IF @quantitaAllocazione IS NULL
		BEGIN
			-- Idempotenza: mai esistita/già rimossa, o movimento non esiste
			SET @returnValue = 0;
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Vincolo reale: la de-allocazione di un carico già confermato non è
			-- ammessa se la quantità è già stata consumata da uno scarico successivo
			-- sullo stesso lotto (la disponibilità scenderebbe sotto zero). Per uno
			-- scarico confermato la de-allocazione libera solo disponibilità, sempre
			-- ammessa.
			IF @lockMovimento = 0 AND @idOperazioneMovimento = 'C'
			BEGIN
				DECLARE @disponibilita DECIMAL(18, 2) = ISNULL((
					SELECT SUM(CASE WHEN mv.IdOperazione = 'C' THEN rl2.Quantita ELSE -rl2.Quantita END)
					FROM
						dbo.tblMagazziniMovimentiRigheLotti rl2 WITH (UPDLOCK, HOLDLOCK)
						INNER JOIN dbo.tblMagazziniMovimentiRighe r2 ON rl2.Id = r2.Id
						INNER JOIN dbo.tblMagazziniMovimenti mv ON r2.IdMovimento = mv.Id
					WHERE
						rl2.IdLotto = @IdLotto
						AND r2.Lock = 0
						AND mv.Lock = 0
				), 0);

				IF (@disponibilita - @quantitaAllocazione) < 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Non è possibile rimuovere l''allocazione: la quantità è già stata utilizzata da uno scarico successivo';
					GOTO BRANCH_END;
				END
			END

			DELETE dbo.tblMagazziniMovimentiRigheLotti
			WHERE Id = @Id AND IdLotto = @IdLotto;

		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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
