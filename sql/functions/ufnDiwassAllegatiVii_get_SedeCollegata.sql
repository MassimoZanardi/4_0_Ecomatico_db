SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Sede da indicare nell'Allegato VII per una sede di Ecomatico: la sede stessa se è collegata a DIWASS, altrimenti
-- la sua azienda se collegata (Sostituita = 1: sul documento comparirà l'azienda, docs/regole/diwass.md D4.2).
-- Nessuna riga se né la sede né l'azienda sono collegate. Solo operatori con il ruolo WSR nuovo o valido
CREATE OR ALTER FUNCTION [dbo].[ufnDiwassAllegatiVii_get_SedeCollegata] (
	@IdSede CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT TOP 1
		IdSede = c.Id,
		Sostituita = c.Sostituita
	FROM (
		SELECT
			o.Id,
			Sostituita = CAST(0 AS BIT),
			Ordine = 0
		FROM dbo.tblDiwassOperatori o
		WHERE
			o.Id = @IdSede
			AND o.Stato IN ('NEW', 'VALID')
		UNION ALL
		SELECT
			o.Id,
			Sostituita = CAST(1 AS BIT),
			Ordine = 1
		FROM
			dbo.tblSedi s
			INNER JOIN dbo.tblDiwassOperatori o ON s.IdParent = o.Id
		WHERE
			s.Id = @IdSede
			AND o.Stato IN ('NEW', 'VALID')
	) c
	ORDER BY c.Ordine
);
GO
