SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Valori EFFETTIVI di ogni registrazione rifiuti ai fini di giacenze, relazioni carico/scarico, limiti ed
-- EoW. La registrazione originale non viene mai modificata da una rettifica (il registro, la stampa e la
-- conservazione devono riportarla com'e' stata inviata al RENTRI): i valori da usare per i calcoli sono
-- invece quelli dell'ultima rettifica di correzione confermata (Lock = 0), ordinata per data/numero della
-- rettifica, oppure Quantita = 0 se esiste un annullamento confermato. Le bozze (Lock = 2) non contano; una
-- rettifica cancellata prima dell'invio viene eliminata fisicamente insieme alla sua riga di tracking.
-- IsRettifica = 1: la registrazione e' essa stessa una rettifica/annullamento (non e' un movimento reale,
-- va sempre esclusa dai calcoli - i suoi valori restano quelli propri, esposti invariati).
-- IsAnnullata = 1: registrazione annullata; le sue relazioni restano (stampa/payload RENTRI) ma con
-- Quantita = 0 non contano piu' ne' come carico ne' come scarico.
CREATE OR ALTER VIEW [dbo].[viewRifiutiRegistrazioniEffettive]
AS
SELECT
	r.Id,
	r.IdMovimento,
	IdEer = CASE WHEN c.IdRettifica IS NOT NULL THEN c.IdEer ELSE m.IdEer END,
	EerDescrizione = CASE WHEN c.IdRettifica IS NOT NULL THEN c.EerDescrizione ELSE m.EerDescrizione END,
	IdStatoFisico = CASE WHEN c.IdRettifica IS NOT NULL THEN c.IdStatoFisico ELSE m.IdStatoFisico END,
	IdUnitaMisura = CASE WHEN c.IdRettifica IS NOT NULL THEN c.IdUnitaMisura ELSE m.IdUnitaMisura END,
	Quantita = CASE
		WHEN a.IdRettifica IS NOT NULL THEN CAST(0 AS DECIMAL(18, 2))
		WHEN c.IdRettifica IS NOT NULL THEN c.Quantita
		ELSE m.Quantita
	END,
	IsRettifica = CAST(IIF(t.IdRettifica IS NOT NULL, 1, 0) AS BIT),
	IsAnnullata = CAST(IIF(a.IdRettifica IS NOT NULL, 1, 0) AS BIT),
	IdRettificaCorrente = c.IdRettifica
FROM
	dbo.tblRifiutiRegistrazioni r
	INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
	LEFT JOIN dbo.tblRentriRegistrazioniRettifiche t ON t.IdRettifica = r.Id
	OUTER APPLY (
		SELECT TOP 1
			x.IdRettifica,
			mx.IdEer,
			mx.EerDescrizione,
			mx.IdStatoFisico,
			mx.IdUnitaMisura,
			mx.Quantita
		FROM
			dbo.tblRentriRegistrazioniRettifiche x
			INNER JOIN dbo.tblRifiutiRegistrazioni rx ON x.IdRettifica = rx.Id
			INNER JOIN dbo.tblRifiutiMovimenti mx ON rx.IdMovimento = mx.Id
		WHERE
			x.Id = r.Id
			AND ISNULL(x.Annullata, 0) = 0
			AND rx.Lock = 0
		ORDER BY
			rx.[Data] DESC,
			rx.Numero DESC
	) c
	OUTER APPLY (
		SELECT TOP 1 x.IdRettifica
		FROM
			dbo.tblRentriRegistrazioniRettifiche x
			INNER JOIN dbo.tblRifiutiRegistrazioni rx ON x.IdRettifica = rx.Id
		WHERE
			x.Id = r.Id
			AND x.Annullata = 1
			AND rx.Lock = 0
	) a;
GO
