SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Valori OPERATIVI di ogni registrazione rifiuti ai fini di giacenze, relazioni carico/scarico, limiti ed
-- EoW. La registrazione originale non viene mai modificata da una rettifica (registro, stampa, conservazione
-- e trasmissione la riportano com'e' stata inviata al RENTRI; ogni rettifica trasmette i propri valori - stato
-- amministrativo). I valori operativi sono quelli dell'ultima rettifica confermata (Lock = 0, di correzione o di
-- annullamento, ordinata per data/numero) letti dalla sua riga di tblRentriRegistrazioniRettifiche: li scrivono
-- uspRifiutiRegistrazioni_upd_Rettifica/_upd_Annullamento alla conferma, "tutto o niente" - i nuovi valori
-- (Quantita = 0 per un annullamento) se la rettifica non rende incoerenti le relazioni carico/scarico, altrimenti
-- quelli operativi precedenti (ufnRifiutiRegistrazioni_get_RettificaOperativa). Le bozze (Lock = 2) non contano;
-- una rettifica cancellata prima dell'invio viene eliminata fisicamente insieme alla sua riga di tracking.
-- IsRettifica = 1: la registrazione e' essa stessa una rettifica/annullamento (non e' un movimento reale,
-- va sempre esclusa dai calcoli - i suoi valori restano quelli propri, esposti invariati).
-- IsAnnullata = 1: registrazione annullata anche operativamente (annullamento confermato con Quantita operativa
-- 0 - un annullamento non operativo riguarda un carico gia' consumato, quindi con quantita' > 0); le sue
-- relazioni restano (stampa/payload RENTRI) ma non contano piu' ne' come carico ne' come scarico. Un
-- annullamento non operativo lascia la registrazione pienamente valida per Ecomatico (IsAnnullata = 0).
CREATE OR ALTER VIEW [dbo].[viewRifiutiRegistrazioniEffettive]
WITH SCHEMABINDING
AS
SELECT
	r.Id,
	r.IdMovimento,
	IdEer = CASE WHEN c.IdRettifica IS NOT NULL THEN c.IdEer ELSE m.IdEer END,
	EerDescrizione = CASE WHEN c.IdRettifica IS NOT NULL THEN c.EerDescrizione ELSE m.EerDescrizione END,
	IdStatoFisico = CASE WHEN c.IdRettifica IS NOT NULL THEN c.IdStatoFisico ELSE m.IdStatoFisico END,
	IdUnitaMisura = CASE WHEN c.IdRettifica IS NOT NULL THEN c.IdUnitaMisura ELSE m.IdUnitaMisura END,
	Quantita = CASE WHEN c.IdRettifica IS NOT NULL THEN c.Quantita ELSE m.Quantita END,
	IsRettifica = CAST(IIF(t.IdRettifica IS NOT NULL, 1, 0) AS BIT),
	IsAnnullata = CAST(IIF(c.Annullata = 1 AND c.Quantita = 0, 1, 0) AS BIT),
	IdRettificaCorrente = c.IdRettifica
FROM
	dbo.tblRifiutiRegistrazioni r
	INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
	LEFT JOIN dbo.tblRentriRegistrazioniRettifiche t ON t.IdRettifica = r.Id
	OUTER APPLY (
		SELECT TOP 1
			x.IdRettifica,
			x.IdEer,
			x.EerDescrizione,
			x.IdStatoFisico,
			x.IdUnitaMisura,
			x.Quantita,
			x.Annullata
		FROM
			dbo.tblRentriRegistrazioniRettifiche x
			INNER JOIN dbo.tblRifiutiRegistrazioni rx ON x.IdRettifica = rx.Id
		WHERE
			x.Id = r.Id
			AND rx.Lock = 0
		ORDER BY
			rx.[Data] DESC,
			rx.Numero DESC
	) c;
GO
