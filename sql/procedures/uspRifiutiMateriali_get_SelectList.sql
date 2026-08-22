CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMateriali_get_SelectList]
	@IdSelected CHAR(2) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		SELECT
			Id = CAST(REPLICATE('0', 2) AS CHAR(2)),
			[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
			Selected = CAST(IIF(@IdSelected IS NULL, 1, 0) AS BIT),
			Pos = 0
		UNION ALL
		SELECT
			Id,
			[Text] = Nome,
			Selected = CAST(1 AS BIT),
			Pos = 1
		FROM dbo.tblRifiutiMateriali
		WHERE Id = @IdSelected
		UNION ALL
		SELECT
			Id,
			[Text] = Nome,
			Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
			Pos = IIF(Nome = 'Altro', 3, 2)
		FROM dbo.tblRifiutiMateriali
		WHERE
			(
			@IdSelected IS NULL
			OR Id <> @IdSelected
			)
			AND
				(
				@Search IS NULL
				OR Nome LIKE '%' + @Search + '%'
				)
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
