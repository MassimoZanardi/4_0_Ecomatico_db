CREATE OR ALTER PROCEDURE [dbo].[uspTipi_get_SelectList]
	@IdSessione CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdModulo = NULLIF(LTRIM(RTRIM(@IdModulo)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdModulo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo non può essere vuoto';
			GOTO BRANCH_END;
		END

		SELECT
			Id = CAST(REPLICATE('0', 16) AS CHAR(16)),
			[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
			Selected = CAST(0 AS BIT),
			Pos = 0
		UNION ALL -- ramo 1: tipi globali (IdSede IS NULL)
		SELECT
			Id,
			[Text] = Nome,
			Selected = CAST(0 AS BIT),
			Pos = 1
		FROM dbo.tblTipi
		WHERE IdSede IS NULL
		UNION ALL -- ramo 2: tipi dell'azienda interna del calendario della sessione
		SELECT
			t.Id,
			[Text] = t.Nome,
			Selected = CAST(0 AS BIT),
			Pos = 2
		FROM
			dbo.tblSessioni x
			INNER JOIN dbo.tblCalendari c ON x.IdCalendario = c.Id
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			INNER JOIN dbo.tblTipi t ON s.IdAziendaInterna = t.IdSede
		WHERE
			x.Id = @IdSessione
			AND t.IdModulo = @IdModulo
			AND t.Lock = 0
		ORDER BY Pos, [Text];

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
