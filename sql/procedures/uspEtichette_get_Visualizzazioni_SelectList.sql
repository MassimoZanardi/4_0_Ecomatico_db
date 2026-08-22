CREATE OR ALTER PROCEDURE [dbo].[uspEtichette_get_Visualizzazioni_SelectList]
	@IdSelected CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		SELECT
			Id = 'C',
			[Text] = CAST('Compatta' AS VARCHAR(50)),
			Selected = CAST(IIF('C' = @IdSelected, 1, 0) AS BIT),
			Pos = IIF('C' = @IdSelected, 1, 0)

		UNION ALL

		SELECT
			Id = 'E',
			[Text] = CAST('Estesa' AS VARCHAR(50)),
			Selected = CAST(IIF('E' = @IdSelected, 1, 0) AS BIT),
			Pos = IIF('E' = @IdSelected, 1, 0)

		ORDER BY Pos, [Text];

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
