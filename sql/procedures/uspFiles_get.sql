SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Un file allegato, per il download: l'app legge il contenuto dall'Object Storage (<Prefisso>/<Id>) solo dopo questa SP.
-- Basta il permesso di lettura sul record (uspFiles_get_Permesso)
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_get]
	@Id UNIQUEIDENTIFIER = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		DECLARE @idRecord CHAR(16) = (SELECT IdRecord
		FROM dbo.tblFiles
		WHERE Id = @Id);

		IF @idRecord IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'File non trovato';
			GOTO BRANCH_END;
		END

		DECLARE @permesso INT;
		EXEC dbo.uspFiles_get_Permesso
			@IdRecord = @idRecord,
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
		WHERE f.Id = @Id;

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
