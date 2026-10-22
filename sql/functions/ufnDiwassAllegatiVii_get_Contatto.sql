SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Contatto proposto per un soggetto dell'Allegato VII (obbligatorio su DIWASS): la prima persona attiva della sede e il
-- primo telefono e la prima email tra i recapiti della sede
CREATE OR ALTER FUNCTION [dbo].[ufnDiwassAllegatiVii_get_Contatto] (
	@IdSede CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		Nome = (
			SELECT TOP 1 p.NomeCompleto
			FROM dbo.tblPersone p
			WHERE
				p.IdSede = @IdSede
				AND p.Lock = 0
				AND ISNULL(p.Disabilitata, 0) = 0
			ORDER BY p.NomeCompleto
		),
		Telefono = (
			SELECT TOP 1 r.Valore
			FROM dbo.tblSediRecapiti r
			WHERE
				r.Id = @IdSede
				AND r.IdRecapito LIKE 'T%'
				AND r.Valore IS NOT NULL
			ORDER BY r.IdRecapito
		),
		Email = (
			SELECT TOP 1 r.Valore
			FROM dbo.tblSediRecapiti r
			WHERE
				r.Id = @IdSede
				AND r.IdRecapito LIKE 'M%'
				AND r.Valore IS NOT NULL
			ORDER BY r.IdRecapito
		)
);
GO
