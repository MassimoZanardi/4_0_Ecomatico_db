SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Generazione automatica delle fatture: i documenti candidati, cioè le registrazioni dei rifiuti
-- (ufnFattureDocumenti_get_Rifiuti, con @Rifiuti = 1), i DDT di magazzino (ufnFattureDocumenti_get_Magazzino,
-- con @Magazzino = 1) e i servizi (ufnFattureDocumenti_get_Servizi, con @Servizi = 1), con in più ciò che serve a
-- raggrupparli in fatture e a riepilogarli. IdModulo dice da quale viene il documento (RIF, MAG, SRV): per un DDT,
-- Id è l'Id del movimento; un servizio non ha un numero (Numero NULL).
-- La leggono il riepilogo (uspFatture_get_Genera_Riepilogo), l'anteprima delle fatture
-- (uspFatture_get_Genera_Fatture_List), l'elenco di dettaglio (uspFatture_get_Genera_List) e la generazione
-- (uspFatture_ins_Genera): così contano, mostrano e generano le stesse cose.
--   GruppoSede, GruppoContratto: con il cliente dicono in quale fattura va il documento, secondo il
--        raggruppamento della scheda del cliente (tblClientiFornitori.IdRaggruppamento): S una fattura per sede
--        del produttore, T una per contratto, altrimenti una per cliente (entrambi NULL). I documenti di una
--        stessa pre-fattura restano insieme: prendono il gruppo del suo primo documento (data, numero).
--   PrimoDellaPreFattura: il primo documento della sua pre-fattura, che ne porta le righe e l'imponibile.
--   Imponibile: quello delle righe dell'importo applicato; per una pre-fattura il suo imponibile, una volta
--        sola, sul primo documento (NULL sugli altri).
--   Esito: F fatturabile; S fatturabile con l'importo standard perché il contratto non è valido alla data;
--        P in una pre-fattura che verrà convertita; A annullata; N indicata come non fatturabile; I nessun
--        importo coincide; C cliente non determinato; R l'importo non ha righe applicabili; V manca
--        l'aliquota IVA. F, S e P entrano in una fattura (Fatturabile = 1).
CREATE OR ALTER FUNCTION dbo.ufnFattureGenera_get_Documenti (
	@IdSessione CHAR(16),
	@IdAzienda CHAR(16),
	@Id CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@IdClienteFornitore CHAR(16),
	@IncludiPreFatture BIT,
	@Rifiuti BIT,
	@Magazzino BIT,
	@Servizi BIT)
RETURNS TABLE
AS
RETURN
(
	SELECT
		t.Id,
		t.IdModulo,
		t.[Data],
		t.Numero,
		t.IdAzienda,
		t.IdProduttore,
		t.IdEer,
		t.IdUnitaMisura,
		t.Quantita,
		t.IsAnnullata,
		t.NonFatturabile,
		t.IdPreFattura,
		t.IdImporto,
		t.IdOffertaContratto,
		t.IdClienteFornitore,
		t.ClienteOrigine,
		t.IdImportoScartato,
		t.Righe,
		t.Totale,
		t.SenzaIva,
		t.Fatturabile,
		PrimoDellaPreFattura = CAST(IIF(t.IdPreFattura IS NOT NULL AND t.N = 1, 1, 0) AS BIT),
		GruppoSede = IIF(t.IdPreFattura IS NULL, t.GruppoSedeProprio,
			FIRST_VALUE(t.GruppoSedeProprio) OVER (PARTITION BY t.IdPreFattura ORDER BY t.[Data], t.Numero, t.Id)),
		GruppoContratto = IIF(t.IdPreFattura IS NULL, t.GruppoContrattoProprio,
			FIRST_VALUE(t.GruppoContrattoProprio) OVER (PARTITION BY t.IdPreFattura ORDER BY t.[Data], t.Numero, t.Id)),
		Imponibile = CASE
			WHEN t.IdPreFattura IS NULL THEN t.Totale
			WHEN t.N = 1 THEN pf.Imponibile
		END,
		Esito = CAST(CASE
			WHEN t.IdPreFattura IS NOT NULL THEN 'P'
			WHEN t.Fatturabile = 1 AND t.IdImportoScartato IS NOT NULL AND t.IdOffertaContratto IS NULL THEN 'S'
			WHEN t.Fatturabile = 1 THEN 'F'
			WHEN t.IsAnnullata = 1 THEN 'A'
			WHEN t.NonFatturabile = 1 THEN 'N'
			WHEN t.SenzaImporto = 1 THEN 'I'
			WHEN t.IdClienteFornitore IS NULL THEN 'C'
			WHEN t.Righe = 0 THEN 'R'
			ELSE 'V'
		END AS CHAR(1))
	FROM
		(
			SELECT
				d.Id,
				d.IdModulo,
				d.[Data],
				d.Numero,
				d.IdAzienda,
				d.IdProduttore,
				d.IdEer,
				d.IdUnitaMisura,
				d.Quantita,
				d.IsAnnullata,
				d.NonFatturabile,
				d.IdPreFattura,
				d.IdImporto,
				d.IdOffertaContratto,
				d.IdClienteFornitore,
				d.ClienteOrigine,
				d.IdImportoScartato,
				d.SenzaImporto,
				d.Righe,
				d.Totale,
				d.SenzaIva,
				d.Fatturabile,
				GruppoSedeProprio = IIF(c.IdRaggruppamento = 'S', d.IdProduttore, NULL),
				GruppoContrattoProprio = IIF(c.IdRaggruppamento = 'T', d.IdOffertaContratto, NULL),
				-- Posizione del documento nella sua pre-fattura (conta solo dove IdPreFattura non è NULL)
				N = ROW_NUMBER() OVER (PARTITION BY d.IdPreFattura ORDER BY d.[Data], d.Numero, d.Id)
			FROM
				(
					SELECT IdModulo = CAST('RIF' AS CHAR(3)), Id, [Data], Numero, IdAzienda, IdProduttore, IdEer, IdUnitaMisura, Quantita, IsAnnullata, NonFatturabile, IdPreFattura, IdImporto, IdOffertaContratto, IdClienteFornitore, ClienteOrigine, IdImportoScartato, SenzaImporto, Righe, Totale, SenzaIva, Fatturabile
					FROM dbo.ufnFattureDocumenti_get_Rifiuti(@IdSessione, @IdAzienda, @Id, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture)
					WHERE @Rifiuti = 1

					UNION ALL

					SELECT IdModulo = CAST('MAG' AS CHAR(3)), Id, [Data], Numero, IdAzienda, IdProduttore, IdEer, IdUnitaMisura, Quantita, IsAnnullata, NonFatturabile, IdPreFattura, IdImporto, IdOffertaContratto, IdClienteFornitore, ClienteOrigine, IdImportoScartato, SenzaImporto, Righe, Totale, SenzaIva, Fatturabile
					FROM dbo.ufnFattureDocumenti_get_Magazzino(@IdSessione, @IdAzienda, @Id, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture)
					WHERE @Magazzino = 1

					UNION ALL

					SELECT IdModulo = CAST('SRV' AS CHAR(3)), Id, [Data], Numero, IdAzienda, IdProduttore, IdEer, IdUnitaMisura, Quantita, IsAnnullata, NonFatturabile, IdPreFattura, IdImporto, IdOffertaContratto, IdClienteFornitore, ClienteOrigine, IdImportoScartato, SenzaImporto, Righe, Totale, SenzaIva, Fatturabile
					FROM dbo.ufnFattureDocumenti_get_Servizi(@IdSessione, @IdAzienda, @Id, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture)
					WHERE @Servizi = 1
				) d
				LEFT JOIN dbo.tblClientiFornitori c ON d.IdClienteFornitore = c.Id
		) t
		OUTER APPLY dbo.ufnFatture_get_Totali(IIF(t.N = 1, t.IdPreFattura, NULL)) pf
);
GO
