SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Sedi collegabili a DIWASS per la sessione (Diwass > Operatori): aziende e sedi, interne ed esterne, dell'azienda
-- interna del contesto (Condivisa = 0, modificabili) più i soggetti condivisi da altre aziende nelle Aree, con le
-- loro sedi (Condivisa = 1, sola lettura: il collegamento lo gestisce l'azienda proprietaria). Stesso perimetro di
-- uspSedi_get_AziendeEsterne_List. Senza azienda nel contesto nessuna riga
CREATE OR ALTER FUNCTION [dbo].[ufnDiwassOperatori_get_SediBySessione_List] (
	@IdSessione CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		s.Id,
		Condivisa = CAST(0 AS BIT),
		Area = CAST(NULL AS VARCHAR(50))
	FROM
		dbo.tblSedi s
		INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
	WHERE
		e.Id = @IdSessione
		AND s.Lock = 0
	UNION ALL -- rami mutualmente esclusivi: il secondo esclude le sedi dell'azienda del contesto

	SELECT
		s.Id,
		Condivisa = CAST(1 AS BIT),
		Area = CAST(MIN(c.Area) AS VARCHAR(50))
	FROM
		dbo.tblSessioni e
		CROSS APPLY dbo.ufnSedi_get_AziendeEsterneCondiviseByUtente_List(e.IdUtente) c
		INNER JOIN dbo.tblSedi s ON s.Id = c.Id OR s.IdParent = c.Id
	WHERE
		e.Id = @IdSessione
		AND c.IdAziendaInterna <> e.IdAzienda
		AND s.IdAziendaInterna <> e.IdAzienda
		AND s.Lock = 0
	GROUP BY s.Id
);
GO
