SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Generazione automatica delle fatture: servizi candidati, con gli importi e il cliente che verrebbero applicati
-- (ufnImportiServizi_get_Applicazione_List: un solo importo per servizio) e l'esito. Stesse colonne e stessi
-- parametri di ufnFattureDocumenti_get_Magazzino: si leggono insieme in ufnFattureGenera_get_Documenti. Id è l'Id
-- del servizio, Data quella del suo evento; il servizio non ha un numero.
--   @Id: un solo servizio ("Genera la fattura" dalla scheda); altrimenti @IdAzienda e l'intervallo di date.
-- Candidati: servizi confermati ed Eseguiti, non serie ricorrenti, di un calendario di una sede che la sessione
-- vede, non ancora in una fattura (le pre-fatture non contano come fattura quando si includono).
-- IdProduttore: qui è il richiedente del servizio, la sede per il raggruppamento "una fattura per sede".
-- SenzaImporto = 1: nessun importo coincide, oppure l'importo applicato non ha una riga per una delle risorse.
-- Fatturabile = 1: non "Non fatturabile", un importo con una riga per ogni risorsa, un cliente determinato,
-- almeno una riga di fattura e l'aliquota IVA su ogni riga con importo. Stessa condizione di
-- uspFattureDocumenti_get: vanno tenute allineate. Un servizio in una pre-fattura inclusa è sempre fatturabile.
CREATE OR ALTER FUNCTION dbo.ufnFattureDocumenti_get_Servizi (
	@IdSessione CHAR(16),
	@IdAzienda CHAR(16),
	@Id CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@IdClienteFornitore CHAR(16),
	@IncludiPreFatture BIT)
RETURNS TABLE
AS
RETURN
(
	SELECT
		a.Id,
		a.[Data],
		Numero = CAST(NULL AS INT),
		a.IdAzienda,
		IdProduttore = a.IdRichiedente,
		IdEer = CAST(NULL AS CHAR(6)),
		IdUnitaMisura = CAST(NULL AS CHAR(2)),
		Quantita = CAST(NULL AS DECIMAL(18, 2)),
		IsAnnullata = CAST(0 AS BIT),
		a.NonFatturabile,
		IdPreFattura = IIF(a.IsPreFattura = 1, a.IdFattura, NULL),
		a.IdImporto,
		a.IdOffertaContratto,
		IdClienteFornitore = IIF(a.IsPreFattura = 1, a.IdClientePreFattura, a.IdClienteFornitore),
		a.ClienteOrigine,
		a.IdImportoScartato,
		SenzaImporto = CAST(IIF(a.IdImporto IS NULL OR a.RisorseSenzaImporto > 0, 1, 0) AS BIT),
		Righe = ISNULL(t.Righe, 0),
		Totale = t.Totale,
		SenzaIva = ISNULL(t.SenzaIva, 0),
		Fatturabile = CAST(CASE
			WHEN a.IsPreFattura = 1 THEN 1
			WHEN a.NonFatturabile = 0 AND a.IdImporto IS NOT NULL AND a.RisorseSenzaImporto = 0
				AND a.IdClienteFornitore IS NOT NULL AND ISNULL(t.Righe, 0) > 0 AND ISNULL(t.SenzaIva, 0) = 0 THEN 1
			ELSE 0
		END AS BIT)
	FROM
		dbo.ufnImportiServizi_get_Applicazione_List(@Id, @IdAzienda, @DataDa, @DataA, 1) a
		INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeInterna = x.Id
		OUTER APPLY (
			SELECT
				Totale = SUM(ISNULL(q.Imponibile, 0)),
				Righe = COUNT(*),
				SenzaIva = SUM(IIF(q.SolaDescrizione = 0 AND q.IdAliquotaIva IS NULL, 1, 0))
			FROM dbo.ufnImportiServizi_get_RigheFattura(a.Id, a.IdClienteFornitore) q
		) t
	WHERE
		-- Non ancora in una fattura; in una pre-fattura solo se si includono
			(
			a.IdFattura IS NULL
			OR (a.IsPreFattura = 1 AND @IncludiPreFatture = 1)
			)
		AND
			(
			@IdClienteFornitore IS NULL
			OR IIF(a.IsPreFattura = 1, a.IdClientePreFattura, a.IdClienteFornitore) = @IdClienteFornitore
			)
);
GO
