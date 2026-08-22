
CREATE OR ALTER FUNCTION [dbo].[ufnSedi_get_SediEsterneCondiviseByUtente_List] (
	@i dbo.tvpAziendeInterneByUtente READONLY)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	WITH cte AS (
		SELECT
			Id = ae.IdOsepe,
			ui.IdDominio,
			IdArea = a.Id,
			Area = a.Nome
		FROM
			@i ui
			INNER JOIN dbo.tblAreeSediInterne ai ON ui.Id = ai.IdSede
			INNER JOIN dbo.tblAree a ON ai.Id = a.Id
			INNER JOIN dbo.tblAreeOsepe ae ON a.Id = ae.Id
		WHERE a.Lock = 0),
	-- Deduplicazione: se lo stesso Osepe appartiene a più aree,
	-- si tiene una sola riga per Id (la prima per IdArea)
	cteDedup AS (
		SELECT
			Id,
			IdDominio = MIN(IdDominio),
			IdArea = MIN(IdArea),
			Area = MIN(Area)
		FROM cte
		GROUP BY Id
	)
	-- Ramo 1: gli Osepe stessi (sedi esterne dirette)
	SELECT
		s.Id,
		s.IdParent,
		s.IdAziendaInterna,
		c.IdDominio,
		s.Disabilitata,
		c.IdArea,
		c.Area
	FROM
		cteDedup c
		INNER JOIN dbo.tblSedi s ON c.Id = s.Id
	WHERE s.Lock = 0
	UNION ALL -- mutualmente esclusivi: s.Id ≠ s.IdParent per definizione

	-- Ramo 2: sotto-sedi degli Osepe
	SELECT
		s.Id,
		s.IdParent,
		s.IdAziendaInterna,
		c.IdDominio,
		s.Disabilitata,
		c.IdArea,
		c.Area
	FROM
		cteDedup c
		INNER JOIN dbo.tblSedi s ON c.Id = s.IdParent
	WHERE s.Lock = 0);
