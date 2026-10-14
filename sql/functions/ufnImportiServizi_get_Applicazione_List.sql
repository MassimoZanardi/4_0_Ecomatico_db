SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, servizi: per ogni servizio, l'importo applicato (uno solo: l'importo dei servizi è un
-- listino), il cliente a cui fatturarlo e il riepilogo delle sue risorse. Una riga per servizio; è l'analogo di
-- ufnImportiMagazzino_get_Applicazione_List.
--   Parametri: quelli di ufnImportiServizi_get_Scelta_List.
-- Risorse: persone e oggetti del servizio con quantità maggiore di 0. RisorseSenzaImporto: quelle che non hanno
-- una riga nell'importo applicato (tutte, se nessun importo coincide): se ce n'è anche una sola il servizio non
-- viene fatturato. Un servizio senza risorse si fattura con le sole righe "una volta per servizio".
-- Cliente (ClienteOrigine): D quello indicato sul servizio (tblFattureDocumenti), altrimenti C quello del
-- contratto dell'importo applicato, altrimenti P la scheda cliente attiva del soggetto richiedente (per un importo
-- standard). NULL se nessuno dei tre.
-- IdImportoScartato: importo di un contratto che coinciderebbe con il servizio ma non è valido alla sua data.
-- IdFattura: solo se la fattura non è cancellata. IsPreFattura, IdClientePreFattura: come per i rifiuti.
CREATE OR ALTER FUNCTION dbo.ufnImportiServizi_get_Applicazione_List (
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
		doc.IdEvento,
		doc.[Data],
		doc.Lock,
		doc.IdAzienda,
		doc.IdSedeInterna,
		doc.IsFatturabile,
		doc.IsEseguito,
		doc.IdTipo,
		doc.IdRichiedente,
		doc.IdRichiedenteParent,
		IdClienteIndicato = d.IdClienteFornitore,
		NonFatturabile = CAST(ISNULL(d.NonFatturabile, 0) AS BIT),
		IdFattura = f.Id,
		IsPreFattura = CAST(IIF(f.IdTipo = 'TD00', 1, 0) AS BIT),
		IdClientePreFattura = IIF(f.IdTipo = 'TD00', f.IdClienteFornitore, NULL),
		Risorse = ISNULL(g.Risorse, 0),
		RisorseSenzaImporto = ISNULL(g.RisorseSenzaImporto, 0),
		s.IdImporto,
		s.IdOffertaContratto,
		s.IdImportoScartato,
		IdClienteFornitore = COALESCE(d.IdClienteFornitore, s.IdClienteContratto, cp.Id),
		ClienteOrigine = CAST(CASE
			WHEN d.IdClienteFornitore IS NOT NULL THEN 'D'
			WHEN s.IdClienteContratto IS NOT NULL THEN 'C'
			WHEN cp.Id IS NOT NULL THEN 'P'
		END AS CHAR(1))
	FROM
		dbo.ufnImportiServizi_get_Documenti(@Id, @IdAzienda, @DataDa, @DataA) doc
		INNER JOIN dbo.ufnImportiServizi_get_Scelta_List(@Id, @IdAzienda, @DataDa, @DataA, @SoloFatturabili) s ON doc.Id = s.Id
		LEFT JOIN dbo.tblFattureDocumenti d ON doc.Id = d.Id
		LEFT JOIN dbo.tblFatture f ON d.IdFattura = f.Id
								  AND f.Lock IN (0, 2)
		OUTER APPLY (
			-- Risorse con quantità e quante di loro non hanno il prezzo nell'importo applicato
			SELECT
				Risorse = COUNT(*),
				RisorseSenzaImporto = SUM(IIF(p.Id IS NULL, 1, 0))
			FROM
				dbo.tblServiziOsepe so
				OUTER APPLY (
					SELECT TOP (1) x.Id
					FROM
						dbo.tblImportiRighe x
						INNER JOIN dbo.tblImportiRigheServizi xs ON x.Id = xs.Id
					WHERE
						x.IdImporto = s.IdImporto
						AND x.IdTipo = 'SU'
						AND x.Importo IS NOT NULL
						AND ISNULL(x.MinimoFatturabile, 0) = 0
						AND xs.IdOsepe = so.IdOsepe
				) p
			WHERE
				so.Id = doc.Id
				AND so.Quantita > 0
		) g
		OUTER APPLY (
			SELECT TOP (1) c.Id
			FROM dbo.tblClientiFornitori c
			WHERE
				c.IdSede = doc.IdRichiedenteParent
				AND c.IdAziendaInterna = doc.IdAzienda
				AND c.Tipo = 'C'
				AND c.Lock = 0
			ORDER BY c.Id
		) cp
);
GO
