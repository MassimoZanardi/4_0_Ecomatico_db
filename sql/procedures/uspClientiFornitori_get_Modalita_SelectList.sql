SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_get_Modalita_SelectList
	@IdSelected CHAR(4) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST('0000' AS CHAR(4)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected IS NULL OR @IdSelected = '0000', 1, 0) AS BIT),
				Pos = 0,
				Ordine = CAST(NULL AS VARCHAR(100))

			UNION ALL

			SELECT
				Id,
				[Text] = CAST(Nome AS VARCHAR(100)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1,
				Ordine = CAST(Id AS VARCHAR(100))
			FROM dbo.tblPagamentiModalita
		) t
		ORDER BY Pos, Ordine;

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
