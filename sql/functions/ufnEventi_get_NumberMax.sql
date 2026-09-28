SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnEventi_get_NumberMax]
(
	@Data SMALLDATETIME,
	@DataFine SMALLDATETIME,
	@IdIntervallo CHAR(2),
	@Frequenza INT,
	@Ripetizioni INT
)
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
	-- Protezione: frequenza NULL o zero restituisce 0
	IF @Frequenza IS NULL OR @Frequenza <= 0
		RETURN 0;

	DECLARE @rtn INT = CASE
		WHEN @IdIntervallo = 'DD' THEN DATEDIFF(DAY, @Data, @DataFine) / @Frequenza
		WHEN @IdIntervallo = 'WK' THEN DATEDIFF(WEEK, @Data, @DataFine) / @Frequenza
		WHEN @IdIntervallo = 'MM' THEN DATEDIFF(MONTH, @Data, @DataFine) / @Frequenza
		WHEN @IdIntervallo = 'YY' THEN DATEDIFF(YEAR, @Data, @DataFine) / @Frequenza
		ELSE 0
	END;

	RETURN IIF(@Ripetizioni > 0 AND @Ripetizioni < @rtn, @Ripetizioni - 1, @rtn);
END;
