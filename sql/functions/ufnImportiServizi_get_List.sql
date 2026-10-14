SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti > Importi servizi: righe dell'elenco e dell'esportazione (uspImportiServizi_get_List,
-- uspImportiServizi_get_Esportazione), così leggono le stesse righe con la stessa ricerca.
-- Scope: importi dei servizi attivi dell'azienda interna corrente della sessione.
-- Variabili: tipo di servizio, richiedente (soggetto e, facoltativa, una sua sede), sede interna (quella del
-- calendario che ospita il servizio), etichetta del servizio. Una variabile NULL vale "qualsiasi". Le risorse
-- stanno sulle righe dell'importo.
-- StatoValore 1 (avviso): importo senza righe, importo di un'offerta, contratto scaduto.
--   @SoloContrattoScaduto = 1: solo gli importi di un contratto confermato la cui validità è finita prima di oggi.
CREATE OR ALTER FUNCTION dbo.ufnImportiServizi_get_List (
	@IdSessione CHAR(16),
	@Search VARCHAR(50),
	@SoloContrattoScaduto BIT)
RETURNS TABLE
AS
RETURN
(
	SELECT
		i.Id,
		StatoValore = CASE
			WHEN g.Righe IS NULL THEN 1
			WHEN c.Tipo = 'O' THEN 1
			WHEN c.DataFine < CAST(GETDATE() AS DATE) THEN 1
			ELSE 0
		END,
		StatoDescrizione = CASE
			WHEN g.Righe IS NULL THEN 'Importo senza righe: non genera righe in fattura'
			WHEN c.Tipo = 'O' THEN 'Importo di un''offerta: non viene applicato nella fatturazione'
			WHEN c.DataFine < CAST(GETDATE() AS DATE) THEN 'Contratto scaduto il ' + CONVERT(VARCHAR(10), c.DataFine, 103)
			ELSE 'OK'
		END,
		i.Nome,
		i.IdPriorita,
		Priorita = p.Nome,
		Tipo = tp.Nome,
		Richiedente = IIF(r.IdRichiedente IS NULL, ra.NomeCompleto, rs.NomeCompleto + ISNULL(' ' + rs.IndirizzoCompleto, '')),
		SedeInterna = si.NomeCompleto + ISNULL(' ' + si.IndirizzoCompleto, ''),
		Etichetta = et.Nome,
		c.Cliente,
		ContrattoTipo = c.Tipo,
		ContrattoDataInizio = c.DataInizio,
		ContrattoDataFine = c.DataFine,
		Righe = ISNULL(g.Righe, 0)
	FROM
		dbo.tblImporti i
		INNER JOIN dbo.tblSessioni s ON i.IdSede = s.IdAzienda
		INNER JOIN dbo.tblImportiServizi r ON i.Id = r.Id
		LEFT JOIN dbo.tblImportiPriorita p ON i.IdPriorita = p.Id
		LEFT JOIN dbo.tblTipi tp ON r.IdTipo = tp.Id
		LEFT JOIN dbo.tblSedi ra ON r.IdRichiedenteParent = ra.Id
		LEFT JOIN dbo.tblSedi rs ON r.IdRichiedente = rs.Id
		LEFT JOIN dbo.tblSedi si ON r.IdSedeInterna = si.Id
		LEFT JOIN dbo.tblEtichette et ON r.IdEtichetta = et.Id
		OUTER APPLY (
			SELECT Righe = COUNT(*)
			FROM dbo.tblImportiRighe x
			WHERE x.IdImporto = i.Id
			HAVING COUNT(*) > 0
		) g
		OUTER APPLY (
			SELECT TOP (1)
				oc.Tipo,
				oc.Lock,
				oc.DataInizio,
				oc.DataFine,
				Cliente = cs.NomeCompleto
			FROM
				dbo.tblOfferteContrattiImporti ci
				INNER JOIN dbo.tblOfferteContratti oc ON ci.IdOffertaContratto = oc.Id
				LEFT JOIN dbo.tblClientiFornitori cf ON oc.IdClienteFornitore = cf.Id
				LEFT JOIN dbo.tblSedi cs ON cf.IdSede = cs.Id
			WHERE
				ci.IdImporto = i.Id
				AND oc.Lock <= 2
		) c
	WHERE
		s.Id = @IdSessione
		AND i.Lock = 0
		-- Solo gli importi di un contratto confermato la cui validità è finita prima di oggi
		AND
			(
			ISNULL(@SoloContrattoScaduto, 0) = 0
			OR (c.Tipo = 'C' AND c.Lock = 0 AND c.DataFine < CAST(GETDATE() AS DATE))
			)
		AND
			(
			@Search IS NULL
			OR i.Nome LIKE '%' + @Search + '%'
			OR tp.Nome LIKE '%' + @Search + '%'
			OR ra.NomeCompleto LIKE '%' + @Search + '%'
			OR rs.NomeCompleto LIKE '%' + @Search + '%'
			OR si.NomeCompleto LIKE '%' + @Search + '%'
			OR et.Nome LIKE '%' + @Search + '%'
			OR c.Cliente LIKE '%' + @Search + '%'
			)
);
GO
