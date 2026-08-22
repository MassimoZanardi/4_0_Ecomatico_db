CREATE OR ALTER FUNCTION [dbo].[ufnSedi_get_AziendeEsterneNonCondiviseByDominio_List] (
	@IdDominio CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	SELECT
		s.Id,
		s.IdParent,
		IdAziendaInterna = se.IdSedeInterna,
		i.IdDominio,
		s.Disabilitata
	FROM
		dbo.tblSediInterne i
		INNER JOIN dbo.tblSedi si ON i.Id = si.Id
		INNER JOIN dbo.tblSediEsterne se ON si.Id = se.IdSedeInterna
		INNER JOIN dbo.tblSedi s ON se.Id = s.Id
	WHERE
		i.IdDominio = @IdDominio
		AND si.Lock = 0
		AND s.Lock = 0
);
