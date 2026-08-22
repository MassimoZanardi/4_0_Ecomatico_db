CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRuoli_get_SelectList]
	@IdSelected CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		SELECT
			Id = CAST('0' AS CHAR(1)),
			[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
			Selected = CAST(IIF(@IdSelected IS NULL, 1, 0) AS BIT),
			Pos = 0
		UNION ALL
		SELECT
			Id,
			[Text] = Nome,
			Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
			Pos
		FROM dbo.tblRifiutiRuoli
		ORDER BY Pos;

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
