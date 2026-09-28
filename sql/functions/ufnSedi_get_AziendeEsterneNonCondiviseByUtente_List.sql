SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnSedi_get_AziendeEsterneNonCondiviseByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	SELECT
		se.Id,
		s.IdParent,
		s.IdAziendaInterna,
		i.IdDominio,
		s.Disabilitata
	FROM
		dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) i
		INNER JOIN dbo.tblSediEsterne se ON i.Id = se.IdSedeInterna
		INNER JOIN dbo.tblSedi s ON se.Id = s.Id
	WHERE
		s.Lock = 0
		AND NOT EXISTS ( SELECT 1 FROM dbo.tblAreeOsepe ae INNER JOIN dbo.tblAree a ON ae.Id = a.Id WHERE a.Lock = 0 AND ae.IdOsepe = s.Id )
);
