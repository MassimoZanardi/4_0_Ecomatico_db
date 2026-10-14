SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, servizi: righe di fattura che l'importo applicato al servizio @Id genera.
-- Funzione in linea: si può usare con CROSS APPLY su più servizi. Nessuna riga se il servizio non ha un importo.
--
-- Righe a quantità (tipo SU, con la risorsa): una per ogni risorsa del servizio che ha il suo prezzo
-- nell'importo, nell'ordine delle risorse (per nome), con la quantità della risorsa nel servizio e l'unità di
-- misura della persona o dell'oggetto. Una riga a quantità la cui risorsa non è nel servizio non entra.
-- Righe per servizio (tipo SM) e righe di sola descrizione (importo NULL): una volta per servizio, dopo le righe
-- a quantità, nell'ordine delle righe dell'importo; quantità 1 (unità NR) se hanno un importo.
-- Minimo fatturabile (al massimo una riga per importo): è il minimo da fatturare per il servizio. Si confronta con
-- la somma degli imponibili delle altre righe (se la riga del minimo è di tipo SM, di tutte; altrimenti di quelle
-- a quantità): se il minimo è maggiore la riga entra con quantità 1 e importo pari alla differenza.
-- Testo: i segnaposto #1 data del servizio, #2 tipo di servizio, #3 richiedente, #4 risorsa (vuoto sulle righe
-- "una volta per servizio").
-- Aliquota IVA: quella della riga dell'importo, altrimenti quella della scheda del cliente @IdClienteFornitore.
-- Ordine: Gruppo (0 le righe a quantità, 1 quelle una volta per servizio), PosServizio, Pos.
CREATE OR ALTER FUNCTION dbo.ufnImportiServizi_get_RigheFattura (
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
			ServizioData = CONVERT(VARCHAR(10), doc.[Data], 103),
			Tipo = tp.Nome,
			Richiedente = sr.NomeCompleto + ISNULL(' ' + sr.IndirizzoCompleto, '')
		FROM
			dbo.ufnImportiServizi_get_Documenti(@Id, NULL, NULL, NULL) doc
			LEFT JOIN dbo.tblClientiFornitori c ON c.Id = @IdClienteFornitore
			LEFT JOIN dbo.tblTipi tp ON doc.IdTipo = tp.Id
			LEFT JOIN dbo.tblSedi sr ON doc.IdRichiedente = sr.Id
	),
	scelta AS (
		SELECT s.IdImporto
		FROM dbo.ufnImportiServizi_get_Scelta_List(@Id, NULL, NULL, NULL, 0) s
		WHERE s.IdImporto IS NOT NULL
	),
	righe AS (
		-- Righe a quantità: una per ogni risorsa del servizio che ha il suo prezzo nell'importo
		SELECT
			Gruppo = 0,
			a.IdOsepe,
			PosServizio = a.Pos,
			g.Id,
			g.Pos,
			g.IdTipo,
			MinimoFatturabile = CAST(0 AS BIT),
			Prezzo = g.Importo,
			Quantita = CAST(a.Quantita AS DECIMAL(18, 4)),
			IdUnitaMisura = CAST(a.IdUnitaMisura AS CHAR(2)),
			a.Voce
		FROM
			dbo.ufnImportiServizi_get_ApplicazioneRighe_List(@Id, NULL, NULL, NULL, 0) a
			INNER JOIN dbo.tblImportiRighe g ON a.IdRigaImporto = g.Id

		UNION ALL

		-- Righe per servizio, di sola descrizione e minimo fatturabile: una volta per servizio
		SELECT
			Gruppo = 1,
			IdOsepe = CAST(NULL AS CHAR(16)),
			PosServizio = 0,
			g.Id,
			g.Pos,
			g.IdTipo,
			MinimoFatturabile = CAST(ISNULL(g.MinimoFatturabile, 0) AS BIT),
			Prezzo = g.Importo,
			Quantita = CAST(IIF(g.Importo IS NULL, NULL, 1) AS DECIMAL(18, 4)),
			IdUnitaMisura = CAST(IIF(g.Importo IS NULL, NULL, 'NR') AS CHAR(2)),
			Voce = CAST(NULL AS VARCHAR(200))
		FROM
			scelta a
			INNER JOIN dbo.tblImportiRighe g ON a.IdImporto = g.IdImporto
		WHERE
			g.Importo IS NULL
			OR g.IdTipo = 'SM'
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
					AND (m.IdTipo = 'SM' OR x.IdTipo <> 'SM')
			), 0)
		FROM righe m
		WHERE
			m.MinimoFatturabile = 1
			AND m.Prezzo IS NOT NULL
	)
	SELECT
		t.Gruppo,
		t.IdOsepe,
		t.PosServizio,
		t.Id,
		t.Pos,
		t.IdTipo,
		t.MinimoFatturabile,
		SolaDescrizione = CAST(IIF(t.Prezzo IS NULL, 1, 0) AS BIT),
		Descrizione = CAST(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(d.Descrizione, ''),
			'#1', ISNULL(h.ServizioData, '__/__/____')),
			'#2', ISNULL(h.Tipo, '')),
			'#3', ISNULL(h.Richiedente, '')),
			'#4', ISNULL(t.Voce, '')) AS VARCHAR(1000)),
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
