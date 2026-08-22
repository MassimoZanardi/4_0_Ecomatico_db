
CREATE FUNCTION [dbo].[ufnSedi_get_SediEsterneNonCondiviseByUtente_List] (
	@i dbo.tvpAziendeInterneByUtente READONLY)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Ramo 1: sedi esterne dirette
	SELECT
		s.Id,
		s.IdParent,
		s.IdAziendaInterna,
		i.IdDominio,
		s.Disabilitata
	FROM
		@i i
		INNER JOIN dbo.tblSediEsterne e ON i.Id = e.IdSedeInterna
		INNER JOIN dbo.tblSedi s ON e.Id = s.Id
	WHERE
		s.Lock = 0
		AND NOT EXISTS ( SELECT 1 FROM dbo.tblAreeOsepe ae INNER JOIN dbo.tblAree a ON ae.Id = a.Id WHERE a.Lock = 0 AND ae.IdOsepe = s.Id )
	UNION ALL -- mutualmente esclusivi: s.Id ≠ s.IdParent per definizione

	-- Ramo 2: sotto-sedi delle sedi esterne
	SELECT
		s.Id,
		s.IdParent,
		s.IdAziendaInterna,
		i.IdDominio,
		s.Disabilitata
	FROM
		@i i
		INNER JOIN dbo.tblSediEsterne e ON i.Id = e.IdSedeInterna
		INNER JOIN dbo.tblSedi s ON e.Id = s.IdParent
	WHERE
		s.Lock = 0
		AND NOT EXISTS ( SELECT 1 FROM dbo.tblAreeOsepe ae INNER JOIN dbo.tblAree a ON ae.Id = a.Id WHERE a.Lock = 0 AND ae.IdOsepe = s.IdParent )
);
