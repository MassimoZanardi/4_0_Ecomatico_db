CREATE OR ALTER PROCEDURE [dbo].[uspCalendario_get_AnniSelectList]
	@Anni INT = 10,
	@Offset INT = -10
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Riconduce ai default se fuori range
		SET @Anni = CASE WHEN @Anni IS NULL OR @Anni <= 0 OR @Anni > 50 THEN 10 ELSE @Anni END;
		SET @Offset = CASE WHEN @Offset IS NULL OR @Offset < -50 OR @Offset > 50 THEN -10 ELSE @Offset END;

		DECLARE @anno INT = DATEPART(YEAR, DATEADD(YEAR, @Offset, GETDATE()));

		WITH cte AS (
			SELECT Anno = @anno
			UNION ALL
			SELECT Anno + 1
			FROM cte
			WHERE Anno < @anno + @Anni)
		SELECT
			Id = Anno,
			[Text] = Anno,
			Selected = CAST(0 AS BIT)
		FROM cte
		ORDER BY Anno
		OPTION (MAXRECURSION 200);

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
