SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, magazzino: righe di fattura che l'importo applicato al DDT del movimento @Id genera.
-- Funzione in linea: si può usare con CROSS APPLY su più DDT. Nessuna riga se il DDT non ha un importo.
--
-- Righe a quantità (tipo MA, con l'articolo o il materiale): una per ogni riga del DDT con quell'articolo o quel
-- materiale, nell'ordine delle righe del DDT, con la quantità e l'unità di misura della riga (riga articolo:
-- unità dell'articolo; riga EoW: chilogrammi). Una riga a quantità il cui articolo non è nel DDT non entra.
-- Righe per movimento (tipo MM) e righe di sola descrizione (importo NULL): una volta per DDT, dopo le righe a
-- quantità, nell'ordine delle righe dell'importo; quantità 1 (unità NR) se hanno un importo.
-- Minimo fatturabile (al massimo una riga per importo): è il minimo da fatturare per il DDT. Si confronta con la
-- somma degli imponibili delle altre righe (se la riga del minimo è di tipo MM, di tutte; altrimenti di quelle a
-- quantità): se il minimo è maggiore la riga entra con quantità 1 e importo pari alla differenza.
-- Testo: i segnaposto #1 articolo o materiale della riga del DDT (vuoto sulle righe "una volta per DDT"),
-- #2 numero del DDT, #3 data del DDT, #4 destinatario, #5 destinazione (se non indicata, il destinatario).
-- Aliquota IVA: quella della riga dell'importo, altrimenti quella della scheda del cliente @IdClienteFornitore.
-- Ordine: PosDdt (0 per le righe "una volta per DDT", che vanno in coda con Gruppo = 1), poi Pos.
CREATE OR ALTER FUNCTION dbo.ufnImportiMagazzino_get_RigheFattura (
	@Id CHAR(16),
	@IdClienteFornitore CHAR(16))
RETURNS TABLE
AS
RETURN
(
	WITH testata AS (
		SELECT
			doc.Id,
			IdAliquotaIvaCliente = c.IdAliquotaIva,
			DdtNumero = CAST(CAST(doc.Numero AS VARCHAR(10)) + ISNULL('/' + doc.Sezionale, '') AS VARCHAR(20)),
			DdtData = CONVERT(VARCHAR(10), doc.[Data], 103),
			Destinatario = sd.NomeCompleto + ISNULL(' ' + sd.IndirizzoCompleto, ''),
			Destinazione = sz.NomeCompleto + ISNULL(' ' + sz.IndirizzoCompleto, '')
		FROM
			dbo.ufnImportiMagazzino_get_Documenti(@Id, NULL, NULL, NULL) doc
			LEFT JOIN dbo.tblClientiFornitori c ON c.Id = @IdClienteFornitore
			LEFT JOIN dbo.tblSedi sd ON doc.IdDestinatario = sd.Id
			LEFT JOIN dbo.tblSedi sz ON doc.IdDestinazioneEffettiva = sz.Id
	),
	ddt AS (
		SELECT
			x.IdRiga,
			PosDdt = ISNULL(x.Pos, 0),
			x.IdImporto,
			x.IdRigaImporto,
			x.Voce,
			x.Quantita,
			x.IdUnitaMisura
		FROM dbo.ufnImportiMagazzino_get_ApplicazioneRighe_List(@Id, NULL, NULL, NULL, 0) x
		WHERE x.IdImporto IS NOT NULL
	),
	righe AS (
		-- Righe a quantità: una per ogni riga del DDT che ha il suo prezzo nell'importo
		SELECT
			Gruppo = 0,
			IdRigaDdt = a.IdRiga,
			a.PosDdt,
			g.Id,
			g.Pos,
			g.IdTipo,
			MinimoFatturabile = CAST(0 AS BIT),
			Prezzo = g.Importo,
			Quantita = CAST(a.Quantita AS DECIMAL(18, 4)),
			IdUnitaMisura = CAST(a.IdUnitaMisura AS CHAR(2)),
			a.Voce
		FROM
			ddt a
			INNER JOIN dbo.tblImportiRighe g ON a.IdRigaImporto = g.Id

		UNION ALL

		-- Righe per movimento, di sola descrizione e minimo fatturabile: una volta per DDT
		SELECT
			Gruppo = 1,
			IdRigaDdt = CAST(NULL AS CHAR(16)),
			PosDdt = 0,
			g.Id,
			g.Pos,
			g.IdTipo,
			MinimoFatturabile = CAST(ISNULL(g.MinimoFatturabile, 0) AS BIT),
			Prezzo = g.Importo,
			Quantita = CAST(IIF(g.Importo IS NULL, NULL, 1) AS DECIMAL(18, 4)),
			IdUnitaMisura = CAST(IIF(g.Importo IS NULL, NULL, 'NR') AS CHAR(2)),
			Voce = CAST(NULL AS VARCHAR(200))
		FROM
			(SELECT DISTINCT IdImporto FROM ddt) a
			INNER JOIN dbo.tblImportiRighe g ON a.IdImporto = g.IdImporto
		WHERE
			g.Importo IS NULL
			OR g.IdTipo = 'MM'
			OR ISNULL(g.MinimoFatturabile, 0) = 1
	),
	minimo AS (
		-- Somma degli imponibili delle righe con cui si confronta il minimo fatturabile
		SELECT
			Altre = ISNULL((
				SELECT SUM(ROUND(x.Prezzo * x.Quantita, 2))
				FROM righe x
				WHERE
					x.MinimoFatturabile = 0
					AND x.Quantita IS NOT NULL
					AND (m.IdTipo = 'MM' OR x.IdTipo <> 'MM')
			), 0)
		FROM righe m
		WHERE
			m.MinimoFatturabile = 1
			AND m.Prezzo IS NOT NULL
	)
	SELECT
		t.Gruppo,
		t.IdRigaDdt,
		t.PosDdt,
		t.Id,
		t.Pos,
		t.IdTipo,
		t.MinimoFatturabile,
		SolaDescrizione = CAST(IIF(t.Prezzo IS NULL, 1, 0) AS BIT),
		Descrizione = CAST(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(d.Descrizione, ''),
			'#1', ISNULL(t.Voce, '')),
			'#2', ISNULL(h.DdtNumero, '')),
			'#3', ISNULL(h.DdtData, '__/__/____')),
			'#4', ISNULL(h.Destinatario, '')),
			'#5', ISNULL(h.Destinazione, '')) AS VARCHAR(1000)),
		t.Quantita,
		t.IdUnitaMisura,
		Importo = CAST(IIF(t.MinimoFatturabile = 1, t.Prezzo - n.Altre, t.Prezzo) AS DECIMAL(18, 4)),
		Imponibile = CAST(ROUND(IIF(t.MinimoFatturabile = 1, t.Prezzo - n.Altre, t.Prezzo * t.Quantita), 2) AS DECIMAL(18, 2)),
		IdAliquotaIva = ISNULL(d.IdAliquotaIva, h.IdAliquotaIvaCliente),
		d.IdConto
	FROM
		righe t
		CROSS JOIN testata h
		LEFT JOIN dbo.tblImportiRigheDettagli d ON t.Id = d.Id
		LEFT JOIN minimo n ON t.MinimoFatturabile = 1
	WHERE
		-- Sola descrizione: sempre
		t.Prezzo IS NULL
		-- Riga normale: sempre (ha una quantità)
		OR t.MinimoFatturabile = 0
		-- Minimo fatturabile: solo per la differenza non raggiunta dalle altre righe
		OR (t.MinimoFatturabile = 1 AND t.Prezzo > n.Altre)
);
GO
