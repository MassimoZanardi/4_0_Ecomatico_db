CREATE FUNCTION [dbo].[ufnDate_get_GiornoDelMeseRelativo]
(
	@DataInizio SMALLDATETIME,
	@Data SMALLDATETIME,
	@Relativo INT -- 1-4=prima..quarta occorrenza, 5=ultima occorrenza
)
RETURNS SMALLDATETIME
WITH SCHEMABINDING
AS
BEGIN
	-- Porta @Data al primo giorno del mese
	SET @Data = DATEADD(DAY, 1 - DAY(@Data), @Data);

	-- Calcola l'ultimo giorno del mese
	DECLARE @DataFineMese SMALLDATETIME = DATEADD(DAY, -1, DATEADD(MONTH, 1, @Data));

	RETURN (
		SELECT IIF(
			@Relativo = 5,
			-- Ultima occorrenza: parte dalla fine del mese e va indietro
			DATEADD(DAY,
				((7 + (DATEPART(DW, @DataFineMese) - DATEPART(DW, @DataInizio))) % 7) * -1,
				@DataFineMese),
			-- N-esima occorrenza: parte dall'inizio del mese e va avanti
			DATEADD(DAY,
				7 * (@Relativo - 1),
				DATEADD(DAY,
					(7 + (DATEPART(DW, @DataInizio) - DATEPART(DW, @Data))) % 7,
					@Data))
		)
	);
END;
