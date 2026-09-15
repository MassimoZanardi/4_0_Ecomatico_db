SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspAteco_get_SelectList]
	@IdSelected VARCHAR(10) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		;WITH cte AS (
			-- Codice selezionato: appare sempre, anche se non combacia con @Search
			SELECT
				a.Id,
				[Text] = a.Id + ' - ' + a.Descrizione,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblAteco a
			WHERE a.Id = @IdSelected

			UNION ALL -- altri codici, filtrabili per @Search

			SELECT
				a.Id,
				[Text] = a.Id + ' - ' + a.Descrizione,
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM dbo.tblAteco a
			WHERE
				(@IdSelected IS NULL OR a.Id <> @IdSelected)
				AND
					(
					@Search IS NULL
					OR a.Id LIKE @Search + '%'
					OR a.Descrizione LIKE '%' + @Search + '%'
					)
		)
		SELECT TOP 50
			Id,
			[Text],
			Selected
		FROM cte
		ORDER BY Pos, Id
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
		THROW 50001, @returnMessage, 1;
	END

END;
GO
