CREATE OR ALTER PROCEDURE [dbo].[uspComuni_get_IdByNome]
	@Nome VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametro
		SET @Nome = NULLIF(LTRIM(RTRIM(@Nome)), '');
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Separa il nome dalla sigla provincia, es. "Milano (MI)" → NomeBase = "Milano", Sigla = "MI"
		-- Se il suffisso non è presente o è malformato, usa il nome completo senza sigla
		DECLARE @posApertura INT = CHARINDEX(' (', @Nome);
		DECLARE @posChiusura INT;
		DECLARE @nomeBase VARCHAR(50);
		DECLARE @sigla VARCHAR(10);

		IF @posApertura > 0
			SET @posChiusura = CHARINDEX(')', @Nome, @posApertura);

		IF @posApertura > 0 AND @posChiusura > @posApertura + 2
		BEGIN
			SET @nomeBase = LEFT(@Nome, @posApertura - 1);
			SET @sigla = SUBSTRING(@Nome, @posApertura + 2, @posChiusura - @posApertura - 2);
		END
		ELSE
		BEGIN
			SET @nomeBase = @Nome;
			SET @sigla = NULL;
		END

		-- Filtra anche per sigla provincia quando disponibile: esistono comuni omonimi
		-- in province diverse (es. "San Teodoro"), altrimenti TOP 1 sarebbe ambiguo
		SELECT TOP 1
			c.Id
		FROM
			dbo.tblComuni c
			LEFT JOIN dbo.tblProvince p ON c.IdProvincia = p.Id
		WHERE
			c.Nome = @nomeBase
			AND
				(
				@sigla IS NULL
				OR p.Sigla = @sigla
				)
		ORDER BY
			c.Nome, c.Id; -- deterministico anche se resta un'ambiguità (nessuna sigla fornita)

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
