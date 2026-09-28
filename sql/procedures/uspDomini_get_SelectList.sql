CREATE OR ALTER PROCEDURE [dbo].[uspDomini_get_SelectList]
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
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

		DECLARE @master BIT = (
			SELECT d.[Master]
			FROM dbo.tblSessioni e
			INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
			INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
			WHERE e.Id = @IdSessione);

		DECLARE @idSelected CHAR(16) = ISNULL((
			SELECT d.Id
			FROM dbo.tblDomini d
			INNER JOIN dbo.tblSessioni s ON d.Id = s.IdDominio
			WHERE
				s.Id = @IdSessione
				AND d.Lock = 0
		), REPLICATE('0', 16));

		;WITH cte AS (
			SELECT
				Id = CAST(REPLICATE('0', 16) AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(50)),
				Selected = CAST(IIF(@idSelected = REPLICATE('0', 16), 1, 0) AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				Id,
				[Text] = Nome,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblDomini
			WHERE
				Id = @idSelected
				AND Id <> REPLICATE('0', 16)
			UNION ALL

			SELECT
				Id,
				[Text] = Nome,
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM dbo.tblDomini
			WHERE
				@master = 1
				AND Id <> @idSelected
				AND Lock = 0
				AND
					(
					@Search IS NULL
					OR Nome LIKE '%' + @Search + '%'
					)
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
