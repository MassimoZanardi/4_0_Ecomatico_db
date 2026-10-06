SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_get_Natura_SelectList
	@IdSelected VARCHAR(4) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		-- Codici natura della fattura elettronica (N1...N7), preceduti dal codice
		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST('0000' AS VARCHAR(4)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
				Selected = CAST(IIF(@IdSelected IS NULL OR @IdSelected = '0000', 1, 0) AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				Id,
				[Text] = CAST(Id + ' - ' + Nome AS VARCHAR(200)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM dbo.tblAliquoteIvaNatura
		) t
		ORDER BY Pos, Id;

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
