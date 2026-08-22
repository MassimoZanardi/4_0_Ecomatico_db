CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_get_Permessi_SelectList]
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SELECT
			Id = -1,
			[Text] = '(Selezionare)',
			Selected = CAST(0 AS BIT),
			Pos = 0
		UNION ALL
		SELECT
			Id,
			[Text] = Nome,
			Selected = CAST(0 AS BIT),
			Pos = 1
		FROM
			dbo.tblPermessi
		ORDER BY
			Pos, Id;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
