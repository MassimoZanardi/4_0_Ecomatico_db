CREATE OR ALTER PROCEDURE [dbo].[uspDomini_get_IsStart]
	@Codice CHAR(5) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametro
		SET @Codice = NULLIF(LTRIM(RTRIM(@Codice)), '');
		IF @Codice IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Codice non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Restituisce 1 se esiste un dominio attivo con quel codice e un logo
		SELECT rtn = CAST(
			CASE
				WHEN EXISTS (
					SELECT 1
					FROM dbo.tblDomini
					WHERE
						Codice = @Codice
						AND Logo IS NOT NULL
						AND Lock = 0
				) THEN 1
				ELSE 0
			END
		AS BIT);

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
