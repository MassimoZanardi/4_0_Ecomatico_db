SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- @Tipo: NULL tutte le operazioni, 'R' solo recupero, 'D' solo smaltimento; l'operazione selezionata resta sempre in elenco
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiAttivitaRecuperoSmaltimento_get_SelectList]
	@IdSelected CHAR(2) = NULL,
	@Tipo CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Tipo = NULLIF(LTRIM(RTRIM(@Tipo)), '');

		SELECT
			Id = CAST('00' AS CHAR(2)),
			[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
			Selected = CAST(IIF(@IdSelected IS NULL, 1, 0) AS BIT)

		UNION ALL

		SELECT
			Id,
			[Text] = Codice + ' - ' + Nome,
			Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT)
		FROM
			dbo.tblRifiutiAttivitaRecuperoSmaltimento
		WHERE
			@Tipo IS NULL
			OR Codice LIKE @Tipo + '%'
			OR Id = @IdSelected
		ORDER BY
			Id;

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
