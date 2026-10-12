SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select delle priorità di un importo, dalla più alta alla più bassa (dato di riferimento: tblImportiPriorita).
-- A parità di variabili coincidenti con il documento da fatturare vince l'importo con la priorità più alta.
CREATE OR ALTER PROCEDURE dbo.uspImporti_get_Priorita_SelectList
	@IdSelected INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SELECT
			Id = CAST(p.Id AS VARCHAR(10)),
			[Text] = p.Nome,
			Selected = CAST(IIF(p.Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblImportiPriorita p
		ORDER BY p.Id DESC;

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
