SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, magazzino: per ogni DDT, l'importo applicato (uno solo: l'importo di magazzino è un
-- listino), il cliente a cui fatturarlo e il riepilogo delle sue righe
-- (ufnImportiMagazzino_get_ApplicazioneRighe_List). Una riga per movimento con un DDT; è l'analogo di
-- ufnImportiRifiuti_get_Applicazione_List.
--   Parametri: quelli di ufnImportiMagazzino_get_ApplicazioneRighe_List.
-- Righe: righe articolo ed EoW del DDT. RigheSenzaImporto: quelle il cui articolo o materiale non ha una riga
-- nell'importo applicato (tutte, se nessun importo coincide): se ce n'è anche una sola il DDT intero non viene
-- fatturato. Un DDT senza righe non ha importo.
-- Cliente (ClienteOrigine): D quello indicato sul DDT (tblFattureDocumenti), altrimenti C quello del contratto
-- dell'importo applicato, altrimenti P la scheda cliente attiva del soggetto destinatario (per un importo
-- standard). NULL se nessuno dei tre.
-- IdImportoScartato: importo di un contratto che coinciderebbe con il DDT ma non è valido alla sua data.
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
		g.IdImporto,
		g.IdOffertaContratto,
		g.IdImportoScartato,
		IdClienteFornitore = COALESCE(d.IdClienteFornitore, g.IdClienteContratto, cp.Id),
		ClienteOrigine = CAST(CASE
			WHEN d.IdClienteFornitore IS NOT NULL THEN 'D'
			WHEN g.IdClienteContratto IS NOT NULL THEN 'C'
			WHEN cp.Id IS NOT NULL THEN 'P'
		END AS CHAR(1))
	FROM
		dbo.ufnImportiMagazzino_get_Documenti(@Id, @IdAzienda, @DataDa, @DataA) doc
		LEFT JOIN dbo.tblFattureDocumenti d ON doc.Id = d.Id
		LEFT JOIN dbo.tblFatture f ON d.IdFattura = f.Id
								  AND f.Lock IN (0, 2)
		LEFT JOIN (
			-- Importo, contratto e cliente sono gli stessi su tutte le righe del DDT
			SELECT
				r.IdMovimento,
				Righe = COUNT(*),
				RigheSenzaImporto = SUM(IIF(r.IdRigaImporto IS NULL, 1, 0)),
				IdImporto = MIN(r.IdImporto),
				IdOffertaContratto = MIN(r.IdOffertaContratto),
				IdClienteContratto = MIN(r.IdClienteContratto),
				IdImportoScartato = MIN(r.IdImportoScartato)
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
