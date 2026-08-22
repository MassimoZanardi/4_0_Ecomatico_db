CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiEer_get_List]
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		SELECT TOP 50
			Id,
			Nome = Nome + IIF(Pericoloso = 1, '*', ''),
			Descrizione,
			Pericoloso
		FROM
			dbo.tblRifiutiEer
		WHERE
			@Search IS NULL
			OR Nome LIKE '%' + @Search + '%'
			OR Descrizione LIKE '%' + @Search + '%'
		ORDER BY Nome
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
