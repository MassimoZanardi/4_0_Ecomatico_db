SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: importi di magazzino attivi dell'azienda le cui variabili coincidono con i valori di una
-- riga di DDT. È l'unico punto in cui è scritta la regola di coincidenza per il magazzino, come
-- ufnImportiRifiuti_get_Coincidenti per i rifiuti: la leggono la fatturazione e la verifica degli importi.
-- Funzione in linea senza TOP né sottoquery: applicata a più righe diventa un join. Per questo non va aggiunto
-- qui nulla che dipenda dal documento oltre ai confronti delle variabili.
--
-- Il confronto è per riga del DDT: @IdArticolo per una riga articolo, @IdMateriale per una riga EoW (l'altro è
-- NULL). Un importo che indica un articolo non coincide con una riga EoW, e viceversa; un importo che non
-- indica né l'uno né l'altro coincide con qualsiasi riga.
-- Coincidenza: tutte le variabili indicate nell'importo coincidono con i valori (una variabile NULL vale
-- "qualsiasi"). Destinatario: @IdDestinatarioParent è il soggetto, @IdDestinatario la sua sede.
-- ETICHETTA: qui non viene verificata. IdEtichetta è quella indicata nell'importo (NULL = qualsiasi): chi
-- chiama scarta l'importo se la indica e il DDT non ce l'ha tra le sue.
-- Classe:
--   V  candidato: importo standard (non associato a un contratto o a un'offerta), oppure importo di un
--      contratto attivo di un cliente con @Data compresa tra inizio e fine;
--   S  scartato: importo di un contratto attivo di un cliente non valido alla data (avviso "contratto scaduto");
--   X  mai candidato: importo di un'offerta o di un contratto cancellato.
-- Ordine di scelta tra i candidati: IdPriorita DESC, Standard (prima quello di un contratto), IdImporto.
CREATE OR ALTER FUNCTION dbo.ufnImportiMagazzino_get_Coincidenti (
	@IdAzienda CHAR(16),
	@Data DATE,
	@IdDestinatarioParent CHAR(16),
	@IdDestinatario CHAR(16),
	@IdArticolo CHAR(16),
	@IdMateriale CHAR(2))
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
		dbo.tblImportiMagazzino ir
		INNER JOIN dbo.tblImporti i ON ir.Id = i.Id
		LEFT JOIN dbo.tblOfferteContrattiImporti ci ON i.Id = ci.IdImporto
		-- FORCESEEK: il contratto si legge per chiave, come in ufnImportiRifiuti_get_Coincidenti
		LEFT JOIN dbo.tblOfferteContratti oc WITH (FORCESEEK) ON ci.IdOffertaContratto = oc.Id
	WHERE
		-- Azienda: quella copiata sulle variabili (tblImportiMagazzino.IdSede)
		ir.IdSede = @IdAzienda
		AND i.Lock = 0
		AND (ir.IdArticolo IS NULL OR ir.IdArticolo = @IdArticolo)
		AND (ir.IdMateriale IS NULL OR ir.IdMateriale = @IdMateriale)
		AND (ir.IdDestinatarioParent IS NULL OR ir.IdDestinatarioParent = @IdDestinatarioParent)
		AND (ir.IdDestinatario IS NULL OR ir.IdDestinatario = @IdDestinatario)
);
GO
