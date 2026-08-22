CREATE PROCEDURE [dbo].[uspEventi_get_RicorrenzeGiornoMeseRelativo_SelectList]
	@Data SMALLDATETIME = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		IF @Data IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Data non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET DATEFIRST 1;

		DECLARE @relativo INT;
		DECLARE @giornoSettimana INT;
		DECLARE @day INT;

		SELECT
			@day = DAY(@Data),
			@giornoSettimana = DATEPART(DW, @Data),
			@relativo = CASE
				WHEN DAY(@Data) <= 7 THEN 1
				WHEN DAY(@Data) <= 14 THEN 2
				WHEN DAY(@Data) <= 21 THEN 3
				WHEN DAY(@Data) <= 28 THEN 4
				ELSE 5
			END;

		SELECT
			Id = 0,
			[Text] = 'Il giorno ' + FORMAT(@Data, 'dd', 'it-IT') + ' del mese',
			Selected = CAST(0 AS BIT)

		UNION ALL

		SELECT
			Id = @relativo,
			[Text] = CASE @giornoSettimana
				WHEN 7 THEN
					CASE @relativo
						WHEN 1 THEN 'La prima domenica del mese'
						WHEN 2 THEN 'La seconda domenica del mese'
						WHEN 3 THEN 'La terza domenica del mese'
						WHEN 4 THEN 'La quarta domenica del mese'
						ELSE 'L''ultima domenica del mese'
					END
				ELSE
					CASE @relativo
						WHEN 1 THEN 'Il primo ' + FORMAT(@Data, 'dddd', 'it-IT') + ' del mese'
						WHEN 2 THEN 'Il secondo ' + FORMAT(@Data, 'dddd', 'it-IT') + ' del mese'
						WHEN 3 THEN 'Il terzo ' + FORMAT(@Data, 'dddd', 'it-IT') + ' del mese'
						WHEN 4 THEN 'Il quarto ' + FORMAT(@Data, 'dddd', 'it-IT') + ' del mese'
						ELSE 'L''ultimo ' + FORMAT(@Data, 'dddd', 'it-IT') + ' del mese'
					END
			END,
			Selected = CAST(0 AS BIT);

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
