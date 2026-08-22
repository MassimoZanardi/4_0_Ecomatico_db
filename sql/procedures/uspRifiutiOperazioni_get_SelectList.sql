CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiOperazioni_get_SelectList]
	@IdSessione CHAR(16) = NULL,
	@IsRentri BIT = NULL,
	@IsFormulario BIT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- @IsRentri     = NULL → nessun filtro; = 1 → solo Rentri
		-- @IsFormulario = NULL → nessun filtro; = 0 → senza formulario; = 1 → con formulario

		IF @IsFormulario = 1 SET @IsRentri = NULL;

		SELECT
			Id = CAST(REPLICATE('0', 16) AS CHAR(16)),
			[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
			Selected = CAST(1 AS BIT),
			Pos = 0
		UNION ALL
		SELECT
			o.Id,
			[Text] = CAST(o.Pos AS VARCHAR(2)) + '. ' + o.Nome,
			Selected = CAST(0 AS BIT),
			o.Pos
		FROM
			dbo.tblRifiutiOperazioni o
			INNER JOIN dbo.tblRifiutiOperazioniRegistriTipi ot ON o.Id = ot.Id
			INNER JOIN dbo.tblRifiutiRegistri r ON ot.IdTipo = r.IdTipo
			INNER JOIN dbo.tblSessioni e ON r.Id = e.IdRegistro
		WHERE
			e.Id = @IdSessione
			AND
				(
				@IsRentri IS NULL
				OR o.IsRentri = @IsRentri
				)
			AND
				(
				@IsFormulario IS NULL
				OR ISNULL(o.IsFormulario, 0) = @IsFormulario
				)
		ORDER BY Pos
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
