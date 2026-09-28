SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Decide se una rettifica (@IdRettifica, di correzione o di annullamento) puo' valere anche per lo stato
-- OPERATIVO di Ecomatico (giacenze, residui, relazioni carico/scarico) oltre che per quello amministrativo
-- RENTRI, che riceve sempre i valori della rettifica. Restituisce una riga con i valori operativi in vigore
-- PRIMA della rettifica (ultima altra rettifica confermata dell'originale, altrimenti i valori propri
-- dell'originale) e IsOperativa. Regola "tutto o niente": se la rettifica renderebbe incoerenti le relazioni
-- dell'originale restano operativi tutti i valori precedenti.
-- Relazioni considerate: su entrambi i lati, quantita' > 0, nessuna delle due registrazioni in bozza, la
-- controparte non annullata operativamente (viewRifiutiRegistrazioniEffettive.IsAnnullata).
-- Correzione (@IdEer/@IdStatoFisico/@IdUnitaMisura/@Quantita = nuovi valori) non operativa se l'originale ha
-- relazioni e: Eer/stato fisico/unita' di misura cambiano, oppure la quantita' scende sotto quella gia'
-- prelevata dalle registrazioni padre (lato figlio), oppure cambia la quantita' di una registrazione che ha
-- figli (lato padre: le quantita' delle relazioni sono gia' distribuite su quella quantita').
-- Annullamento (parametri valore ignorati) non operativo se l'originale e' figlio di relazioni attive: carico
-- gia' consumato da scarichi (padre S), oppure scarico da cui derivano carichi (padre C, es. scarico per
-- trattamento interno I con carichi M/NP generati) - escluderlo lascerebbe carichi derivati da uno scarico a 0.
-- Uno scarico senza carichi derivati e' annullabile anche operativamente (i carichi che consumava tornano
-- disponibili), cosi' come un carico non consumato (es. un carico Materiale, che non puo' mai essere figlio).
-- Le quote EoW e il magazzino non contano: il registro prevale, i moduli si adeguano.
-- Chiamata da uspRifiutiRegistrazioni_upd_Rettifica/_upd_Annullamento (alla conferma, sotto lock) e da
-- uspRifiutiRegistrazioni_get_RettificaIsOperativa (anteprima per la modale di conferma in Edit).
CREATE OR ALTER FUNCTION [dbo].[ufnRifiutiRegistrazioni_get_RettificaOperativa] (
	@IdRettifica CHAR(16),
	@IdEer CHAR(6),
	@IdStatoFisico CHAR(1),
	@IdUnitaMisura CHAR(2),
	@Quantita DECIMAL(18, 2)
)
RETURNS TABLE
AS
RETURN
WITH p AS (
	SELECT
		t.Id,
		IsAnnullamento = ISNULL(t.Annullata, 0),
		IdEer = CASE WHEN c.IdRettifica IS NOT NULL THEN c.IdEer ELSE m.IdEer END,
		EerDescrizione = CASE WHEN c.IdRettifica IS NOT NULL THEN c.EerDescrizione ELSE m.EerDescrizione END,
		IdStatoFisico = CASE WHEN c.IdRettifica IS NOT NULL THEN c.IdStatoFisico ELSE m.IdStatoFisico END,
		IdUnitaMisura = CASE WHEN c.IdRettifica IS NOT NULL THEN c.IdUnitaMisura ELSE m.IdUnitaMisura END,
		Quantita = CASE WHEN c.IdRettifica IS NOT NULL THEN c.Quantita ELSE m.Quantita END
	FROM
		dbo.tblRentriRegistrazioniRettifiche t
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON t.Id = r.Id
		INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		OUTER APPLY (
			SELECT TOP 1
				x.IdRettifica,
				x.IdEer,
				x.EerDescrizione,
				x.IdStatoFisico,
				x.IdUnitaMisura,
				x.Quantita
			FROM
				dbo.tblRentriRegistrazioniRettifiche x
				INNER JOIN dbo.tblRifiutiRegistrazioni rx ON x.IdRettifica = rx.Id
			WHERE
				x.Id = t.Id
				AND x.IdRettifica <> @IdRettifica
				AND rx.Lock = 0
			ORDER BY
				rx.[Data] DESC,
				rx.Numero DESC
		) c
	WHERE t.IdRettifica = @IdRettifica),
l AS (
	SELECT
		a.Id,
		a.IdParent,
		a.Quantita
	FROM
		p
		INNER JOIN dbo.tblRifiutiRegistrazioniRelazioni a ON a.Id = p.Id OR a.IdParent = p.Id
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON a.Id = r.Id
		INNER JOIN dbo.tblRifiutiRegistrazioni rp ON a.IdParent = rp.Id
		INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON a.Id = v.Id
		INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON a.IdParent = vp.Id
	WHERE
		a.Quantita > 0
		AND r.Lock < 2
		AND rp.Lock < 2
		AND
			(
			a.Id = p.Id
			OR v.IsAnnullata = 0
			)
		AND
			(
			a.IdParent = p.Id
			OR vp.IsAnnullata = 0
			)
)
SELECT
	p.Id,
	p.IsAnnullamento,
	p.IdEer,
	p.EerDescrizione,
	p.IdStatoFisico,
	p.IdUnitaMisura,
	p.Quantita,
	IsOperativa = CAST(CASE
		WHEN p.IsAnnullamento = 1 THEN IIF(EXISTS (
			SELECT 1
			FROM l
			WHERE l.Id = p.Id), 0, 1)
		WHEN NOT EXISTS (SELECT 1
		FROM l) THEN 1
		WHEN ISNULL(@IdEer, '') <> ISNULL(p.IdEer, '')
			OR ISNULL(@IdStatoFisico, '') <> ISNULL(p.IdStatoFisico, '')
			OR ISNULL(@IdUnitaMisura, '') <> ISNULL(p.IdUnitaMisura, '') THEN 0
		WHEN ISNULL(@Quantita, 0) < (SELECT ISNULL(SUM(l.Quantita), 0)
		FROM l
		WHERE l.Id = p.Id) THEN 0
		WHEN ISNULL(@Quantita, 0) <> ISNULL(p.Quantita, 0) AND EXISTS (SELECT 1
		FROM l
		WHERE l.IdParent = p.Id) THEN 0
		ELSE 1
	END AS BIT)
FROM p;
GO
