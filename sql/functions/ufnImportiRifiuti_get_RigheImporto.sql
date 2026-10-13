SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: righe di fattura che l'importo @IdImporto genera per la registrazione dei rifiuti @Id,
-- nell'ordine delle righe dell'importo. Importo e cliente sono quelli già determinati dal confronto
-- (ufnImportiRifiuti_get_Applicazione_List): qui non lo si rifà. Funzione in linea: si può usare con CROSS APPLY
-- su più registrazioni. Nessuna riga se @IdImporto è NULL.
--
-- Quantità secondo il tipo della riga: RM una per registrazione (unità NR); RK i chilogrammi e RT le tonnellate
-- (chilogrammi / 1000), solo per le registrazioni in chilogrammi; RL i litri, solo per le registrazioni in
-- litri. Una riga a quantità che non vale per l'unità della registrazione non entra. La quantità è quella
-- operativa della registrazione (dopo le rettifiche).
-- Riga di sola descrizione (importo NULL): entra sempre, senza quantità né importo.
-- Minimo fatturabile (al massimo una riga per importo): il suo importo è il minimo da fatturare per la
-- registrazione. Si confronta con la somma degli imponibili delle altre righe (se la riga del minimo è di tipo
-- RM, di tutte; altrimenti di quelle a quantità, senza le righe RM): se il minimo è maggiore la riga entra con
-- quantità 1 e importo pari alla differenza, altrimenti non entra.
-- Testo: i segnaposto #1 codice EER, #2 numero del formulario, #3 data del formulario, #4 produttore,
-- #5 destinatario vengono sostituiti con i dati della registrazione.
-- Aliquota IVA: quella della riga dell'importo, altrimenti quella della scheda del cliente @IdClienteFornitore.
CREATE OR ALTER FUNCTION dbo.ufnImportiRifiuti_get_RigheImporto (
	@Id CHAR(16),
	@IdImporto CHAR(16),
	@IdClienteFornitore CHAR(16))
RETURNS TABLE
AS
RETURN
(
	WITH a AS (
		SELECT
			r.Id,
			IdImporto = @IdImporto,
			v.IdUnitaMisura,
			v.Quantita,
			IdAliquotaIvaCliente = c.IdAliquotaIva,
			Eer = e.Nome + IIF(e.Pericoloso = 1, '*', ''),
			m.FormularioNumero,
			FormularioData = CONVERT(VARCHAR(10), fo.DataEmissione, 103),
			Produttore = sp.NomeCompleto + ISNULL(' ' + sp.IndirizzoCompleto, ''),
			Destinatario = sd.NomeCompleto + ISNULL(' ' + sd.IndirizzoCompleto, '')
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			LEFT JOIN dbo.tblClientiFornitori c ON c.Id = @IdClienteFornitore
			LEFT JOIN dbo.tblRifiutiEer e ON v.IdEer = e.Id
			LEFT JOIN dbo.tblRifiutiFormulari fo ON r.IdMovimento = fo.IdMovimento
												 AND fo.Lock < 2
			LEFT JOIN dbo.tblSedi sp ON m.IdSedeProduttoreDetentore = sp.Id
			LEFT JOIN dbo.tblSedi sd ON m.IdSedeDestinatario = sd.Id
		WHERE
			r.Id = @Id
			AND @IdImporto IS NOT NULL
	),
	righe AS (
		SELECT
			g.Id,
			g.Pos,
			g.IdTipo,
			MinimoFatturabile = CAST(ISNULL(g.MinimoFatturabile, 0) AS BIT),
			Prezzo = g.Importo,
			Quantita = CAST(CASE
				WHEN g.Importo IS NULL THEN NULL
				WHEN g.IdTipo = 'RM' THEN 1
				WHEN g.IdTipo = 'RK' AND a.IdUnitaMisura = 'KG' THEN a.Quantita
				WHEN g.IdTipo = 'RT' AND a.IdUnitaMisura = 'KG' THEN a.Quantita / 1000.0
				WHEN g.IdTipo = 'RL' AND a.IdUnitaMisura = 'LT' THEN a.Quantita
			END AS DECIMAL(18, 4)),
			IdUnitaMisura = CAST(CASE
				WHEN g.Importo IS NULL THEN NULL
				WHEN g.IdTipo = 'RM' THEN 'NR'
				WHEN g.IdTipo = 'RK' THEN 'KG'
				WHEN g.IdTipo = 'RT' THEN 'TN'
				WHEN g.IdTipo = 'RL' THEN 'LT'
			END AS CHAR(2)),
			Descrizione = CAST(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(d.Descrizione, ''),
				'#1', ISNULL(a.Eer, '')),
				'#2', ISNULL(a.FormularioNumero, '')),
				'#3', ISNULL(a.FormularioData, '')),
				'#4', ISNULL(a.Produttore, '')),
				'#5', ISNULL(a.Destinatario, '')) AS VARCHAR(1000)),
			IdAliquotaIva = ISNULL(d.IdAliquotaIva, a.IdAliquotaIvaCliente),
			d.IdConto
		FROM
			a
			INNER JOIN dbo.tblImportiRighe g ON a.IdImporto = g.IdImporto
			LEFT JOIN dbo.tblImportiRigheDettagli d ON g.Id = d.Id
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
					AND (m.IdTipo = 'RM' OR x.IdTipo <> 'RM')
			), 0)
		FROM righe m
		WHERE
			m.MinimoFatturabile = 1
			AND m.Prezzo IS NOT NULL
	)
	SELECT
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
	WHERE
		-- Sola descrizione: sempre
		t.Prezzo IS NULL
		-- Riga normale: solo se ha una quantità per l'unità della registrazione
		OR (t.MinimoFatturabile = 0 AND t.Quantita IS NOT NULL)
		-- Minimo fatturabile: solo per la differenza non raggiunta dalle altre righe
		OR (t.MinimoFatturabile = 1 AND t.Prezzo > n.Altre)
);
GO
