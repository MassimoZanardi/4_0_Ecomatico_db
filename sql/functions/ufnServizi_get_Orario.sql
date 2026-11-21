SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnServizi_get_Orario]
(
	@Data SMALLDATETIME,
	@InGiornata BIT,
	@Durata INT
)
RETURNS VARCHAR(30)
WITH SCHEMABINDING
AS
BEGIN
	/*
	*   Orario del servizio per i testi di calendario, Impegni, elenco e stampa:
	*   - con l'ora e la durata          "09:00-11:30" (fine alla mezzanotte = "24:00")
	*   - con l'ora, senza durata        "09:00"
	*   - in giornata, con la durata     "In giornata (4:00)"
	*   - in giornata, senza durata      "In giornata"
	*/
	DECLARE @durataTesto VARCHAR(10) = IIF(@Durata IS NULL, NULL,
		CAST(@Durata / 60 AS VARCHAR(5)) + ':' + RIGHT('0' + CAST(@Durata % 60 AS VARCHAR(2)), 2));

	IF ISNULL(@InGiornata, 0) = 1
		RETURN 'In giornata' + ISNULL(' (' + @durataTesto + ')', '');

	DECLARE @fine DATETIME = DATEADD(MINUTE, @Durata, CAST(@Data AS DATETIME));

	RETURN CONVERT(VARCHAR(5), @Data, 108)
		+ ISNULL('-' + IIF(CAST(@fine AS DATE) > CAST(@Data AS DATE), '24:00', CONVERT(VARCHAR(5), @fine, 108)), '');
END;
GO
