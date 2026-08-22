CREATE PROCEDURE [dbo].[uspOsepe_get_NonCondivise_SelectList]
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);

		;WITH cte AS (
			-- Opzione vuota sempre in cima
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
				Selected = CAST(0 AS BIT),
				Pos = 0

			UNION ALL -- rami mutualmente esclusivi per Pos

			-- Osepe selezionata: garantisce che compaia anche se il TOP 50
			-- della lista generale (Pos = 2) la escluderebbe
			SELECT
				i.Id,
				[Text] = i.[Text] + ' [' + i.TipoNome + ']',
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnOsepe_get_NonCondiviseByDominio_List(e.IdDominio) i
			WHERE
				e.Id = @IdSessione
				AND i.Id = @IdSelected
			UNION ALL

			-- Osepe non condivise del dominio della sessione
			SELECT
				i.Id,
				[Text] = i.[Text] + ' [' + i.TipoNome + ']',
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnOsepe_get_NonCondiviseByDominio_List(e.IdDominio) i
			WHERE
				e.Id = @IdSessione
				AND i.Id <> @IdSelected
				AND (@Search IS NULL OR i.[Text] + ' [' + i.TipoNome + ']' LIKE '%' + @Search + '%')
		)
		SELECT TOP 50
			Id,
			[Text],
			Selected
		FROM cte
		ORDER BY Pos, [Text]
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
