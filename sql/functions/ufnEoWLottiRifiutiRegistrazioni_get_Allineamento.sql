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
-- - se il totale allocato supera @Quantita la differenza si toglie partendo dall'ultimo lotto riempito
--   (Pos piu' alta; righe senza Pos per ultime, poi lotto aperto piu' di recente), fino ad azzerare;
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
		-- Quantita cumulata dall'ultimo lotto riempito (compreso quello della riga), solo lotti compatibili
		Cumulata = SUM(IIF(@IdMateriale IS NOT NULL AND l.IdMateriale = @IdMateriale, ISNULL(q.Quantita, 0), 0)) OVER (
			ORDER BY
				IIF(@IdMateriale IS NOT NULL AND l.IdMateriale = @IdMateriale, 0, 1),
				ISNULL(q.Pos, 0) DESC,
				l.DataApertura DESC,
				q.IdLotto DESC
			ROWS UNBOUNDED PRECEDING),
		-- Parte del totale compatibile che eccede la quantita' operativa
		Eccesso = SUM(IIF(@IdMateriale IS NOT NULL AND l.IdMateriale = @IdMateriale, ISNULL(q.Quantita, 0), 0)) OVER () - ISNULL(@Quantita, 0)
	FROM
		dbo.tblEoWLottiRifiutiRegistrazioni q
		INNER JOIN dbo.tblEoWLotti l ON q.IdLotto = l.Id
	WHERE q.IdRegistrazione = @IdRegistrazione)
SELECT
	a.IdLotto,
	a.Quantita,
	QuantitaNuova = CASE
		WHEN a.IsCompatibile = 0 THEN CAST(0 AS DECIMAL(18, 2))
		WHEN a.Eccesso <= 0 THEN a.Quantita
		-- Eccesso ancora da togliere arrivati a questa riga (gia' coperto dalle righe riempite dopo?)
		WHEN a.Eccesso - (a.Cumulata - a.Quantita) <= 0 THEN a.Quantita
		WHEN a.Eccesso - (a.Cumulata - a.Quantita) >= a.Quantita THEN CAST(0 AS DECIMAL(18, 2))
		ELSE a.Quantita - (a.Eccesso - (a.Cumulata - a.Quantita))
	END
FROM a;
GO
