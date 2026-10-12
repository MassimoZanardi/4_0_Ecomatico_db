SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: importo e cliente che la fatturazione applica a una registrazione dei rifiuti
-- (regole O5 di docs/regole/offerte-contratti.md). Una riga per la registrazione @Id, anche se nessun importo
-- coincide (IdImporto NULL). Funzione in linea: si può usare con CROSS APPLY su più registrazioni.
--
-- Importo: tra gli importi rifiuti attivi dell'azienda del registro, il primo le cui variabili indicate
-- coincidono tutte con la registrazione (una variabile NULL vale "qualsiasi"), in ordine di priorità
-- decrescente e, a parità di priorità, prima quello di un contratto e poi quello standard.
--   - Importo standard (non associato a un contratto o a un'offerta): sempre candidato.
--   - Importo di un contratto: candidato solo se il contratto è attivo, di un cliente, e la data della
--     registrazione è compresa tra inizio e fine.
--   - Il cliente indicato sulla registrazione NON entra nella scelta dell'importo: cambia solo l'intestatario
--     della fattura. La registrazione può essere fatturata, per esempio, all'intermediario con l'importo e le
--     condizioni del contratto di un altro cliente.
--   - Importo di un'offerta: mai candidato.
-- Valori della registrazione: quelli OPERATIVI (viewRifiutiRegistrazioniEffettive: EER, unità di misura e
-- quantità dopo le rettifiche); soggetti ed etichette sono quelli della registrazione.
--
-- Cliente (ClienteOrigine): D quello indicato sulla registrazione (tblFattureDocumenti), altrimenti C quello del
-- contratto dell'importo applicato, altrimenti P la scheda cliente attiva del soggetto produttore (per un
-- importo standard). NULL se nessuno dei tre.
-- IdImportoScartato: importo di un contratto che coinciderebbe con la registrazione ma il cui contratto non è
-- valido alla data della registrazione (serve all'avviso "contratto scaduto").
-- IdFattura: solo se la fattura non è cancellata (cancellata la fattura, la registrazione torna fatturabile).
-- IsPreFattura, IdClientePreFattura: il documento è in una pre-fattura (TD00), intestata a quel cliente; la
-- generazione può riprenderla e convertirla in fattura (uspFatture_ins_Genera, @IncludiPreFatture).
CREATE OR ALTER FUNCTION dbo.ufnImportiRifiuti_get_Applicazione (
	@Id CHAR(16))
RETURNS TABLE
AS
RETURN
(
	WITH doc AS (
		SELECT
			r.Id,
			r.[Data],
			r.Numero,
			r.Lock,
			IdSedeRegistro = g.IdSede,
			IdAzienda = sr.IdAziendaInterna,
			m.IdOperazione,
			IsFatturabile = CAST(ISNULL(o.IsFatturabile, 0) AS BIT),
			v.IdEer,
			v.IdUnitaMisura,
			v.Quantita,
			v.IsRettifica,
			v.IsAnnullata,
			IdProduttore = m.IdSedeProduttoreDetentore,
			IdProduttoreParent = ISNULL(sp.IdParent, sp.Id),
			IdTrasportatore = m.IdSedeTrasportatore1,
			IdDestinatario = m.IdSedeDestinatario,
			IdIntermediario = m.IdSedeIntermediario1,
			m.FormularioNumero,
			IdClienteIndicato = d.IdClienteFornitore,
			NonFatturabile = CAST(ISNULL(d.NonFatturabile, 0) AS BIT),
			IdFattura = f.Id,
			IsPreFattura = CAST(IIF(f.IdTipo = 'TD00', 1, 0) AS BIT),
			IdClientePreFattura = IIF(f.IdTipo = 'TD00', f.IdClienteFornitore, NULL)
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi sr ON g.IdSede = sr.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN dbo.tblSedi sp ON m.IdSedeProduttoreDetentore = sp.Id
			LEFT JOIN dbo.tblFattureDocumenti d ON r.Id = d.Id
			LEFT JOIN dbo.tblFatture f ON d.IdFattura = f.Id
									  AND f.Lock IN (0, 2)
		WHERE r.Id = @Id
	)
	SELECT
		doc.Id,
		doc.[Data],
		doc.Numero,
		doc.Lock,
		doc.IdSedeRegistro,
		doc.IdAzienda,
		doc.IdOperazione,
		doc.IsFatturabile,
		doc.IdEer,
		doc.IdUnitaMisura,
		doc.Quantita,
		doc.IsRettifica,
		doc.IsAnnullata,
		doc.IdProduttore,
		doc.IdProduttoreParent,
		doc.IdTrasportatore,
		doc.IdDestinatario,
		doc.IdIntermediario,
		doc.FormularioNumero,
		doc.IdClienteIndicato,
		doc.NonFatturabile,
		doc.IdFattura,
		doc.IsPreFattura,
		doc.IdClientePreFattura,
		a.IdImporto,
		a.IdOffertaContratto,
		IdClienteFornitore = COALESCE(doc.IdClienteIndicato, a.IdClienteContratto, cp.Id),
		ClienteOrigine = CAST(CASE
			WHEN doc.IdClienteIndicato IS NOT NULL THEN 'D'
			WHEN a.IdClienteContratto IS NOT NULL THEN 'C'
			WHEN cp.Id IS NOT NULL THEN 'P'
		END AS CHAR(1)),
		IdImportoScartato = s.IdImporto
	FROM
		doc
		OUTER APPLY (
			SELECT TOP (1)
				IdImporto = i.Id,
				IdOffertaContratto = oc.Id,
				IdClienteContratto = oc.IdClienteFornitore
			FROM
				dbo.tblImporti i
				INNER JOIN dbo.tblImportiRifiuti ir ON i.Id = ir.Id
				LEFT JOIN dbo.tblOfferteContrattiImporti ci ON i.Id = ci.IdImporto
				LEFT JOIN dbo.tblOfferteContratti oc ON ci.IdOffertaContratto = oc.Id
			WHERE
				i.IdSede = doc.IdAzienda
				AND i.Lock = 0
				AND
					(
					ci.IdImporto IS NULL
					OR
						(
						oc.Lock = 0
						AND oc.Tipo = 'C'
						AND oc.ClienteFornitoreTipo = 'C'
						AND doc.[Data] BETWEEN oc.DataInizio AND oc.DataFine
						)
					)
				AND (ir.IdEer IS NULL OR ir.IdEer = doc.IdEer)
				AND (ir.IdProduttoreParent IS NULL OR ir.IdProduttoreParent = doc.IdProduttoreParent)
				AND (ir.IdProduttore IS NULL OR ir.IdProduttore = doc.IdProduttore)
				AND (ir.IdTrasportatore IS NULL OR ir.IdTrasportatore = doc.IdTrasportatore)
				AND (ir.IdDestinatario IS NULL OR ir.IdDestinatario = doc.IdDestinatario)
				AND (ir.IdIntermediario IS NULL OR ir.IdIntermediario = doc.IdIntermediario)
				AND
					(
					ir.IdEtichetta IS NULL
					OR EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioniEtichette e WHERE e.Id = doc.Id AND e.IdEtichetta = ir.IdEtichetta)
					)
			ORDER BY
				i.IdPriorita DESC,
				IIF(ci.IdImporto IS NULL, 1, 0),
				i.Id
		) a
		OUTER APPLY (
			SELECT TOP (1) c.Id
			FROM dbo.tblClientiFornitori c
			WHERE
				c.IdSede = doc.IdProduttoreParent
				AND c.IdAziendaInterna = doc.IdAzienda
				AND c.Tipo = 'C'
				AND c.Lock = 0
			ORDER BY c.Id
		) cp
		OUTER APPLY (
			SELECT TOP (1) IdImporto = i.Id
			FROM
				dbo.tblImporti i
				INNER JOIN dbo.tblImportiRifiuti ir ON i.Id = ir.Id
				INNER JOIN dbo.tblOfferteContrattiImporti ci ON i.Id = ci.IdImporto
				INNER JOIN dbo.tblOfferteContratti oc ON ci.IdOffertaContratto = oc.Id
			WHERE
				i.IdSede = doc.IdAzienda
				AND i.Lock = 0
				AND oc.Lock = 0
				AND oc.Tipo = 'C'
				AND oc.ClienteFornitoreTipo = 'C'
				AND NOT (doc.[Data] BETWEEN oc.DataInizio AND oc.DataFine)
				AND (ir.IdEer IS NULL OR ir.IdEer = doc.IdEer)
				AND (ir.IdProduttoreParent IS NULL OR ir.IdProduttoreParent = doc.IdProduttoreParent)
				AND (ir.IdProduttore IS NULL OR ir.IdProduttore = doc.IdProduttore)
				AND (ir.IdTrasportatore IS NULL OR ir.IdTrasportatore = doc.IdTrasportatore)
				AND (ir.IdDestinatario IS NULL OR ir.IdDestinatario = doc.IdDestinatario)
				AND (ir.IdIntermediario IS NULL OR ir.IdIntermediario = doc.IdIntermediario)
				AND
					(
					ir.IdEtichetta IS NULL
					OR EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioniEtichette e WHERE e.Id = doc.Id AND e.IdEtichetta = ir.IdEtichetta)
					)
			ORDER BY
				i.IdPriorita DESC,
				i.Id
		) s
);
GO
