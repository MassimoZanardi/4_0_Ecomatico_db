CREATE FUNCTION [dbo].[ufnOsepe_get_NonCondiviseByDominio_List] (
	@IdDominio CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Ramo 1: sedi esterne del dominio
	SELECT
		s.Id,
		Tipo = 'S',
		TipoNome = 'Sede',
		IdSede = i.Id,
		i.IdDominio,
		s.Disabilitata,
		[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
		ImpiegabileServizi = CAST(0 AS BIT) -- ✅ aggiunto per coerenza
	FROM
		dbo.tblSediInterne i
		INNER JOIN dbo.tblSedi si ON i.Id = si.Id
		INNER JOIN dbo.tblSediEsterne se ON si.Id = se.IdSedeInterna
		INNER JOIN dbo.tblSedi s ON se.Id = s.Id
	WHERE
		i.IdDominio = @IdDominio -- ✅ filtro dominio
		AND si.Lock = 0
		AND s.Lock = 0
	UNION ALL -- rami mutualmente esclusivi per tipo di entità

	-- Ramo 2: persone del dominio
	SELECT
		s.Id,
		Tipo = 'P',
		TipoNome = 'Persona',
		IdSede = i.Id,
		i.IdDominio,
		s.Disabilitata,
		[Text] = s.NomeCompleto,
		s.ImpiegabileServizi
	FROM
		dbo.tblSediInterne i
		INNER JOIN dbo.tblSedi si ON i.Id = si.Id
		INNER JOIN dbo.tblPersone s ON i.Id = s.IdSede
	WHERE
		i.IdDominio = @IdDominio -- ✅ aggiunto: mancava
		AND si.Lock = 0
		AND s.Lock = 0
	UNION ALL

	-- Ramo 3: oggetti del dominio
	SELECT
		s.Id,
		Tipo = 'O',
		TipoNome = 'Oggetto',
		IdSede = i.Id,
		i.IdDominio,
		s.Disabilitata,
		[Text] = s.Nome,
		s.ImpiegabileServizi
	FROM
		dbo.tblSediInterne i
		INNER JOIN dbo.tblSedi si ON i.Id = si.Id
		INNER JOIN dbo.tblOggetti s ON i.Id = s.IdSede
	WHERE
		i.IdDominio = @IdDominio -- ✅ aggiunto: mancava
		AND si.Lock = 0
		AND s.Lock = 0
);
