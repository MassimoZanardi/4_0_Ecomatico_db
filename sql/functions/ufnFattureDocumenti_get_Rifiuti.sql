SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Generazione automatica delle fatture: registrazioni dei rifiuti candidate, con l'importo e il cliente che
-- verrebbero applicati (ufnImportiRifiuti_get_Applicazione) e l'esito. Serve sia alla verifica
-- (uspFatture_get_Genera_List) sia alla generazione (uspFatture_ins_Genera), così leggono le stesse righe.
--   @Id: una sola registrazione ("Genera la fattura" dalla scheda); altrimenti @IdAzienda e l'intervallo di date.
--   @IdClienteFornitore: solo i documenti che verrebbero fatturati a quel cliente.
-- Candidate: registrazioni confermate (Lock = 0) di un'operazione fatturabile, non rettifiche, di un registro
-- di una sede che la sessione vede (titolarità).
-- Fatturabile = 1: non annullata, non "Non fatturabile", non già fatturata, con un importo che coincide, un
-- cliente determinato, almeno una riga e l'aliquota IVA su ogni riga con importo (della riga o della scheda del
-- cliente). Stessa condizione di uspFattureDocumenti_get ("Verifica importo e
-- cliente" sulla scheda): vanno tenute allineate.
CREATE OR ALTER FUNCTION dbo.ufnFattureDocumenti_get_Rifiuti (
	@IdSessione CHAR(16),
	@IdAzienda CHAR(16),
	@Id CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@IdClienteFornitore CHAR(16))
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
		a.IdFattura,
		a.IdImporto,
		a.IdOffertaContratto,
		a.IdClienteFornitore,
		a.ClienteOrigine,
		a.IdImportoScartato,
		Righe = ISNULL(t.Righe, 0),
		Totale = t.Totale,
		SenzaIva = ISNULL(t.SenzaIva, 0),
		Fatturabile = CAST(IIF(
			a.IsAnnullata = 0 AND a.NonFatturabile = 0 AND a.IdFattura IS NULL
			AND a.IdImporto IS NOT NULL AND a.IdClienteFornitore IS NOT NULL AND ISNULL(t.Righe, 0) > 0 AND ISNULL(t.SenzaIva, 0) = 0, 1, 0) AS BIT)
	FROM
		dbo.tblRifiutiRegistrazioni r
		INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
		INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
		INNER JOIN dbo.tblSedi sr ON g.IdSede = sr.Id
		INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON g.IdSede = x.Id
		CROSS APPLY dbo.ufnImportiRifiuti_get_Applicazione(r.Id) a
		OUTER APPLY (
			SELECT
				Totale = SUM(ISNULL(q.Imponibile, 0)),
				Righe = COUNT(*),
				SenzaIva = SUM(IIF(q.SolaDescrizione = 0 AND q.IdAliquotaIva IS NULL, 1, 0))
			FROM dbo.ufnImportiRifiuti_get_ApplicazioneRighe(r.Id) q
		) t
	WHERE
		r.Lock = 0
		AND o.IsFatturabile = 1
		AND a.IsRettifica = 0
		AND
			(
				(@Id IS NOT NULL AND r.Id = @Id)
				OR
				(
					@Id IS NULL
					AND sr.IdAziendaInterna = @IdAzienda
					AND r.[Data] >= @DataDa
					AND r.[Data] <= @DataA
				)
			)
		AND (@IdClienteFornitore IS NULL OR a.IdClienteFornitore = @IdClienteFornitore)
);
GO
