SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, magazzino: per ogni riga dei DDT, l'importo applicato al DDT e la riga dell'importo che
-- dà il prezzo dell'articolo o del materiale (regole O5M di docs/regole/offerte-contratti.md). Una riga per
-- ogni riga articolo o EoW del DDT; le righe descrittive del DDT non entrano.
--   Parametri: quelli di ufnImportiMagazzino_get_Documenti. @SoloFatturabili = 1: solo i DDT confermati e
--        fatturabili; il confronto non viene fatto per gli altri.
-- Importo: UNO SOLO PER DDT, lo stesso su tutte le sue righe: tra gli importi di magazzino attivi dell'azienda, il
-- primo le cui variabili coincidono con il DDT (ufnImportiMagazzino_get_Coincidenti: sede di partenza,
-- destinatario, destinazione; l'etichetta è una di quelle del DDT), in ordine di priorità decrescente e, a parità,
-- prima quello di un contratto e poi quello standard. La validità del contratto è alla data del DDT.
-- IdRigaImporto: la riga a quantità (tipo MA) dell'importo che indica l'articolo o il materiale della riga del DDT.
-- NULL se il DDT non ha un importo, o se l'importo non ha una riga per quell'articolo: in quel caso il DDT non è
-- fatturabile. Non si cerca il prezzo in un altro importo.
-- Riga articolo: unità di misura dell'articolo. Riga EoW: chilogrammi.
-- IdImportoScartato: importo di un contratto che coinciderebbe con il DDT ma non è valido alla sua data.
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
	WITH scelta AS (
		-- Per ogni DDT gli importi che coincidono: N = 1 è il primo candidato (classe V) in ordine di scelta, o
		-- una riga senza candidato; IdImportoScartato il primo degli scartati (classe S). Un importo che indica
		-- un'etichetta che il DDT non ha non coincide: passa alla classe X
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
			dbo.ufnImportiMagazzino_get_Documenti(@Id, @IdAzienda, @DataDa, @DataA) doc
			OUTER APPLY dbo.ufnImportiMagazzino_get_Coincidenti(doc.IdAzienda, doc.[Data], doc.IdSedeDdt, doc.IdDestinatarioParent, doc.IdDestinazioneEffettiva) c
			-- Al massimo una riga: (Id, IdEtichetta) è la chiave primaria
			LEFT JOIN dbo.tblMagazziniDdtEtichette e ON e.Id = doc.IdDdt
													 AND e.IdEtichetta = c.IdEtichetta
			CROSS APPLY (SELECT Classe = IIF(c.IdEtichetta IS NOT NULL AND e.Id IS NULL, 'X', c.Classe)) q
		WHERE
			ISNULL(@SoloFatturabili, 0) = 0
			OR (doc.Lock = 0 AND doc.IsFatturabile = 1)
	),
	righe AS (
		SELECT
			r.IdMovimento,
			IdRiga = r.Id,
			IsEoW = CAST(0 AS BIT),
			r.Pos,
			r.IdArticolo,
			IdMateriale = CAST(NULL AS CHAR(2)),
			Voce = CAST(a.Nome + ISNULL(' (' + a.Codice + ')', '') AS VARCHAR(200)),
			r.Quantita,
			IdUnitaMisura = a.IdUnitaMisura
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblMagazziniArticoli a ON r.IdArticolo = a.Id
		WHERE r.Lock <= 2

		UNION ALL

		SELECT
			r.IdMovimento,
			IdRiga = r.Id,
			IsEoW = CAST(1 AS BIT),
			r.Pos,
			IdArticolo = CAST(NULL AS CHAR(16)),
			r.IdMateriale,
			Voce = CAST(ma.Nome AS VARCHAR(200)),
			r.Quantita,
			IdUnitaMisura = CAST('KG' AS CHAR(2))
		FROM
			dbo.tblMagazziniMovimentiRigheEoW r
			LEFT JOIN dbo.tblRifiutiMateriali ma ON r.IdMateriale = ma.Id
		WHERE r.Lock <= 2
	)
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
		s.IdImporto,
		s.IdOffertaContratto,
		s.IdClienteContratto,
		s.IdImportoScartato,
		IdRigaImporto = p.Id
	FROM
		scelta s
		INNER JOIN righe g ON s.Id = g.IdMovimento
		OUTER APPLY (
			-- Riga a quantità dell'importo per l'articolo o il materiale di questa riga del DDT (una sola: lo
			-- garantisce uspImportiRighe_upd)
			SELECT TOP (1) x.Id
			FROM
				dbo.tblImportiRighe x
				INNER JOIN dbo.tblImportiRigheMagazzino xm ON x.Id = xm.Id
			WHERE
				x.IdImporto = s.IdImporto
				AND x.IdTipo = 'MA'
				AND x.Importo IS NOT NULL
				AND ISNULL(x.MinimoFatturabile, 0) = 0
				AND (xm.IdArticolo = g.IdArticolo OR xm.IdMateriale = g.IdMateriale)
			ORDER BY ISNULL(x.Pos, 0), x.Id
		) p
	WHERE s.N = 1
);
GO
