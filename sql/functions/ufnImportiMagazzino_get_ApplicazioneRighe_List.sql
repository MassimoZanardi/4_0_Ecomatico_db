SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, magazzino: importo che la fatturazione applica a ogni riga dei DDT (regole O5M di
-- docs/regole/offerte-contratti.md). Il confronto è per riga: una riga per ogni riga articolo o EoW del DDT,
-- anche se nessun importo coincide (IdImporto NULL). Le righe descrittive del DDT non entrano.
--   Parametri: quelli di ufnImportiMagazzino_get_Documenti. @SoloFatturabili = 1: solo i DDT confermati e
--        fatturabili; il confronto non viene fatto per gli altri.
-- Importo: tra gli importi di magazzino attivi dell'azienda, il primo le cui variabili coincidono con la riga
-- (ufnImportiMagazzino_get_Coincidenti: articolo o materiale, destinatario; l'etichetta è una di quelle del
-- DDT), in ordine di priorità decrescente e, a parità, prima quello di un contratto e poi quello standard. La
-- validità del contratto è alla data del DDT.
-- Riga articolo: unità di misura dell'articolo. Riga EoW: chilogrammi.
-- IdImportoScartato: importo di un contratto che coinciderebbe ma non è valido alla data del DDT.
CREATE OR ALTER FUNCTION dbo.ufnImportiMagazzino_get_ApplicazioneRighe_List (
	@Id CHAR(16),
	@IdAzienda CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@SoloFatturabili BIT)
RETURNS TABLE
AS
RETURN
(
	WITH righe AS (
		SELECT
			IdMovimento = doc.Id,
			doc.IdDdt,
			doc.[Data],
			doc.IdAzienda,
			doc.IdDestinatario,
			doc.IdDestinatarioParent,
			IdRiga = r.Id,
			IsEoW = CAST(0 AS BIT),
			r.Pos,
			r.IdArticolo,
			IdMateriale = CAST(NULL AS CHAR(2)),
			Voce = CAST(a.Nome + ISNULL(' (' + a.Codice + ')', '') AS VARCHAR(200)),
			r.Quantita,
			IdUnitaMisura = a.IdUnitaMisura
		FROM
			dbo.ufnImportiMagazzino_get_Documenti(@Id, @IdAzienda, @DataDa, @DataA) doc
			INNER JOIN dbo.tblMagazziniMovimentiRighe r ON doc.Id = r.IdMovimento
			INNER JOIN dbo.tblMagazziniArticoli a ON r.IdArticolo = a.Id
		WHERE
			r.Lock <= 2
			AND (ISNULL(@SoloFatturabili, 0) = 0 OR (doc.Lock = 0 AND doc.IsFatturabile = 1))

		UNION ALL

		SELECT
			IdMovimento = doc.Id,
			doc.IdDdt,
			doc.[Data],
			doc.IdAzienda,
			doc.IdDestinatario,
			doc.IdDestinatarioParent,
			IdRiga = r.Id,
			IsEoW = CAST(1 AS BIT),
			r.Pos,
			IdArticolo = CAST(NULL AS CHAR(16)),
			r.IdMateriale,
			Voce = CAST(ma.Nome AS VARCHAR(200)),
			r.Quantita,
			IdUnitaMisura = CAST('KG' AS CHAR(2))
		FROM
			dbo.ufnImportiMagazzino_get_Documenti(@Id, @IdAzienda, @DataDa, @DataA) doc
			INNER JOIN dbo.tblMagazziniMovimentiRigheEoW r ON doc.Id = r.IdMovimento
			LEFT JOIN dbo.tblRifiutiMateriali ma ON r.IdMateriale = ma.Id
		WHERE
			r.Lock <= 2
			AND (ISNULL(@SoloFatturabili, 0) = 0 OR (doc.Lock = 0 AND doc.IsFatturabile = 1))
	),
	scelta AS (
		-- Per ogni riga gli importi che coincidono: N = 1 è il primo candidato (classe V) in ordine di scelta, o
		-- una riga senza candidato; IdImportoScartato il primo degli scartati (classe S). Un importo che indica
		-- un'etichetta che il DDT non ha non coincide: passa alla classe X
		SELECT
			g.IdMovimento,
			g.IdRiga,
			g.IsEoW,
			g.Pos,
			g.IdArticolo,
			g.IdMateriale,
			g.Voce,
			g.Quantita,
			g.IdUnitaMisura,
			IdImporto = IIF(q.Classe = 'V', c.IdImporto, NULL),
			IdOffertaContratto = IIF(q.Classe = 'V', c.IdOffertaContratto, NULL),
			IdClienteContratto = IIF(q.Classe = 'V', c.IdClienteContratto, NULL),
			IdImportoScartato = FIRST_VALUE(IIF(q.Classe = 'S', c.IdImporto, NULL)) OVER (
				PARTITION BY g.IdRiga
				ORDER BY IIF(q.Classe = 'S', 0, 1), c.IdPriorita DESC, c.IdImporto
				ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
			N = ROW_NUMBER() OVER (
				PARTITION BY g.IdRiga
				ORDER BY IIF(q.Classe = 'V', 0, 1), c.IdPriorita DESC, c.Standard, c.IdImporto)
		FROM
			righe g
			OUTER APPLY dbo.ufnImportiMagazzino_get_Coincidenti(g.IdAzienda, g.[Data], g.IdDestinatarioParent, g.IdDestinatario, g.IdArticolo, g.IdMateriale) c
			-- Al massimo una riga: (Id, IdEtichetta) è la chiave primaria
			LEFT JOIN dbo.tblMagazziniDdtEtichette e ON e.Id = g.IdDdt
													 AND e.IdEtichetta = c.IdEtichetta
			CROSS APPLY (SELECT Classe = IIF(c.IdEtichetta IS NOT NULL AND e.Id IS NULL, 'X', c.Classe)) q
	)
	SELECT
		t.IdMovimento,
		t.IdRiga,
		t.IsEoW,
		t.Pos,
		t.IdArticolo,
		t.IdMateriale,
		t.Voce,
		t.Quantita,
		t.IdUnitaMisura,
		t.IdImporto,
		t.IdOffertaContratto,
		t.IdClienteContratto,
		t.IdImportoScartato
	FROM scelta t
	WHERE t.N = 1
);
GO
