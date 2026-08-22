CREATE PROCEDURE [dbo].[uspRifiutiMovimenti_get_ClassiPericolo_List]
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		SELECT
			Id = c.Id,
			[Text] = c.Codice,
			[Checked] = CAST(IIF(rc.Id IS NULL, 0, 1) AS BIT),
			[Description] = c.Nome
		FROM
			dbo.tblRifiutiClassiPericolo c
			LEFT JOIN dbo.tblRifiutiMovimentiClassiPericolo rc ON c.Id = rc.IdClasse AND rc.Id = @Id
		ORDER BY
			c.Id;

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
