SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Prima data di spedizione ammessa per un Allegato VII inviato il giorno @Data: va inviato almeno due giorni lavorativi
-- prima che la spedizione inizi (Reg. UE 2024/1157 art. 18.5), cioè @Data deve precedere almeno due giorni lavorativi
-- prima della spedizione. Giorno lavorativo come nel Reg. di esecuzione UE 2025/1290 art. 2.16: da lunedì a venerdì,
-- esclusi 1 gennaio, 1 maggio, 15 agosto, 1 novembre, 25 e 26 dicembre (non le festività nazionali)
CREATE OR ALTER FUNCTION [dbo].[ufnDiwassAllegatiVii_get_DataSpedizioneMinima] (
	@Data DATE)
RETURNS DATE
AS
BEGIN
	DECLARE @giorno DATE = @Data;
	DECLARE @lavorativi INT = 0;

	-- Secondo giorno lavorativo da @Data compresa: la spedizione può iniziare dal giorno dopo
	WHILE @lavorativi < 2
	BEGIN
		IF (DATEDIFF(DAY, '19000101', @giorno) % 7) < 5
			AND RIGHT(CONVERT(CHAR(8), @giorno, 112), 4) NOT IN ('0101', '0501', '0815', '1101', '1225', '1226')
			SET @lavorativi += 1;
		IF @lavorativi < 2
			SET @giorno = DATEADD(DAY, 1, @giorno);
	END

	RETURN DATEADD(DAY, 1, @giorno);
END;
GO
