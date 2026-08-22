CREATE PROCEDURE [dbo].[uspRifiutiAttivitaRecuperoSmaltimento_get_SelectList]
	@IdSelected CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		SELECT
			Id = CAST('00' AS CHAR(2)),
			[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
			Selected = CAST(IIF(@IdSelected IS NULL, 1, 0) AS BIT)

		UNION ALL

		SELECT
			Id,
			[Text] = Codice + ' - ' + Nome,
			Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT)
		FROM
			dbo.tblRifiutiAttivitaRecuperoSmaltimento
		ORDER BY
			Id;

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
