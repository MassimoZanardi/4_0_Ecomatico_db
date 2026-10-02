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
		-- Esclusa solo se l'utente la vede gia' come condivisa (area di cui fa parte una sua azienda interna):
		-- l'azienda proprietaria vede sempre le proprie anagrafiche, anche in un'area di cui non fa parte
		AND NOT EXISTS ( SELECT 1 FROM dbo.tblAreeOsepe ae INNER JOIN dbo.tblAree a ON ae.Id = a.Id INNER JOIN dbo.tblAreeSediInterne ai ON a.Id = ai.Id INNER JOIN dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) x ON ai.IdSede = x.Id WHERE a.Lock = 0 AND ae.IdOsepe = s.Id )
);
