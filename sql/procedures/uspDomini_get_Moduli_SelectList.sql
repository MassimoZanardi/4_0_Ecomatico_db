CREATE OR ALTER PROCEDURE [dbo].[uspDomini_get_Moduli_SelectList]
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Restituisce tutti i moduli selezionabili per un dominio
		-- escludendo BAS (Base) e IMP (Impostazioni) riservati al sistema
		SELECT
			Id,
			[Text] = Nome,
			Selected = CAST(0 AS BIT)
		FROM
			dbo.tblModuli
		WHERE Id NOT IN ('BAS', 'IMP')
		ORDER BY
			Nome;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
