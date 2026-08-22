CREATE PROCEDURE [dbo].[uspComuni_get_Lista_ByNome]
	@Nome VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- @Nome = NULL → restituisce tutti i comuni (fino a TOP 20)
		SET @Nome = NULLIF(LTRIM(RTRIM(@Nome)), '');

		SELECT TOP 21 -- 1 riga fissa (Selezionare) + 20 comuni
			Id,
			Nome,
			CAP,
			CodiceCatastale,
			IdProvincia,
			Pos
		FROM (
			SELECT
				Id = '000000',
				Nome = '(Selezionare)',
				CAP = '',
				CodiceCatastale = '',
				IdProvincia = '000',
				Pos = 0

			UNION ALL -- mutualmente esclusivi per Id

			SELECT TOP 20
				c.Id,
				Nome = c.Nome + ' (' + ISNULL(p.Sigla, '') + ')',
				c.CAP,
				c.CodiceCatastale,
				c.IdProvincia,
				Pos = 1
			FROM
				dbo.tblComuni c
				LEFT JOIN dbo.tblProvince p ON c.IdProvincia = p.Id
			WHERE c.Nome LIKE '%' + ISNULL(@Nome, '') + '%'
			ORDER BY
				c.Nome -- TOP 20 deterministico con ORDER BY
		) t
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
