SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheEoWLotti_del
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

		-- L'allocazione EoW è rimovibile mentre il movimento è in bozza o già
		-- confermato: rappresenta sempre uno scarico, quindi rimuoverla libera solo
		-- disponibilità, mai un vincolo reale da verificare.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniMovimentiRigheEoWLotti rl
				INNER JOIN dbo.tblMagazziniMovimentiRigheEoW r ON rl.Id = r.Id
				INNER JOIN dbo.tblMagazziniMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
			WHERE
				rl.Id = @Id
				AND rl.IdLotto = @IdLotto
				AND e.Id = @IdSessione
				AND m.Lock IN (0, 2)
		)
		BEGIN
			-- Idempotenza: mai esistita/già rimossa, o movimento non esiste
			SET @returnValue = 0;
			GOTO BRANCH_END;
		END

		DELETE dbo.tblMagazziniMovimentiRigheEoWLotti
		WHERE Id = @Id AND IdLotto = @IdLotto;

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
