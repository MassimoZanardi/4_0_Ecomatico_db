SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, servizi: per ogni servizio l'importo applicato (regole O5S di docs/regole/offerte-contratti.md).
-- Una riga per servizio, anche senza importo.
--   Parametri: quelli di ufnImportiServizi_get_Documenti. @SoloFatturabili = 1: solo i servizi confermati,
--        eseguiti e non serie ricorrenti; il confronto non viene fatto per gli altri.
-- Importo: UNO SOLO PER SERVIZIO: tra gli importi dei servizi attivi dell'azienda, il primo le cui variabili
-- coincidono con il servizio (ufnImportiServizi_get_Coincidenti: tipo, richiedente, sede interna; l'etichetta è
-- una di quelle del servizio), in ordine di priorità decrescente e, a parità, prima quello di un contratto e poi
-- quello standard. La validità del contratto è alla data del servizio. Le risorse non entrano nella scelta.
-- IdImportoScartato: importo di un contratto che coinciderebbe con il servizio ma non è valido alla sua data.
CREATE OR ALTER FUNCTION dbo.ufnImportiServizi_get_Scelta_List (
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
		t.Id,
		t.IdImporto,
		t.IdOffertaContratto,
		t.IdClienteContratto,
		t.IdImportoScartato
	FROM
		(
			-- Per ogni servizio gli importi che coincidono: N = 1 è il primo candidato (classe V) in ordine di
			-- scelta, o una riga senza candidato; IdImportoScartato il primo degli scartati (classe S). Un importo che
			-- indica un'etichetta che il servizio non ha non coincide: passa alla classe X
			SELECT
				doc.Id,
				IdImporto = IIF(q.Classe = 'V', c.IdImporto, NULL),
				IdOffertaContratto = IIF(q.Classe = 'V', c.IdOffertaContratto, NULL),
				IdClienteContratto = IIF(q.Classe = 'V', c.IdClienteContratto, NULL),
				IdImportoScartato = FIRST_VALUE(IIF(q.Classe = 'S', c.IdImporto, NULL)) OVER (
					PARTITION BY doc.Id
					ORDER BY IIF(q.Classe = 'S', 0, 1), c.IdPriorita DESC, c.IdImporto
					ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
				N = ROW_NUMBER() OVER (
					PARTITION BY doc.Id
					ORDER BY IIF(q.Classe = 'V', 0, 1), c.IdPriorita DESC, c.Standard, c.IdImporto)
			FROM
				dbo.ufnImportiServizi_get_Documenti(@Id, @IdAzienda, @DataDa, @DataA) doc
				OUTER APPLY dbo.ufnImportiServizi_get_Coincidenti(doc.IdAzienda, doc.[Data], doc.IdTipo, doc.IdRichiedenteParent, doc.IdRichiedente, doc.IdSedeInterna) c
				-- Al massimo una riga: (Id, IdEtichetta) è la chiave primaria
				LEFT JOIN dbo.tblEventiEtichette e ON e.Id = doc.IdEvento
												  AND e.IdEtichetta = c.IdEtichetta
				CROSS APPLY (SELECT Classe = IIF(c.IdEtichetta IS NOT NULL AND e.Id IS NULL, 'X', c.Classe)) q
			WHERE
				ISNULL(@SoloFatturabili, 0) = 0
				OR (doc.Lock = 0 AND doc.IsFatturabile = 1 AND doc.IsEseguito = 1)
		) t
	WHERE t.N = 1
);
GO
