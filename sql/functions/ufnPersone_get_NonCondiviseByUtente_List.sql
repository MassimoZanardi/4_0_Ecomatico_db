SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnPersone_get_NonCondiviseByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	SELECT
		s.Id,
		s.IdSede,
		i.IdDominio,
		s.Disabilitata
	FROM
		dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) i
		INNER JOIN dbo.tblPersone s ON i.Id = s.IdSede
	WHERE
		s.Lock = 0
		AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblAreeOsepe ae
				INNER JOIN dbo.tblAree a ON ae.Id = a.Id
			WHERE a.Lock = 0 AND ae.IdOsepe = s.Id -- esclude persone condivise tramite area
		)
);
