
CREATE FUNCTION [dbo].[ufnOsepe_get_CondiviseByUtente_List] (
	@IdUtente CHAR(16))
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
			dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) ui
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
	-- Ramo 1: Osepe come sede diretta
	SELECT
		c.Id,
		Tipo = 'S',
		IdSede = s.IdAziendaInterna,
		c.IdDominio,
		s.Disabilitata,
		c.IdArea,
		c.Area,
		[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
		ImpiegabileServizi = CAST(0 AS BIT)
	FROM
		cteDedup c
		INNER JOIN dbo.tblSedi s ON c.Id = s.Id
	WHERE s.Lock = 0
	UNION ALL -- rami mutualmente esclusivi per tipo e JOIN

	-- Ramo 2: sotto-sedi dell'Osepe
	SELECT
		s.Id,
		Tipo = 'S',
		IdSede = s.IdAziendaInterna,
		c.IdDominio,
		s.Disabilitata,
		c.IdArea,
		c.Area,
		[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
		ImpiegabileServizi = CAST(0 AS BIT)
	FROM
		cteDedup c
		INNER JOIN dbo.tblSedi s ON c.Id = s.IdParent
	WHERE s.Lock = 0
	UNION ALL

	-- Ramo 3: oggetti dell'Osepe
	SELECT
		c.Id,
		Tipo = 'O',
		IdSede = s.IdSede,
		c.IdDominio,
		s.Disabilitata,
		c.IdArea,
		c.Area,
		[Text] = s.Nome,
		s.ImpiegabileServizi
	FROM
		cteDedup c
		INNER JOIN dbo.tblOggetti s ON c.Id = s.Id
	WHERE s.Lock = 0
	UNION ALL

	-- Ramo 4: persone dell'Osepe
	SELECT
		c.Id,
		Tipo = 'P',
		IdSede = s.IdSede,
		c.IdDominio,
		s.Disabilitata,
		c.IdArea,
		c.Area,
		[Text] = s.NomeCompleto,
		s.ImpiegabileServizi
	FROM
		cteDedup c
		INNER JOIN dbo.tblPersone s ON c.Id = s.Id
	WHERE s.Lock = 0);
