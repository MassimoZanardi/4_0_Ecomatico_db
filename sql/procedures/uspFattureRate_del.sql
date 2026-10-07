SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_del
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
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

		-- Idempotenza: mai esistita è trattata come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureRate WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- La fattura della rata deve esistere (in bozza o attiva, non eliminata), appartenere
		-- all'azienda interna corrente della sessione e non essere in sola lettura
		DECLARE @idAzienda CHAR(16);
		DECLARE @solaLettura BIT;
		SELECT
			@idAzienda = f.IdSede,
			@solaLettura = ISNULL(f.SolaLettura, 0)
		FROM
			dbo.tblFattureRate r
			INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			r.Id = @Id
			AND e.Id = @IdSessione
			AND f.Lock IN (0, 2);

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END
		IF @solaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura e salvare';
			GOTO BRANCH_END;
		END
		IF EXISTS (SELECT 1 FROM dbo.tblFattureRatePagamenti WHERE IdRata = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una rata con pagamenti non può essere tolta';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DELETE dbo.tblFattureRate
			WHERE Id = @Id;
			DELETE dbo.tblIdLog
			WHERE Id = @Id;
			DELETE dbo.tblId
			WHERE Id = @Id;
		COMMIT TRANSACTION;

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
