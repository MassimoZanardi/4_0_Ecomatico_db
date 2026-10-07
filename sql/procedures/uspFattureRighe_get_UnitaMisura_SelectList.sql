SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Unità di misura per le righe della fattura: tutte, con la prima voce "(Nessuna)".
CREATE OR ALTER PROCEDURE dbo.uspFattureRighe_get_UnitaMisura_SelectList
	@IdSelected CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST('00' AS CHAR(2)),
				[Text] = CAST('(Nessuna)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected IS NULL OR @IdSelected = '00', 1, 0) AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				Id,
				[Text] = CAST(Nome AS VARCHAR(100)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM dbo.tblUnitaMisura
		) t
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO
