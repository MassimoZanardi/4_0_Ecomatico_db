CREATE PROCEDURE [dbo].[uspRifiutiUnitaMisura_get_SelectList]
	@IdSelected CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		SELECT
			Id,
			[Text] = Id,
			Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblUnitaMisura
		WHERE Id IN ('KG', 'LT');

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
