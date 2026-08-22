CREATE PROCEDURE [dbo].[uspComuni_get]
	@Id CHAR(6) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
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

		SELECT
			Id,
			IdProvincia,
			Nome,
			CAP,
			CodiceCatastale
		FROM (
			SELECT
				Id = '000000',
				IdProvincia = '000',
				Nome = '(Selezionare)',
				CAP = '',
				CodiceCatastale = ''

			UNION ALL -- mutualmente esclusivi per Id

			SELECT
				Id,
				IdProvincia,
				Nome,
				CAP,
				CodiceCatastale
			FROM
				dbo.tblComuni
		) t
		WHERE t.Id = @Id;

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
