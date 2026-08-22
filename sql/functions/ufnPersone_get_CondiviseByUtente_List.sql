
CREATE FUNCTION [dbo].[ufnPersone_get_CondiviseByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- GROUP BY su s.Id per deduplicare: la stessa persona può apparire più volte
	-- se associata a più aree o se più sedi interne appartengono alla stessa area
	SELECT
		s.Id,
		s.IdSede,
		IdDominio = MIN(ui.IdDominio),
		Disabilitata = MIN(CAST(s.Disabilitata AS TINYINT)),
		IdArea = MIN(a.Id),
		Area = MIN(a.Nome)
	FROM
		dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) ui
	INNER JOIN dbo.tblAreeSediInterne ai ON ui.Id = ai.IdSede
	INNER JOIN dbo.tblAree a ON ai.Id = a.Id
	INNER JOIN dbo.tblAreeOsepe ae ON a.Id = ae.Id
	INNER JOIN dbo.tblPersone s ON ae.IdOsepe = s.Id
	WHERE
		a.Lock = 0
		AND s.Lock = 0
	GROUP BY s.Id, s.IdSede
);
