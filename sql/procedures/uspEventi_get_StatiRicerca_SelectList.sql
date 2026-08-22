CREATE PROCEDURE [dbo].[uspEventi_get_StatiRicerca_SelectList]
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SELECT
			Id = Id,
			[Text] = Nome,
			Selected = CAST(0 AS BIT)
		FROM
			dbo.tblEventiStatiRicerca
		ORDER BY
			Pos;

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
