CREATE OR ALTER PROCEDURE [dbo].[uspColori_get]
	@Id CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametro
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblColori
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Colore non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			Id,
			Nome,
			Css,
			Hex
		FROM
			dbo.tblColori
		WHERE Id = @Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
