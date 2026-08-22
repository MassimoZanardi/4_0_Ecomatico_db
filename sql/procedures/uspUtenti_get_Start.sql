CREATE PROCEDURE [dbo].[uspUtenti_get_Start]
	@Email VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Email = NULLIF(LTRIM(RTRIM(@Email)), '');
		IF @Email IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Email non può essere vuoto';
			GOTO BRANCH_END;
		END

		SELECT TOP 1
			rtn = IIF(d.Logo IS NULL, '', d.Codice)
		FROM
			dbo.tblUtenti u
			INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
		WHERE u.Email = @Email
		ORDER BY
			IIF(d.Logo IS NULL, 1, 0); -- preferisce il dominio con logo

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
