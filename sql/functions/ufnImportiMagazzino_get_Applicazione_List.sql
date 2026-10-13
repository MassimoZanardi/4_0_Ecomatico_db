SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, magazzino: per ogni DDT, il riepilogo degli importi applicati alle sue righe
-- (ufnImportiMagazzino_get_ApplicazioneRighe_List) e il cliente a cui fatturarlo. Una riga per movimento con
-- un DDT; è l'analogo di ufnImportiRifiuti_get_Applicazione_List, con il confronto fatto per riga.
--   Parametri: quelli di ufnImportiMagazzino_get_ApplicazioneRighe_List.
-- Righe: righe articolo ed EoW del DDT. RigheSenzaImporto: quelle a cui nessun importo coincide: se ce n'è
-- anche una sola il DDT intero non viene fatturato (non si fattura una parte del DDT).
-- IdImporto, IdOffertaContratto: l'importo e il contratto applicati, solo se sono gli stessi per tutte le righe
-- (altrimenti NULL): servono al legame in tblFattureDocumenti e al raggruppamento per contratto.
-- Cliente (ClienteOrigine): D quello indicato sul DDT (tblFattureDocumenti), altrimenti C quello dei contratti
-- degli importi applicati, altrimenti P la scheda cliente attiva del soggetto destinatario. ClientiDiversi = 1:
-- le righe hanno importi di contratti di clienti diversi e sul DDT non è indicato un cliente: va indicato.
-- IdFattura: solo se la fattura non è cancellata. IsPreFattura, IdClientePreFattura: come per i rifiuti.
CREATE OR ALTER FUNCTION dbo.ufnImportiMagazzino_get_Applicazione_List (
	@Id CHAR(16),
	@IdAzienda CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@SoloFatturabili BIT)
RETURNS TABLE
AS
RETURN
(
	SELECT
		doc.Id,
		doc.IdDdt,
		doc.[Data],
		doc.Numero,
		doc.Sezionale,
		doc.Lock,
		doc.IdAzienda,
		doc.IdSedeDdt,
		doc.IsFatturabile,
		doc.IdDestinatario,
		doc.IdDestinatarioParent,
		doc.IdDestinazione,
		IdClienteIndicato = d.IdClienteFornitore,
		NonFatturabile = CAST(ISNULL(d.NonFatturabile, 0) AS BIT),
		IdFattura = f.Id,
		IsPreFattura = CAST(IIF(f.IdTipo = 'TD00', 1, 0) AS BIT),
		IdClientePreFattura = IIF(f.IdTipo = 'TD00', f.IdClienteFornitore, NULL),
		Righe = ISNULL(g.Righe, 0),
		RigheSenzaImporto = ISNULL(g.RigheSenzaImporto, 0),
		RigheScartate = ISNULL(g.RigheScartate, 0),
		IdImporto = IIF(g.ImportoMin = g.ImportoMax AND g.RigheSenzaImporto = 0, g.ImportoMin, NULL),
		IdOffertaContratto = IIF(g.ContrattoMin = g.ContrattoMax AND g.RigheStandard = 0 AND g.RigheSenzaImporto = 0, g.ContrattoMin, NULL),
		IdClienteFornitore = COALESCE(d.IdClienteFornitore, IIF(g.ClienteMin = g.ClienteMax, g.ClienteMin, NULL), IIF(g.ClienteMin IS NULL, cp.Id, NULL)),
		ClienteOrigine = CAST(CASE
			WHEN d.IdClienteFornitore IS NOT NULL THEN 'D'
			WHEN g.ClienteMin = g.ClienteMax THEN 'C'
			WHEN g.ClienteMin IS NULL AND cp.Id IS NOT NULL THEN 'P'
		END AS CHAR(1)),
		ClientiDiversi = CAST(IIF(d.IdClienteFornitore IS NULL AND g.ClienteMin <> g.ClienteMax, 1, 0) AS BIT)
	FROM
		dbo.ufnImportiMagazzino_get_Documenti(@Id, @IdAzienda, @DataDa, @DataA) doc
		LEFT JOIN dbo.tblFattureDocumenti d ON doc.Id = d.Id
		LEFT JOIN dbo.tblFatture f ON d.IdFattura = f.Id
								  AND f.Lock IN (0, 2)
		LEFT JOIN (
			SELECT
				r.IdMovimento,
				Righe = COUNT(*),
				RigheSenzaImporto = SUM(IIF(r.IdImporto IS NULL, 1, 0)),
				RigheScartate = SUM(IIF(r.IdImportoScartato IS NOT NULL, 1, 0)),
				RigheStandard = SUM(IIF(r.IdImporto IS NOT NULL AND r.IdOffertaContratto IS NULL, 1, 0)),
				ImportoMin = MIN(r.IdImporto),
				ImportoMax = MAX(r.IdImporto),
				ContrattoMin = MIN(r.IdOffertaContratto),
				ContrattoMax = MAX(r.IdOffertaContratto),
				ClienteMin = MIN(r.IdClienteContratto),
				ClienteMax = MAX(r.IdClienteContratto)
			FROM dbo.ufnImportiMagazzino_get_ApplicazioneRighe_List(@Id, @IdAzienda, @DataDa, @DataA, @SoloFatturabili) r
			GROUP BY r.IdMovimento
		) g ON doc.Id = g.IdMovimento
		OUTER APPLY (
			SELECT TOP (1) c.Id
			FROM dbo.tblClientiFornitori c
			WHERE
				c.IdSede = doc.IdDestinatarioParent
				AND c.IdAziendaInterna = doc.IdAzienda
				AND c.Tipo = 'C'
				AND c.Lock = 0
			ORDER BY c.Id
		) cp
	WHERE
		ISNULL(@SoloFatturabili, 0) = 0
		OR (doc.Lock = 0 AND doc.IsFatturabile = 1)
);
GO
