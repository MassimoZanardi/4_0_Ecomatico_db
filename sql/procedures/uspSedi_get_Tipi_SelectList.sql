CREATE OR ALTER PROCEDURE [dbo].[uspSedi_get_Tipi_SelectList]
	@SediAssociate BIT = 0,
	@IdSelected CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		SELECT
			Id,
			[Text] = CASE WHEN @SediAssociate = 0 THEN NomeParent ELSE Nome END,
			Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT)
		FROM
			dbo.tblSediTipi
		WHERE CASE WHEN @SediAssociate = 0 THEN IIF(NomeParent IS NOT NULL, 1, 0) ELSE IIF(NomeParent IS NULL, 1, 0) END = 1
		ORDER BY
			CASE WHEN @SediAssociate = 0 THEN NomeParent ELSE Nome END;

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
