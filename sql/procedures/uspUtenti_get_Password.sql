CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_get_Password]
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametro
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- TOP 1 + ORDER BY: difensivo nel caso la tabella evolva verso 1:N
		SELECT TOP 1
			[Password]
		FROM dbo.tblUtentiPassword
		WHERE Id = @Id
		ORDER BY [Data] DESC;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;



