CREATE OR ALTER PROCEDURE [dbo].[uspNazioni_get_SelectList]
	@IdSelected CHAR(3) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		;WITH cte AS (
			SELECT
				Id = CAST('000' AS CHAR(3)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected IS NULL, 1, 0) AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				Id,
				[Text] = Nome,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblNazioni
			WHERE Id = @IdSelected
			UNION ALL

			SELECT
				Id,
				[Text] = Nome,
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM dbo.tblNazioni
			WHERE
				Id <> ISNULL(@IdSelected, '000')
				AND (@Search IS NULL OR Nome LIKE '%' + @Search + '%')
		)
		SELECT TOP 50
			Id,
			[Text],
			Selected
		FROM cte
		ORDER BY Pos, [Text]
		OPTION (RECOMPILE);

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
