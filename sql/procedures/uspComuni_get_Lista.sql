CREATE OR ALTER PROCEDURE [dbo].[uspComuni_get_Lista]
	@IdProvincia CHAR(3) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametro
		SET @IdProvincia = NULLIF(LTRIM(RTRIM(@IdProvincia)), '');
		IF @IdProvincia IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdProvincia non può essere vuoto';
			GOTO BRANCH_END;
		END

		SELECT
			Id = '000000',
			Nome = '(Selezionare)',
			Selected = CAST(0 AS BIT),
			Pos = 0

		UNION ALL -- mutualmente esclusivi per Id

		SELECT
			c.Id,
			Nome = c.Nome + ' (' + p.Sigla + ')',
			Selected = CAST(0 AS BIT),
			Pos = 1
		FROM
			dbo.tblComuni c
			INNER JOIN dbo.tblProvince p ON c.IdProvincia = p.Id
		WHERE c.IdProvincia = @IdProvincia
		ORDER BY
			Pos, Nome;

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
