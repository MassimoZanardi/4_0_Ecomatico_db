SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: importi dei servizi attivi dell'azienda le cui variabili coincidono con i valori di un
-- servizio. È l'unico punto in cui è scritta la regola di coincidenza per i servizi, come
-- ufnImportiMagazzino_get_Coincidenti per il magazzino: la leggono la fatturazione e la verifica degli importi.
-- Funzione in linea senza TOP né sottoquery: applicata a più servizi diventa un join. Per questo non va aggiunto
-- qui nulla che dipenda dal documento oltre ai confronti delle variabili.
--
-- L'importo dei servizi è un listino: si sceglie sul servizio, non sulle sue risorse. Le risorse non sono
-- variabili: stanno sulle righe dell'importo (tblImportiRigheServizi) e le guarda chi calcola le righe di fattura.
-- Coincidenza: tutte le variabili indicate nell'importo coincidono con i valori (una variabile NULL vale
-- "qualsiasi").
--   @IdTipo: tipo del servizio.
--   @IdRichiedenteParent: soggetto del richiedente del servizio; @IdRichiedente: la sede richiedente.
--   @IdSedeInterna: sede interna del calendario che ospita il servizio.
-- ETICHETTA: qui non viene verificata. IdEtichetta è quella indicata nell'importo (NULL = qualsiasi): chi
-- chiama scarta l'importo se la indica e il servizio non ce l'ha tra le sue.
-- Classe:
--   V  candidato: importo standard (non associato a un contratto o a un'offerta), oppure importo di un
--      contratto attivo di un cliente con @Data compresa tra inizio e fine;
--   S  scartato: importo di un contratto attivo di un cliente non valido alla data (avviso "contratto scaduto");
--   X  mai candidato: importo di un'offerta o di un contratto cancellato.
-- Ordine di scelta tra i candidati: IdPriorita DESC, Standard (prima quello di un contratto), IdImporto.
CREATE OR ALTER FUNCTION dbo.ufnImportiServizi_get_Coincidenti (
	@IdAzienda CHAR(16),
	@Data DATE,
	@IdTipo CHAR(16),
	@IdRichiedenteParent CHAR(16),
	@IdRichiedente CHAR(16),
	@IdSedeInterna CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		IdImporto = i.Id,
		i.IdPriorita,
		ir.IdEtichetta,
		IdOffertaContratto = oc.Id,
		IdClienteContratto = oc.IdClienteFornitore,
		Standard = CAST(IIF(ci.IdImporto IS NULL, 1, 0) AS BIT),
		Classe = CAST(CASE
			WHEN ci.IdImporto IS NULL THEN 'V'
			WHEN oc.Lock = 0 AND oc.Tipo = 'C' AND oc.ClienteFornitoreTipo = 'C' AND @Data BETWEEN oc.DataInizio AND oc.DataFine THEN 'V'
			WHEN oc.Lock = 0 AND oc.Tipo = 'C' AND oc.ClienteFornitoreTipo = 'C' AND NOT (@Data BETWEEN oc.DataInizio AND oc.DataFine) THEN 'S'
			ELSE 'X'
		END AS CHAR(1))
	FROM
		dbo.tblImportiServizi ir
		INNER JOIN dbo.tblImporti i ON ir.Id = i.Id
		LEFT JOIN dbo.tblOfferteContrattiImporti ci ON i.Id = ci.IdImporto
		-- FORCESEEK: il contratto si legge per chiave, come in ufnImportiRifiuti_get_Coincidenti
		LEFT JOIN dbo.tblOfferteContratti oc WITH (FORCESEEK) ON ci.IdOffertaContratto = oc.Id
	WHERE
		-- Azienda: quella copiata sulle variabili (tblImportiServizi.IdSede)
		ir.IdSede = @IdAzienda
		AND i.Lock = 0
		AND (ir.IdTipo IS NULL OR ir.IdTipo = @IdTipo)
		AND (ir.IdRichiedenteParent IS NULL OR ir.IdRichiedenteParent = @IdRichiedenteParent)
		AND (ir.IdRichiedente IS NULL OR ir.IdRichiedente = @IdRichiedente)
		AND (ir.IdSedeInterna IS NULL OR ir.IdSedeInterna = @IdSedeInterna)
);
GO
