CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiModelli_get_SelectList]
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IsRentri BIT = NULL,
	@IsFormulario BIT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Titolarità: il Modello è legato a un Registro specifico (tblRifiutiModelli.IdRegistro).
		-- Prima il filtro confrontava solo il Tipo di registro (via tblRifiutiOperazioniRegistriTipi),
		-- non il Registro stesso: due aziende con registri dello stesso Tipo si vedevano a vicenda
		-- i Modelli l'una dell'altra. Pre-calcolato FUORI dalla query principale, stesso pattern
		-- già usato in uspRifiutiFormulari_get_Etichette_SelectList.
		DECLARE @idRegistro CHAR(16);
		SELECT @idRegistro = IdRegistro
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- @IsRentri     = NULL → nessun filtro; = 1 → solo Rentri
		-- @IsFormulario = NULL → nessun filtro; = 0 → senza formulario; = 1 → con formulario
		;WITH cte AS (
			SELECT
				Id = CAST(REPLICATE('0', 16) AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
				Selected = CAST(0 AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				r.Id,
				[Text] = r.Nome,
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblRifiutiModelli r
				INNER JOIN dbo.tblRifiutiOperazioni o ON r.IdOperazione = o.Id
			WHERE
				r.IdRegistro = @idRegistro
				AND o.IsRentri = ISNULL(@IsRentri, o.IsRentri)
				AND ( @IsFormulario IS NULL OR (@IsFormulario = 0 AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiOperazioniFormulario WHERE Id = o.Id)) OR (@IsFormulario = 1 AND EXISTS (SELECT 1 FROM dbo.tblRifiutiOperazioniFormulario WHERE Id = o.Id)) )
				AND r.Lock = 0
				AND (@Search IS NULL OR r.Nome LIKE '%' + @Search + '%')
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
