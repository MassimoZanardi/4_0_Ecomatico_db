SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- File allegati di una registrazione o di un'autorizzazione (@IdRecord). Permesso e titolarità in uspFiles_get_Permesso;
-- IsModificabile dice se la sessione può caricare e cancellare
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_get_List]
	@IdRecord CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRecord = NULLIF(LTRIM(RTRIM(@IdRecord)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRecord IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @IdRecord e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		DECLARE @permesso INT;
		EXEC dbo.uspFiles_get_Permesso
			@IdRecord = @IdRecord,
			@IdSessione = @IdSessione,
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			f.Id,
			f.IdRecord,
			f.Nome,
			Quota = ISNULL(f.Quota, 0),
			IsModificabile = CAST(IIF(@permesso >= 2, 1, 0) AS BIT)
		FROM dbo.tblFiles f
		WHERE f.IdRecord = @IdRecord
		ORDER BY f.Nome;

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
