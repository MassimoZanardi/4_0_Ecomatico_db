CREATE FUNCTION [dbo].[ufnOggetti_get_NonCondivisiByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	SELECT
		s.Id,
		s.IdSede,
		i.IdDominio
	FROM
		dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) i
	INNER JOIN dbo.tblOggetti s ON i.Id = s.IdSede
	WHERE
		s.Lock = 0
		AND NOT EXISTS ( SELECT 1 FROM dbo.tblAreeOsepe ae INNER JOIN dbo.tblAree a ON ae.Id = a.Id WHERE a.Lock = 0 AND ae.IdOsepe = s.Id )
);
