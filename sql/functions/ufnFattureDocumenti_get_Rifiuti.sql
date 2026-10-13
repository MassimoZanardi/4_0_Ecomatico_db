SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Generazione automatica delle fatture: registrazioni dei rifiuti candidate, con l'importo e il cliente che
-- verrebbero applicati (ufnImportiRifiuti_get_Applicazione_List: il confronto con gli importi è fatto una volta
-- per tutte le registrazioni; le righe si leggono con ufnImportiRifiuti_get_RigheImporto) e l'esito. Serve sia alla verifica
-- (uspFatture_get_Genera_List) sia alla generazione (uspFatture_ins_Genera), così leggono le stesse righe.
--   @Id: una sola registrazione ("Genera la fattura" dalla scheda); altrimenti @IdAzienda e l'intervallo di date.
--   @IdClienteFornitore: solo i documenti riconducibili a quel cliente (quelli che gli verrebbero fatturati).
--   @IncludiPreFatture = 1: rientrano anche i documenti già in una pre-fattura (IdPreFattura), che verrà
--        convertita: in fattura vanno le righe della pre-fattura, non quelle ricalcolate dagli importi, e il
--        cliente è quello della pre-fattura.
-- Candidate: registrazioni confermate (Lock = 0) di un'operazione fatturabile, non rettifiche, di un registro
-- di una sede che la sessione vede (titolarità), non ancora in una fattura (le pre-fatture non contano come
-- fattura quando si includono).
-- Fatturabile = 1: non annullata, non "Non fatturabile", con un importo che coincide, un
-- cliente determinato, almeno una riga e l'aliquota IVA su ogni riga con importo (della riga o della scheda del
-- cliente). Stessa condizione di uspFattureDocumenti_get ("Verifica importo e
-- cliente" sulla scheda): vanno tenute allineate. Un documento in una pre-fattura inclusa è sempre fatturabile.
CREATE OR ALTER FUNCTION dbo.ufnFattureDocumenti_get_Rifiuti (
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
		a.Numero,
		a.IdAzienda,
		a.IdProduttore,
		a.IdEer,
		a.IdUnitaMisura,
		a.Quantita,
		a.IsAnnullata,
		a.NonFatturabile,
		IdPreFattura = IIF(a.IsPreFattura = 1, a.IdFattura, NULL),
		a.IdImporto,
		a.IdOffertaContratto,
		IdClienteFornitore = IIF(a.IsPreFattura = 1, a.IdClientePreFattura, a.IdClienteFornitore),
		a.ClienteOrigine,
		a.IdImportoScartato,
		Righe = ISNULL(t.Righe, 0),
		Totale = t.Totale,
		SenzaIva = ISNULL(t.SenzaIva, 0),
		Fatturabile = CAST(CASE
			WHEN a.IsPreFattura = 1 THEN 1
			WHEN a.IsAnnullata = 0 AND a.NonFatturabile = 0
				AND a.IdImporto IS NOT NULL AND a.IdClienteFornitore IS NOT NULL AND ISNULL(t.Righe, 0) > 0 AND ISNULL(t.SenzaIva, 0) = 0 THEN 1
			ELSE 0
		END AS BIT)
	FROM
		-- Registrazioni confermate di un'operazione fatturabile, non rettifiche, di @Id o dell'azienda nel
		-- periodo, con l'importo e il cliente applicati: il confronto è fatto una volta per tutte
		dbo.ufnImportiRifiuti_get_Applicazione_List(@Id, @IdAzienda, @DataDa, @DataA, 1) a
		INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeRegistro = x.Id
		OUTER APPLY (
			SELECT
				Totale = SUM(ISNULL(q.Imponibile, 0)),
				Righe = COUNT(*),
				SenzaIva = SUM(IIF(q.SolaDescrizione = 0 AND q.IdAliquotaIva IS NULL, 1, 0))
			FROM dbo.ufnImportiRifiuti_get_RigheImporto(a.Id, a.IdImporto, a.IdClienteFornitore) q
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
