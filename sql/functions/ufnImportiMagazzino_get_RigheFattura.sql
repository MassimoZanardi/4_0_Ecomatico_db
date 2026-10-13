SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, magazzino: righe di fattura che gli importi applicati alle righe del DDT del movimento
-- @Id generano, nell'ordine delle righe del DDT e, per ciascuna, delle righe dell'importo. Funzione in linea: si
-- può usare con CROSS APPLY su più DDT. Nessuna riga per le righe del DDT senza importo.
--
-- Riga dell'importo a quantità (tipo MA): una per ogni riga del DDT a cui l'importo è applicato, con la quantità
-- e l'unità di misura di quella riga (riga articolo: unità dell'articolo; riga EoW: chilogrammi).
-- Riga per movimento (tipo MM) e riga di sola descrizione (importo NULL): una sola volta per DDT e per importo,
-- sulla prima riga del DDT a cui quell'importo è applicato, con quantità 1 (unità NR) se ha un importo.
-- Minimo fatturabile (al massimo una riga per importo): è il minimo da fatturare per il DDT con quell'importo. Si
-- confronta con la somma degli imponibili delle altre sue righe (se la riga del minimo è di tipo MM, di tutte;
-- altrimenti di quelle a quantità): se il minimo è maggiore la riga entra, una volta, con quantità 1 e importo
-- pari alla differenza, altrimenti non entra.
-- Testo: i segnaposto #1 articolo o materiale della riga del DDT, #2 numero del DDT, #3 data del DDT,
-- #4 destinatario, #5 destinazione (se non indicata, il destinatario) vengono sostituiti.
-- Aliquota IVA: quella della riga dell'importo, altrimenti quella della scheda del cliente @IdClienteFornitore.
CREATE OR ALTER FUNCTION dbo.ufnImportiMagazzino_get_RigheFattura (
	@Id CHAR(16),
	@IdClienteFornitore CHAR(16))
RETURNS TABLE
AS
RETURN
(
	WITH a AS (
		SELECT
			x.IdRiga,
			PosDdt = ISNULL(x.Pos, 0),
			x.IdImporto,
			x.Voce,
			x.Quantita,
			x.IdUnitaMisura,
			-- Prima riga del DDT con questo importo: porta le righe "una volta per DDT"
			Prima = CAST(IIF(ROW_NUMBER() OVER (PARTITION BY x.IdImporto ORDER BY ISNULL(x.Pos, 0), x.IdRiga) = 1, 1, 0) AS BIT),
			IdAliquotaIvaCliente = c.IdAliquotaIva,
			DdtNumero = CAST(CAST(doc.Numero AS VARCHAR(10)) + ISNULL('/' + doc.Sezionale, '') AS VARCHAR(20)),
			DdtData = CONVERT(VARCHAR(10), doc.[Data], 103),
			Destinatario = sd.NomeCompleto + ISNULL(' ' + sd.IndirizzoCompleto, ''),
			Destinazione = ISNULL(sz.NomeCompleto + ISNULL(' ' + sz.IndirizzoCompleto, ''), sd.NomeCompleto + ISNULL(' ' + sd.IndirizzoCompleto, ''))
		FROM
			dbo.ufnImportiMagazzino_get_ApplicazioneRighe_List(@Id, NULL, NULL, NULL, 0) x
			INNER JOIN dbo.ufnImportiMagazzino_get_Documenti(@Id, NULL, NULL, NULL) doc ON x.IdMovimento = doc.Id
			LEFT JOIN dbo.tblClientiFornitori c ON c.Id = @IdClienteFornitore
			LEFT JOIN dbo.tblSedi sd ON doc.IdDestinatario = sd.Id
			LEFT JOIN dbo.tblSedi sz ON doc.IdDestinazione = sz.Id
		WHERE x.IdImporto IS NOT NULL
	),
	righe AS (
		SELECT
			a.IdRiga,
			a.PosDdt,
			a.IdImporto,
			g.Id,
			g.Pos,
			g.IdTipo,
			MinimoFatturabile = CAST(ISNULL(g.MinimoFatturabile, 0) AS BIT),
			Prezzo = g.Importo,
			Quantita = CAST(CASE
				WHEN g.Importo IS NULL THEN NULL
				WHEN g.IdTipo = 'MM' THEN 1
				WHEN g.IdTipo = 'MA' THEN a.Quantita
			END AS DECIMAL(18, 4)),
			IdUnitaMisura = CAST(CASE
				WHEN g.Importo IS NULL THEN NULL
				WHEN g.IdTipo = 'MM' THEN 'NR'
				WHEN g.IdTipo = 'MA' THEN a.IdUnitaMisura
			END AS CHAR(2)),
			Descrizione = CAST(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(d.Descrizione, ''),
				'#1', ISNULL(a.Voce, '')),
				'#2', ISNULL(a.DdtNumero, '')),
				'#3', ISNULL(a.DdtData, '__/__/____')),
				'#4', ISNULL(a.Destinatario, '')),
				'#5', ISNULL(a.Destinazione, '')) AS VARCHAR(1000)),
			IdAliquotaIva = ISNULL(d.IdAliquotaIva, a.IdAliquotaIvaCliente),
			d.IdConto
		FROM
			a
			INNER JOIN dbo.tblImportiRighe g ON a.IdImporto = g.IdImporto
			LEFT JOIN dbo.tblImportiRigheDettagli d ON g.Id = d.Id
		WHERE
			-- A quantità: per ogni riga del DDT; le altre (per movimento, sola descrizione, minimo): una volta
			a.Prima = 1
			OR (g.Importo IS NOT NULL AND g.IdTipo = 'MA' AND ISNULL(g.MinimoFatturabile, 0) = 0)
	),
	minimo AS (
		-- Per ogni importo, somma degli imponibili delle righe con cui si confronta il suo minimo fatturabile
		SELECT
			m.IdImporto,
			Altre = ISNULL((
				SELECT SUM(ROUND(x.Prezzo * x.Quantita, 2))
				FROM righe x
				WHERE
					x.IdImporto = m.IdImporto
					AND x.MinimoFatturabile = 0
					AND x.Quantita IS NOT NULL
					AND (m.IdTipo = 'MM' OR x.IdTipo <> 'MM')
			), 0)
		FROM righe m
		WHERE
			m.MinimoFatturabile = 1
			AND m.Prezzo IS NOT NULL
	)
	SELECT
		t.IdRiga,
		t.PosDdt,
		t.IdImporto,
		t.Id,
		t.Pos,
		t.IdTipo,
		t.MinimoFatturabile,
		SolaDescrizione = CAST(IIF(t.Prezzo IS NULL, 1, 0) AS BIT),
		t.Descrizione,
		Quantita = CAST(IIF(t.MinimoFatturabile = 1, 1, t.Quantita) AS DECIMAL(18, 4)),
		IdUnitaMisura = CAST(IIF(t.MinimoFatturabile = 1, 'NR', t.IdUnitaMisura) AS CHAR(2)),
		Importo = CAST(IIF(t.MinimoFatturabile = 1, t.Prezzo - n.Altre, t.Prezzo) AS DECIMAL(18, 4)),
		Imponibile = CAST(ROUND(IIF(t.MinimoFatturabile = 1, t.Prezzo - n.Altre, t.Prezzo * t.Quantita), 2) AS DECIMAL(18, 2)),
		t.IdAliquotaIva,
		t.IdConto
	FROM
		righe t
		LEFT JOIN minimo n ON t.MinimoFatturabile = 1
						  AND t.IdImporto = n.IdImporto
	WHERE
		-- Sola descrizione: sempre
		t.Prezzo IS NULL
		-- Riga normale: solo se ha una quantità
		OR (t.MinimoFatturabile = 0 AND t.Quantita IS NOT NULL)
		-- Minimo fatturabile: solo per la differenza non raggiunta dalle altre righe
		OR (t.MinimoFatturabile = 1 AND t.Prezzo > n.Altre)
);
GO
