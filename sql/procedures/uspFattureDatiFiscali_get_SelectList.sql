SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Elenchi dei codici per la pagina Fatturazione > Dati fiscali, presi dallo schema della fattura elettronica.
-- @Elenco: R regimi fiscali, T tipi di ritenuta, C causali del pagamento della ritenuta. La prima voce è
-- "(Selezionare)" per i regimi (obbligatorio) e "(Nessuna)" per la ritenuta (facoltativa). Il testo riporta
-- il codice davanti alla descrizione.
CREATE OR ALTER PROCEDURE dbo.uspFattureDatiFiscali_get_SelectList
	@Elenco CHAR(1) = NULL,
	@IdSelected VARCHAR(4) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Elenco = UPPER(NULLIF(LTRIM(RTRIM(@Elenco)), ''));
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		IF @Elenco IS NULL OR @Elenco NOT IN ('R', 'T', 'C')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Elenco deve essere R (regimi fiscali), T (tipi di ritenuta) o C (causali del pagamento)';
			GOTO BRANCH_END;
		END

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(IIF(@Elenco = 'C', '0', '0000') AS VARCHAR(4)),
				[Text] = CAST(IIF(@Elenco = 'R', '(Selezionare)', '(Nessuna)') AS VARCHAR(250)),
				Selected = CAST(IIF(@IdSelected IS NULL, 1, 0) AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				Id = CAST(Id AS VARCHAR(4)),
				[Text] = CAST(Id + ' - ' + Nome AS VARCHAR(250)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM dbo.tblFattureRegimiFiscali
			WHERE @Elenco = 'R'

			UNION ALL

			SELECT
				Id = CAST(Id AS VARCHAR(4)),
				[Text] = CAST(Id + ' - ' + Nome AS VARCHAR(250)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM dbo.tblFattureRitenuteTipi
			WHERE @Elenco = 'T'

			UNION ALL

			SELECT
				Id = CAST(Id AS VARCHAR(4)),
				[Text] = CAST(Id + ' - ' + Nome AS VARCHAR(250)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1 + ISNULL(Pos, 0)
			FROM dbo.tblFattureRitenuteCausali
			WHERE @Elenco = 'C'
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
