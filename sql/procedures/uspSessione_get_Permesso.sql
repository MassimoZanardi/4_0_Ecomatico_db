SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspSessione_get_Permesso]
	@IdSessione CHAR(16) = NULL,
	@IdFunzione CHAR(3) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdFunzione = NULLIF(LTRIM(RTRIM(@IdFunzione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdFunzione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdFunzione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Wrapper SELECT-based di uspSessione_get_FunzionePermesso (OUTPUT), riusa la
		-- stessa cache (tblSessioniFunzioniPermessi) — vedi CLAUDE.md: le SP con OUTPUT
		-- non sono la convenzione di chiamata lato app, si preferisce un valore SELECT.
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @IdFunzione,
			@Permesso = @permesso OUTPUT;

		SELECT Permesso = @permesso;

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
