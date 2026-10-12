SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Contratti (@Tipo = 'C') o offerte (@Tipo = 'O') dei clienti dell'azienda interna corrente della sessione: righe
-- comuni all'elenco (uspOfferteContratti_get_List) e all'esportazione (uspOfferteContratti_get_Esportazione),
-- così scope e criteri di ricerca stanno in un posto solo. Senza azienda nel contesto nessuna riga.
-- Stato (avviso, non blocco): scaduto, non ancora in vigore, senza importi.
CREATE OR ALTER FUNCTION dbo.ufnOfferteContratti_get_List (
	@IdSessione CHAR(16),
	@Tipo CHAR(1),
	@Search VARCHAR(50))
RETURNS TABLE
AS
RETURN
(
	SELECT
		oc.Id,
		StatoValore = CASE
			WHEN oc.DataFine < CAST(GETDATE() AS DATE) THEN 1
			WHEN oc.DataInizio > CAST(GETDATE() AS DATE) THEN 1
			WHEN g.Importi IS NULL THEN 1
			ELSE 0
		END,
		StatoDescrizione = CASE
			WHEN oc.DataFine < CAST(GETDATE() AS DATE) THEN IIF(oc.Tipo = 'O', 'Offerta scaduta il ', 'Contratto scaduto il ') + CONVERT(VARCHAR(10), oc.DataFine, 103)
			WHEN oc.DataInizio > CAST(GETDATE() AS DATE) THEN 'In vigore dal ' + CONVERT(VARCHAR(10), oc.DataInizio, 103)
			WHEN g.Importi IS NULL THEN IIF(oc.Tipo = 'O', 'Offerta senza importi', 'Contratto senza importi')
			ELSE 'In vigore'
		END,
		Cliente = cs.NomeCompleto,
		ClienteIndirizzo = cs.IndirizzoCompleto,
		ClientePartitaIva = cs.PartitaIva,
		ClienteCodiceFiscale = cs.CodiceFiscale,
		oc.Tipo,
		oc.DataInizio,
		oc.DataFine,
		oc.Descrizione,
		oc.Protocollo,
		oc.Ordine,
		oc.DataOrdine,
		oc.CodiceCig,
		oc.CodiceCup,
		Importi = ISNULL(g.Importi, 0)
	FROM
		dbo.tblOfferteContratti oc
		INNER JOIN dbo.tblSessioni s ON oc.IdSede = s.IdAzienda
		LEFT JOIN dbo.tblClientiFornitori cf ON oc.IdClienteFornitore = cf.Id
		LEFT JOIN dbo.tblSedi cs ON cf.IdSede = cs.Id
		OUTER APPLY (
			SELECT Importi = COUNT(*)
			FROM dbo.tblOfferteContrattiImporti ci
			WHERE ci.IdOffertaContratto = oc.Id
			HAVING COUNT(*) > 0
		) g
	WHERE
		s.Id = @IdSessione
		AND oc.Lock = 0
		AND oc.ClienteFornitoreTipo = 'C'
		AND oc.Tipo = @Tipo
		AND
			(
			@Search IS NULL
			OR cs.NomeCompleto LIKE '%' + @Search + '%'
			OR cs.PartitaIva LIKE '%' + @Search + '%'
			OR cs.CodiceFiscale LIKE '%' + @Search + '%'
			OR oc.Descrizione LIKE '%' + @Search + '%'
			OR oc.Protocollo LIKE '%' + @Search + '%'
			OR oc.Ordine LIKE '%' + @Search + '%'
			OR oc.CodiceCig LIKE '%' + @Search + '%'
			OR oc.CodiceCup LIKE '%' + @Search + '%'
			)
);
GO
