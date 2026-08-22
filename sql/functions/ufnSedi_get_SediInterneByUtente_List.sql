CREATE FUNCTION [dbo].[ufnSedi_get_SediInterneByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Amministratori: tutte le aziende interne del dominio (sedi dirette)
	SELECT
		s.Id,
		s.IdParent,
		IdAziendaInterna = s.Id,
		i.IdDominio,
		s.Disabilitata
	FROM
		dbo.tblUtenti u
	INNER JOIN dbo.tblSediInterne i ON u.IdDominio = i.IdDominio
	INNER JOIN dbo.tblSedi s ON i.Id = s.Id
	WHERE
		u.Id = @IdUtente
		AND u.IdRuolo = 'AD' -- AD = Amministratore
		AND s.Lock = 0
	UNION ALL -- ramo Admin/sotto-sedi: IdAziendaInterna diverso → no duplicati col ramo 1

	-- Amministratori: tutte le sotto-sedi delle aziende interne del dominio
	SELECT
		s.Id,
		s.IdParent,
		IdAziendaInterna = s.IdParent,
		i.IdDominio,
		s.Disabilitata
	FROM
		dbo.tblUtenti u
	INNER JOIN dbo.tblSediInterne i ON u.IdDominio = i.IdDominio
	INNER JOIN dbo.tblSedi s ON i.Id = s.IdParent
	WHERE
		u.Id = @IdUtente
		AND u.IdRuolo = 'AD' -- AD = Amministratore
		AND s.Lock = 0
	UNION ALL -- ramo Utente: mutualmente esclusivo con i rami Admin per design

	-- Utenti standard: solo le sedi direttamente associate
	SELECT
		s.Id,
		s.IdParent,
		IdAziendaInterna = i.Id,
		i.IdDominio,
		s.Disabilitata
	FROM
		dbo.tblUtentiSediInterne u
	INNER JOIN dbo.tblSedi s ON u.IdSede = s.Id
	INNER JOIN dbo.tblSediInterne i ON s.IdAziendaInterna = i.Id
	WHERE
		u.Id = @IdUtente
		AND s.Lock = 0
);
