SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- Voci di un campo "Elenco a scelta" (S3.7) inviate dalla scheda del tipo come JSON ["Voce 1","Voce 2", ...], nell'ordine
-- dell'elenco: spazi tolti, righe vuote ignorate, Pos da 1. Errore valorizzato = voce non ammessa (la SP chiamante
-- restituisce il primo, per Pos): piu' di 50 caratteri, ripetuta (maiuscole e minuscole non contano), piu' di 50 voci.
-- Nessuna riga = nessuna voce (la SP chiamante chiede di indicarne almeno una).
-- Usata da uspTipi_ins_Proprieta, uspTipi_upd_ProprietaVoci
CREATE OR ALTER FUNCTION [dbo].[ufnTipi_get_ProprietaVoci_List]
(
	@Voci NVARCHAR(MAX)
)
RETURNS TABLE
AS
RETURN (
	WITH cteVoci AS (
		SELECT
			Ordine = CAST(j.[key] AS INT),
			Testo = LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(j.[value], CHAR(13), ''), CHAR(10), ''), CHAR(9), ' ')))
		FROM OPENJSON(@Voci) j
		WHERE j.[type] IN (1, 2)
	),
	cteNumerate AS (
		SELECT
			Pos = ROW_NUMBER() OVER (ORDER BY Ordine),
			Testo,
			Ripetuta = COUNT(*) OVER (PARTITION BY Testo COLLATE Latin1_General_CI_AS),
			PrimaRipetuta = ROW_NUMBER() OVER (PARTITION BY Testo COLLATE Latin1_General_CI_AS ORDER BY Ordine),
			Totale = COUNT(*) OVER ()
		FROM cteVoci
		WHERE Testo <> ''
	)
	SELECT
		Pos,
		Nome = CAST(LEFT(Testo, 50) AS VARCHAR(50)),
		Errore = CASE
			WHEN Totale > 50 THEN 'L''elenco può avere al massimo 50 voci'
			WHEN LEN(Testo) > 50 THEN 'La voce "' + LEFT(Testo, 30) + '..." supera i 50 caratteri'
			WHEN Ripetuta > 1 AND PrimaRipetuta > 1 THEN 'La voce "' + Testo + '" è ripetuta'
		END
	FROM cteNumerate
);
GO
