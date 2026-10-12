SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Importi rifiuti dell'azienda interna corrente della sessione: righe comuni all'elenco
-- (uspImportiRifiuti_get_List) e all'esportazione (uspImportiRifiuti_get_Esportazione), così scope e
-- criteri di ricerca stanno in un posto solo. Senza azienda nel contesto nessuna riga.
-- Una variabile non indicata nell'importo (NULL) vale "qualsiasi".
-- Contratto: al massimo uno per importo (UX_OfferteContrattiImporti_IdImporto); Tipo C contratto, O offerta.
CREATE OR ALTER FUNCTION dbo.ufnImportiRifiuti_get_List (
	@IdSessione CHAR(16),
	@Search VARCHAR(50))
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
		Eer = e.Nome + IIF(e.Pericoloso = 1, '*', ''),
		EerDescrizione = e.Descrizione,
		Produttore = IIF(r.IdProduttore IS NULL, pa.NomeCompleto, ps.NomeCompleto + ISNULL(' ' + ps.IndirizzoCompleto, '')),
		Trasportatore = tr.NomeCompleto + ISNULL(' ' + tr.IndirizzoCompleto, ''),
		Destinatario = de.NomeCompleto + ISNULL(' ' + de.IndirizzoCompleto, ''),
		Intermediario = im.NomeCompleto + ISNULL(' ' + im.IndirizzoCompleto, ''),
		Etichetta = et.Nome,
		c.Cliente,
		ContrattoTipo = c.Tipo,
		ContrattoDataInizio = c.DataInizio,
		ContrattoDataFine = c.DataFine,
		Righe = ISNULL(g.Righe, 0)
	FROM
		dbo.tblImporti i
		INNER JOIN dbo.tblSessioni s ON i.IdSede = s.IdAzienda
		INNER JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
		LEFT JOIN dbo.tblImportiPriorita p ON i.IdPriorita = p.Id
		LEFT JOIN dbo.tblRifiutiEer e ON r.IdEer = e.Id
		LEFT JOIN dbo.tblSedi pa ON r.IdProduttoreParent = pa.Id
		LEFT JOIN dbo.tblSedi ps ON r.IdProduttore = ps.Id
		LEFT JOIN dbo.tblSedi tr ON r.IdTrasportatore = tr.Id
		LEFT JOIN dbo.tblSedi de ON r.IdDestinatario = de.Id
		LEFT JOIN dbo.tblSedi im ON r.IdIntermediario = im.Id
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
		AND
			(
			@Search IS NULL
			OR i.Nome LIKE '%' + @Search + '%'
			OR e.Nome LIKE '%' + @Search + '%'
			OR pa.NomeCompleto LIKE '%' + @Search + '%'
			OR ps.NomeCompleto LIKE '%' + @Search + '%'
			OR tr.NomeCompleto LIKE '%' + @Search + '%'
			OR de.NomeCompleto LIKE '%' + @Search + '%'
			OR im.NomeCompleto LIKE '%' + @Search + '%'
			OR et.Nome LIKE '%' + @Search + '%'
			OR c.Cliente LIKE '%' + @Search + '%'
			)
);
GO
