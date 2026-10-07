SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Stati della fattura (G Generata, S Spedita). Con @Tutti = 1 (filtro dell'elenco) c'è la prima voce "(Tutti)".
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Stati_SelectList
	@IdSelected CHAR(1) = NULL,
	@Tutti BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Tutti = ISNULL(@Tutti, 0);

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST('0' AS CHAR(1)),
				[Text] = CAST('(Tutti)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected IS NULL OR @IdSelected = '0', 1, 0) AS BIT),
				Pos = 0
			WHERE @Tutti = 1

			UNION ALL

			SELECT
				Id,
				[Text] = CAST(Nome AS VARCHAR(100)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM dbo.tblFattureStati
		) t
		ORDER BY Pos, Id;

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
