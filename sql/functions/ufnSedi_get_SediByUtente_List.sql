
CREATE FUNCTION [dbo].[ufnSedi_get_SediByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Sedi esterne: condivise o non condivise secondo la funzione dedicata
	SELECT
		Id,
		IdParent,
		IdAziendaInterna,
		IdDominio,
		Condivisa,
		Disabilitata,
		Interna = CAST(0 AS BIT)
	FROM
		dbo.ufnSedi_get_SediEsterneByUtente_List(@IdUtente)
	UNION ALL -- mutualmente esclusivi: Interna=1 vs Interna=0
	-- Sedi interne: sempre non condivise per definizione
	SELECT
		Id,
		IdParent,
		IdAziendaInterna,
		IdDominio,
		Condivisa = CAST(0 AS BIT),
		Disabilitata,
		Interna = CAST(1 AS BIT)
	FROM
		dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente)
);
