SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: importo e cliente che la fatturazione applica alle registrazioni dei rifiuti
-- (regole O5 di docs/regole/offerte-contratti.md). Una riga per registrazione, anche se nessun importo
-- coincide (IdImporto NULL).
--   @Id: una sola registrazione; altrimenti le registrazioni dei registri dell'azienda @IdAzienda con la data
--        tra @DataDa e @DataA.
--   @SoloFatturabili = 1: solo le registrazioni confermate (Lock = 0) di un'operazione fatturabile, non
--        rettifiche; il confronto con gli importi non viene fatto per le altre.
-- Il confronto è a insiemi: gli importi dell'azienda si leggono una volta e si incrociano con tutte le
-- registrazioni richieste (ufnImportiRifiuti_get_Coincidenti), invece di una ricerca per registrazione.
-- Chi la chiama con parametri variabili usa OPTION (RECOMPILE); per una sola registrazione c'è
-- ufnImportiRifiuti_get_Applicazione.
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
CREATE OR ALTER FUNCTION dbo.ufnImportiRifiuti_get_Applicazione_List (
	@Id CHAR(16),
	@IdAzienda CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@SoloFatturabili BIT)
RETURNS TABLE
AS
RETURN
(
	WITH ids AS (
		-- Due rami distinti, ciascuno con il suo accesso: la registrazione @Id per chiave, oppure quelle
		-- dell'azienda nel periodo (un solo WHERE con OR farebbe leggere tutte le registrazioni anche per una sola)
		SELECT r.Id
		FROM dbo.tblRifiutiRegistrazioni r
		WHERE r.Id = @Id

		UNION ALL

		SELECT r.Id
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi sr ON g.IdSede = sr.Id
		WHERE
			@Id IS NULL
			AND sr.IdAziendaInterna = @IdAzienda
			AND r.[Data] >= @DataDa
			AND r.[Data] <= @DataA
	),
	doc AS (
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
			ids k
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON k.Id = r.Id
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi sr ON g.IdSede = sr.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN dbo.tblSedi sp ON m.IdSedeProduttoreDetentore = sp.Id
			LEFT JOIN dbo.tblFattureDocumenti d ON r.Id = d.Id
			LEFT JOIN dbo.tblFatture f ON d.IdFattura = f.Id
									  AND f.Lock IN (0, 2)
		WHERE
			ISNULL(@SoloFatturabili, 0) = 0
			OR
			(
				r.Lock = 0
				AND o.IsFatturabile = 1
				AND v.IsRettifica = 0
			)
	),
	scelta AS (
		-- Per ogni registrazione gli importi che coincidono: N = 1 è il primo candidato (classe V) in ordine di
		-- scelta, o una riga senza candidato; IdImportoScartato il primo degli scartati (classe S). Un importo che
		-- indica un'etichetta che la registrazione non ha non coincide: passa alla classe X
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
			doc
			OUTER APPLY dbo.ufnImportiRifiuti_get_Coincidenti(doc.IdAzienda, doc.[Data], doc.IdEer, doc.IdProduttoreParent, doc.IdProduttore,
				doc.IdTrasportatore, doc.IdDestinatario, doc.IdIntermediario) c
			-- Al massimo una riga: (Id, IdEtichetta) è la chiave primaria
			LEFT JOIN dbo.tblRifiutiRegistrazioniEtichette e ON e.Id = doc.Id
															 AND e.IdEtichetta = c.IdEtichetta
			CROSS APPLY (SELECT Classe = IIF(c.IdEtichetta IS NOT NULL AND e.Id IS NULL, 'X', c.Classe)) q
	)
	SELECT
		t.Id,
		t.[Data],
		t.Numero,
		t.Lock,
		t.IdSedeRegistro,
		t.IdAzienda,
		t.IdOperazione,
		t.IsFatturabile,
		t.IdEer,
		t.IdUnitaMisura,
		t.Quantita,
		t.IsRettifica,
		t.IsAnnullata,
		t.IdProduttore,
		t.IdProduttoreParent,
		t.IdTrasportatore,
		t.IdDestinatario,
		t.IdIntermediario,
		t.FormularioNumero,
		t.IdClienteIndicato,
		t.NonFatturabile,
		t.IdFattura,
		t.IsPreFattura,
		t.IdClientePreFattura,
		t.IdImporto,
		t.IdOffertaContratto,
		IdClienteFornitore = COALESCE(t.IdClienteIndicato, t.IdClienteContratto, cp.Id),
		ClienteOrigine = CAST(CASE
			WHEN t.IdClienteIndicato IS NOT NULL THEN 'D'
			WHEN t.IdClienteContratto IS NOT NULL THEN 'C'
			WHEN cp.Id IS NOT NULL THEN 'P'
		END AS CHAR(1)),
		t.IdImportoScartato
	FROM
		scelta t
		OUTER APPLY (
			SELECT TOP (1) c.Id
			FROM dbo.tblClientiFornitori c
			WHERE
				c.IdSede = t.IdProduttoreParent
				AND c.IdAziendaInterna = t.IdAzienda
				AND c.Tipo = 'C'
				AND c.Lock = 0
			ORDER BY c.Id
		) cp
	WHERE t.N = 1
);
GO
