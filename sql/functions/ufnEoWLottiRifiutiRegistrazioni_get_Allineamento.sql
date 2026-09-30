SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Magazzino EoW allineato al registro operativo: per ogni allocazione della registrazione M
-- (@IdRegistrazione) calcola la quantita' allocata che resterebbe con la quantita' operativa @Quantita e il
-- materiale @IdMateriale. Unica regola, usata sia dall'allineamento
-- (uspEoWLottiRifiutiRegistrazioni_upd_Allinea) sia dall'anteprima della modale di conferma:
-- - lotto di materiale diverso da @IdMateriale (o @IdMateriale NULL: registrazione non piu' di materiale
--   prodotto) -> 0;
-- - se il totale allocato supera @Quantita la differenza si toglie rispettando il metodo con cui le
--   allocazioni sono nate (IdAllocazioneTipo), partendo dall'ultima allocazione fatta (Pos piu' alta):
--   percentuale (P) = tutte le allocazioni in percentuale come un blocco unico, ridotto in proporzione
--   (arrotondamento a 2 decimali, resto sull'ultimo lotto del blocco); priorita' (C), lotto unico (U) e
--   manuale (NULL) = lotto per lotto dall'ultimo riempito (per C la Pos segue la priorita', quindi si
--   svuota prima il lotto a priorita' piu' bassa). Righe senza Pos (pregresso) per ultime, poi lotto aperto
--   piu' di recente;
-- - se @Quantita e' maggiore o uguale al totale allocato le allocazioni restano invariate (la differenza e'
--   "da allocare").
-- QuantitaNuova = 0 significa che l'allocazione va rimossa.
CREATE OR ALTER FUNCTION dbo.ufnEoWLottiRifiutiRegistrazioni_get_Allineamento (
	@IdRegistrazione CHAR(16),
	@Quantita DECIMAL(18, 2),
	@IdMateriale CHAR(2)
)
RETURNS TABLE
AS
RETURN
WITH a AS (
	SELECT
		q.IdLotto,
		Quantita = ISNULL(q.Quantita, 0),
		IsCompatibile = CAST(IIF(@IdMateriale IS NOT NULL AND l.IdMateriale = @IdMateriale, 1, 0) AS BIT),
		IsPercentuale = CAST(IIF(q.IdAllocazioneTipo = 'P', 1, 0) AS BIT),
		-- Blocco di riduzione: le allocazioni in percentuale formano un unico blocco, le altre un blocco per lotto
		Blocco = IIF(q.IdAllocazioneTipo = 'P', CAST('P' AS CHAR(16)), q.IdLotto),
		Pos = ISNULL(q.Pos, 0),
		l.DataApertura
	FROM
		dbo.tblEoWLottiRifiutiRegistrazioni q
		INNER JOIN dbo.tblEoWLotti l ON q.IdLotto = l.Id
	WHERE q.IdRegistrazione = @IdRegistrazione),
e AS (
	-- Parte del totale compatibile che eccede la quantita' operativa
	SELECT Eccesso = ISNULL(SUM(Quantita), 0) - ISNULL(@Quantita, 0)
	FROM a
	WHERE IsCompatibile = 1),
b AS (
	SELECT
		Blocco,
		Totale = SUM(Quantita),
		Pos = MAX(Pos),
		DataApertura = MAX(DataApertura)
	FROM a
	WHERE IsCompatibile = 1
	GROUP BY Blocco
),
bc AS (
	-- Totale cumulato dall'ultimo blocco allocato (compreso quello della riga)
	SELECT
		b.Blocco,
		b.Totale,
		Cumulata = SUM(b.Totale) OVER (
			ORDER BY
				b.Pos DESC,
				b.DataApertura DESC,
				b.Blocco DESC
			ROWS UNBOUNDED PRECEDING)
	FROM b
),
br AS (
	-- Quantita' da togliere a ciascun blocco
	SELECT
		bc.Blocco,
		bc.Totale,
		Riduzione = CASE
			WHEN e.Eccesso <= 0 THEN CAST(0 AS DECIMAL(18, 2))
			WHEN e.Eccesso - (bc.Cumulata - bc.Totale) <= 0 THEN CAST(0 AS DECIMAL(18, 2))
			WHEN e.Eccesso - (bc.Cumulata - bc.Totale) >= bc.Totale THEN bc.Totale
			ELSE e.Eccesso - (bc.Cumulata - bc.Totale)
		END
	FROM
		bc
		CROSS JOIN e
),
r AS (
	SELECT
		a.IdLotto,
		a.Blocco,
		a.Quantita,
		a.IsCompatibile,
		Riduzione = ISNULL(br.Riduzione, 0),
		-- Blocco percentuale: quota proporzionale arrotondata a 2 decimali; negli altri blocchi (un solo lotto)
		-- tutta la riduzione del blocco
		RiduzioneRiga = CAST(IIF(a.IsPercentuale = 1 AND br.Totale > 0, ROUND(br.Riduzione * a.Quantita / br.Totale, 2), ISNULL(br.Riduzione, 0)) AS DECIMAL(18, 2)),
		IsUltimaDelBlocco = IIF(ROW_NUMBER() OVER (PARTITION BY a.Blocco ORDER BY a.Pos DESC, a.DataApertura DESC, a.IdLotto DESC) = 1, 1, 0)
	FROM
		a
		LEFT JOIN br ON a.Blocco = br.Blocco
),
rr AS (
	SELECT
		r.IdLotto,
		r.Quantita,
		r.IsCompatibile,
		r.Riduzione,
		-- Resto dell'arrotondamento del blocco sull'ultimo lotto del blocco (Pos piu' alta)
		RiduzioneFinale = r.RiduzioneRiga + IIF(r.IsUltimaDelBlocco = 1, r.Riduzione - SUM(r.RiduzioneRiga) OVER (PARTITION BY r.Blocco), 0)
	FROM r
	WHERE r.IsCompatibile = 1
	UNION ALL
	SELECT
		r.IdLotto,
		r.Quantita,
		r.IsCompatibile,
		r.Riduzione,
		RiduzioneFinale = r.Quantita
	FROM r
	WHERE r.IsCompatibile = 0)
SELECT
	rr.IdLotto,
	rr.Quantita,
	QuantitaNuova = CASE
		WHEN rr.IsCompatibile = 0 THEN CAST(0 AS DECIMAL(18, 2))
		WHEN rr.Riduzione = 0 THEN rr.Quantita
		WHEN rr.Quantita - rr.RiduzioneFinale < 0 THEN CAST(0 AS DECIMAL(18, 2))
		ELSE CAST(rr.Quantita - rr.RiduzioneFinale AS DECIMAL(18, 2))
	END
FROM rr;
GO
