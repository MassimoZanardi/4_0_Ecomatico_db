SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Totali di una fattura, calcolati dalle righe e mai memorizzati. Importo della riga = prezzo unitario:
-- imponibile della riga = Quantita x Importo, arrotondato al centesimo. L'IVA si calcola sull'imponibile
-- complessivo di ciascuna aliquota (come nel riepilogo della fattura elettronica), la ritenuta d'acconto allo
-- stesso modo sull'imponibile complessivo di ciascuna percentuale: l'arrotondamento al centesimo si fa una
-- volta sola, non riga per riga. Totale = imponibile + IVA + bollo. Netto a pagare = totale - ritenuta e, con lo split
-- payment, - IVA (la versa il cliente all'erario).
CREATE OR ALTER FUNCTION dbo.ufnFatture_get_Totali (@IdFattura CHAR(16))
RETURNS TABLE
AS
RETURN
(
	WITH righe AS (
		SELECT
			i.IdAliquotaIva,
			Imponibile = CAST(ROUND(ISNULL(i.Quantita, 1) * ISNULL(i.Importo, 0), 2) AS DECIMAL(18, 2)),
			RitenutaAcconto = ISNULL(i.RitenutaAcconto, 0)
		FROM
			dbo.tblFattureRighe r
			INNER JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
		WHERE r.IdFattura = @IdFattura),
	aliquote AS (
		SELECT
			Imponibile = SUM(g.Imponibile),
			Iva = CAST(ROUND(SUM(g.Imponibile) * ISNULL(MAX(a.Valore), 0) / 100, 2) AS DECIMAL(18, 2))
		FROM
			righe g
			LEFT JOIN dbo.tblAliquoteIva a ON g.IdAliquotaIva = a.Id
		GROUP BY g.IdAliquotaIva
	),
	totali AS (
		SELECT
			Imponibile = ISNULL((SELECT SUM(Imponibile) FROM aliquote), 0),
			Iva = ISNULL((SELECT SUM(Iva) FROM aliquote), 0),
			Ritenuta = ISNULL((SELECT SUM(x.Ritenuta) FROM (SELECT Ritenuta = CAST(ROUND(SUM(Imponibile) * RitenutaAcconto / 100.0, 2) AS DECIMAL(18, 2)) FROM righe GROUP BY RitenutaAcconto) x), 0)
	)
	SELECT
		Imponibile = CAST(t.Imponibile AS DECIMAL(18, 2)),
		Iva = CAST(t.Iva AS DECIMAL(18, 2)),
		Ritenuta = CAST(t.Ritenuta AS DECIMAL(18, 2)),
		Bollo = CAST(ISNULL(f.Bollo, 0) AS DECIMAL(18, 2)),
		Totale = CAST(t.Imponibile + t.Iva + ISNULL(f.Bollo, 0) AS DECIMAL(18, 2)),
		NettoAPagare = CAST(t.Imponibile + t.Iva + ISNULL(f.Bollo, 0) - t.Ritenuta - IIF(ISNULL(f.SplitPayment, 0) = 1, t.Iva, 0) AS DECIMAL(18, 2))
	FROM
		dbo.tblFatture f
		CROSS JOIN totali t
	WHERE f.Id = @IdFattura);
GO
