SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Tipi di documento per la fattura: le autofatture (TD17, TD18, TD19) solo tra le fatture fornitori
-- (@Tipo = F), la pre-fattura (TD00) solo tra le fatture clienti (@Tipo = C). Con @Tutti = 1 (filtro
-- dell'elenco) c'è la prima voce "(Tutti)".
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Tipi_SelectList
	@Tipo CHAR(1) = NULL,
	@IdSelected CHAR(4) = NULL,
	@Tutti BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Tutti = ISNULL(@Tutti, 0);

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST('0000' AS CHAR(4)),
				[Text] = CAST('(Tutti)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected IS NULL OR @IdSelected = '0000', 1, 0) AS BIT),
				Pos = 0
			WHERE @Tutti = 1

			UNION ALL

			SELECT
				Id,
				[Text] = CAST(Nome AS VARCHAR(100)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM dbo.tblFattureTipi
			WHERE
				(@Tipo = 'F' OR Id NOT IN ('TD17', 'TD18', 'TD19'))
				AND (@Tipo = 'C' OR Id <> 'TD00')
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
