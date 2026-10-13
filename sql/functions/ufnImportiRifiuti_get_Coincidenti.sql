SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: importi rifiuti attivi dell'azienda le cui variabili coincidono con i valori indicati
-- (regole O5 di docs/regole/offerte-contratti.md). È l'unico punto in cui è scritta la regola di coincidenza:
-- la leggono la fatturazione (ufnImportiRifiuti_get_Applicazione_List) e la verifica degli importi.
-- Funzione in linea senza TOP né sottoquery: applicata a più documenti diventa un join, e gli importi
-- dell'azienda si leggono una volta sola. Per questo non va aggiunto qui nulla che dipenda dal documento
-- oltre ai confronti delle variabili.
--
-- Coincidenza: tutte le variabili indicate nell'importo coincidono con i valori (una variabile NULL vale
-- "qualsiasi").
-- ETICHETTA: qui non viene verificata. IdEtichetta è quella indicata nell'importo (NULL = qualsiasi): chi
-- chiama scarta l'importo se la indica e il documento non ce l'ha tra le sue.
-- Classe:
--   V  candidato: importo standard (non associato a un contratto o a un'offerta), oppure importo di un
--      contratto attivo di un cliente con @Data compresa tra inizio e fine;
--   S  scartato: importo di un contratto attivo di un cliente non valido alla data (avviso "contratto scaduto");
--   X  mai candidato: importo di un'offerta o di un contratto cancellato.
-- Ordine di scelta tra i candidati: IdPriorita DESC, Standard (prima quello di un contratto), IdImporto.
CREATE OR ALTER FUNCTION dbo.ufnImportiRifiuti_get_Coincidenti (
	@IdAzienda CHAR(16),
	@Data DATE,
	@IdEer CHAR(6),
	@IdProduttoreParent CHAR(16),
	@IdProduttore CHAR(16),
	@IdTrasportatore CHAR(16),
	@IdDestinatario CHAR(16),
	@IdIntermediario CHAR(16))
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
		dbo.tblImportiRifiuti ir
		INNER JOIN dbo.tblImporti i ON ir.Id = i.Id
		LEFT JOIN dbo.tblOfferteContrattiImporti ci ON i.Id = ci.IdImporto
		-- FORCESEEK: il contratto si legge per chiave. Senza, applicata a molti documenti la funzione può finire
		-- a leggere tutti i contratti per ogni documento (misurato: 6 milioni di righe per 3.780 documenti)
		LEFT JOIN dbo.tblOfferteContratti oc WITH (FORCESEEK) ON ci.IdOffertaContratto = oc.Id
	WHERE
		-- Azienda: quella copiata sulle variabili (tblImportiRifiuti.IdSede), per leggere con un solo accesso
		-- gli importi dell'azienda senza passare da quelli di tutte le altre
		ir.IdSede = @IdAzienda
		AND i.Lock = 0
		AND (ir.IdEer IS NULL OR ir.IdEer = @IdEer)
		AND (ir.IdProduttoreParent IS NULL OR ir.IdProduttoreParent = @IdProduttoreParent)
		AND (ir.IdProduttore IS NULL OR ir.IdProduttore = @IdProduttore)
		AND (ir.IdTrasportatore IS NULL OR ir.IdTrasportatore = @IdTrasportatore)
		AND (ir.IdDestinatario IS NULL OR ir.IdDestinatario = @IdDestinatario)
		AND (ir.IdIntermediario IS NULL OR ir.IdIntermediario = @IdIntermediario)
);
GO
