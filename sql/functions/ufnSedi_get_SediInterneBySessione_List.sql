CREATE FUNCTION [dbo].[ufnSedi_get_SediInterneBySessione_List] (
	@IdSessione CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	SELECT
		s.Id,
		s.IdParent,
		s.IdAziendaInterna,
		s.IdDominio,
		s.Disabilitata
	FROM
		dbo.tblSessioni e
		CROSS APPLY dbo.ufnSedi_get_SediInterneByUtente_List(e.IdUtente) s
	WHERE e.Id = @IdSessione);
