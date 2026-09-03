SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Vista consumata dall'hub condiviso 1_0_rentri (branch @App='40' di uspRegistrazioni_get_Conservazione_List),
-- referenziata letteralmente come [4_0_ecomatico]..viewRentriRegistrazioniConservazione. Alimenta la
-- generazione del file XML del registro per la conservazione sostitutiva (Rifiuti/Registrazioni,
-- GET/POST .../registrazioni/{id}/xml) - a differenza di viewRentriRegistrazioniStampa (report PDF,
-- soppressioni per-causale sui campi), questa vista e' quasi identica a viewRentriRegistrazioni
-- (stesso payload di dettaglio usato per l'invio), con 3 aggiunte proprie della conservazione:
-- Autore, DataInserimento, e un RegistrazioniAssociate con anche l'IdentificativoRentri per ogni
-- riferimento (non solo progressivo/anno). Colonne/soppressioni riusano le stesse formule gia'
-- verificate in viewRentriRegistrazioni - non ridotte, non re-inventate - per restare coerenti con
-- l'unica fonte di verita' sulle regole di business gia' stabilita in questo schema. Confrontata con
-- 3_1_ecomatico..viewRentriRegistrazioniConservazione (fornita dall'utente il 2026-09-03): stesso
-- sottoinsieme di campi consumati da RentriApi.Domain.Models.Registrazione (il modello e' condiviso
-- con l'invio - uspRegistrazioni_get_List/get_Conservazione_List usano lo stesso tipo C#).
CREATE OR ALTER VIEW [dbo].[viewRentriRegistrazioniConservazione]
AS
SELECT
	IDRegistro                  = g.Id,
	IDRentri                    = z.IdRentri,

	-- "Autore" nella vista gemella 3_1 e' la Sede del registro (non un utente) - stessa colonna
	-- gia' esposta come IdSede su tblRifiutiRegistri
	Autore                       = g.IdSede,
	-- Data della registrazione, con l'orario reale di inserimento (tblIdLog, Operazione='I')
	DataInserimento              = DATEADD(MINUTE, DATEPART(MINUTE, idl.Data), DATEADD(HOUR, DATEPART(HOUR, idl.Data), CAST(r.Data AS SMALLDATETIME))),

	IdRegistrazione             = r.Id,
	RentriIdentificativo        = r.RentriIdentificativo,
	Numero                      = r.Numero,
	Anno                        = YEAR(r.Data),

	RettificaNumero              = ISNULL(ro.Numero, 0),
	RettificaAnno                 = ISNULL(YEAR(ro.Data), 0),
	RettificaIdentificativo      = ro.RentriIdentificativo,
	RettificaIsAnnullata          = CAST(ISNULL(rett.Annullata, 0) AS BIT),

	Data                         = r.Data,
	Operazione                   = o.Codice,

	Eer                          = m.IdEer,
	EerDescrizione               = m.EerDescrizione,
	StatoFisico                  = sf.Codice,
	Provenienza                  = CASE WHEN o.Codice IN ('T*aT', 'TR') THEN NULL ELSE ISNULL(m.IdProvenienza, 'S') END,

	Quantita                     = m.Quantita,
	UnitaMisura                  = LOWER(um.Codice),
	-- Formato array JSON stringato (es. ["HP01","HP14"]), stessa resa di 3_1 per la conservazione
	-- (diversa sia da viewRentriRegistrazioni ';'-separata sia da viewRentriRegistrazioniStampa spazio-separata)
	ClassiPericolo                = cp.ClassiPericolo,

	VeicoloFuoriUso               = ISNULL(r.VeicoloFuoriUso, 0),
	VeicoloFuoriUsoNumero        = r.VeicoloFuoriUsoNumero,
	VeicoloFuoriUsoData          = ISNULL(r.VeicoloFuoriUsoData, r.Data),

	CategorieAee                 = raee.Codice,

	MaterialeSecondario           = mat.Codice,
	MaterialeSecondarioDescrizione = r.MaterialeDescrizione,

	Esito                        = es.Codice,
	DataEsito                    = ISNULL(r.DataFineTrasporto, r.Data),
	QuantitaDestino               = ISNULL(r.QuantitaVerificata, m.Quantita),

	EsitoCausaleRespingimento    = CASE WHEN ISNULL(es.Codice, 'A') = 'A' THEN NULL ELSE ISNULL(ecr.Codice, 'NC') END,
	RespingimentoMotivo          = CASE WHEN ISNULL(es.Codice, 'A') = 'A' THEN NULL ELSE ISNULL(r.CausaleRespingimentoAltro, 'Non conforme') END,
	RespingimentoQuantita        = ISNULL(r.QuantitaRespinta, m.Quantita),

	Destinazione                 = attv.Codice,

	-- A differenza di viewRentriRegistrazioni (progressivo/anno), qui anche l'IdentificativoRentri
	-- di ogni riferimento (stessa resa di 3_1..viewRentriRegistrazioniConservazione)
	RegistrazioniAssociate       = CASE
		WHEN o.Operazione = 'S' OR o.Codice = 'M' THEN assocRiferimenti.Registrazioni
		ELSE NULL
	END,

	FormularioNumero              = m.FormularioNumero,
	FormularioDataInizioTrasporto = ISNULL(m.DataInizioTrasporto, r.Data),
	TransfrontalieroTipo         = tt.Codice,

	ProduttoreNome                = sp.NomeCompleto,
	ProduttoreCodiceFiscale       = ISNULL(sp.CodiceFiscale, sp.PartitaIva),
	ProduttoreNazione             = nzp.Sigla,
	ProduttoreIdComune            = ip.IdComune,
	ProduttoreIndirizzo           = ip.Indirizzo,
	ProduttoreCAP                 = ip.CAP,
	ProduttoreLocalita            = ip.Localita,

	TrasportatoreNome             = st.NomeCompleto,
	TrasportatoreCodiceFiscale    = ISNULL(st.CodiceFiscale, st.PartitaIva),
	TrasportatoreNazione          = nzt.Sigla,
	TrasportatoreAutorizzazione   = at.Numero,

	DestinatarioNome               = sd.NomeCompleto,
	DestinatarioCodiceFiscale     = ISNULL(sd.CodiceFiscale, sd.PartitaIva),
	DestinatarioNazione           = nzd.Sigla,
	DestinatarioAutorizzazione    = ad.Numero,

	IntermediarioNome              = si.NomeCompleto,
	IntermediarioCodiceFiscale    = ISNULL(si.CodiceFiscale, si.PartitaIva),
	IntermediarioNazione          = nzi.Sigla,
	IntermediarioAutorizzazione   = ai.Numero,

	-- Nessun supporto multi-intermediario su Registrazioni in questo schema (solo IdSedeIntermediario1),
	-- stessa scelta gia' fatta in viewRentriRegistrazioni - la vista gemella 3_1 per la conservazione
	-- non referenzia Intermediario2* neanche lei
	Intermediario2Nome            = CAST(NULL AS VARCHAR(200)),
	Intermediario2CodiceFiscale   = CAST(NULL AS VARCHAR(20)),
	Intermediario2Nazione         = CAST(NULL AS CHAR(2)),
	Intermediario2Autorizzazione  = CAST(NULL AS VARCHAR(20)),

	IsProduttore                  = CAST(IIF(ISNULL(o.IsProduttore, 0) = 1 AND m.IdSedeProduttoreDetentore IS NOT NULL, 1, 0) AS BIT),
	IsTrasportatore                = CAST(IIF(ISNULL(o.IsTrasportatore, 0) = 1 AND m.IdSedeTrasportatore1 IS NOT NULL, 1, 0) AS BIT),
	IsDestinatario                 = CAST(IIF(ISNULL(o.IsDestinatario, 0) = 1 AND m.IdSedeDestinatario IS NOT NULL, 1, 0) AS BIT),
	IsIntermediario                = CAST(IIF(ISNULL(o.IsIntermediario, 0) = 1 AND m.IdSedeIntermediario1 IS NOT NULL, 1, 0) AS BIT),
	IsEsito                        = ISNULL(o.IsEsito, 0),
	IsFormulario                   = CAST(IIF(o.Codice IN ('aT', 'TR', 'T*', 'T*aT'), 1, 0) AS BIT),
	IsTransfrontaliero            = CAST(IIF(r.IdTrasportoTransfrontalieroTipo IS NOT NULL, 1, 0) AS BIT),
	IsStoccaggioIstantaneo        = ISNULL(o.IsStoccaggioIstantaneo, 0),

	Lock                          = r.Lock,

	Note                          = LEFT(r.Note, 500)
FROM
	dbo.tblRifiutiRegistrazioni r
	INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
	INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
	LEFT JOIN dbo.tblRentriRegistri z ON g.Id = z.Id
	LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
	LEFT JOIN dbo.tblRifiutiStatiFisici sf ON m.IdStatoFisico = sf.Id
	LEFT JOIN dbo.tblUnitaMisura um ON m.IdUnitaMisura = um.Id
	LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento attv ON m.IdAttivita = attv.Id
	LEFT JOIN dbo.tblRifiutiRaee raee ON r.IdRaee = raee.Id
	LEFT JOIN dbo.tblRifiutiMateriali mat ON r.IdMateriale = mat.Id
	LEFT JOIN dbo.tblRifiutiRegistrazioniEsiti es ON r.IdEsito = es.Id
	LEFT JOIN dbo.tblRifiutiRegistrazioniEsitiCausaliRespingimento ecr ON r.IdCausaleRespingimento = ecr.Id
	LEFT JOIN dbo.tblRifiutiTrasportiTransfrontalieriTipi tt ON r.IdTrasportoTransfrontalieroTipo = tt.Id
	LEFT JOIN dbo.tblRentriRegistrazioniRettifiche rett ON r.Id = rett.IdRettifica
	LEFT JOIN dbo.tblRifiutiRegistrazioni ro ON rett.Id = ro.Id
	LEFT JOIN dbo.tblIdLog idl ON r.Id = idl.Id AND idl.Operazione = 'I'

	LEFT JOIN dbo.tblSedi sp ON m.IdSedeProduttoreDetentore = sp.Id
	LEFT JOIN dbo.tblSediIndirizzi sip ON sp.Id = sip.Id
	LEFT JOIN dbo.tblIndirizzi ip ON sip.IdIndirizzo = ip.Id
	LEFT JOIN dbo.tblNazioni nzp ON ip.IdNazione = nzp.Id

	LEFT JOIN dbo.tblSedi st ON m.IdSedeTrasportatore1 = st.Id
	LEFT JOIN dbo.tblSediIndirizzi sit ON st.Id = sit.Id
	LEFT JOIN dbo.tblIndirizzi it_ ON sit.IdIndirizzo = it_.Id
	LEFT JOIN dbo.tblNazioni nzt ON it_.IdNazione = nzt.Id
	LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt ON m.Id = mt.Id AND mt.Pos = 0
	LEFT JOIN dbo.tblRifiutiAutorizzazioni at ON mt.IdAutorizzazione = at.Id

	LEFT JOIN dbo.tblSedi sd ON m.IdSedeDestinatario = sd.Id
	LEFT JOIN dbo.tblSediIndirizzi sid ON sd.Id = sid.Id
	LEFT JOIN dbo.tblIndirizzi id_ ON sid.IdIndirizzo = id_.Id
	LEFT JOIN dbo.tblNazioni nzd ON id_.IdNazione = nzd.Id
	LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
	LEFT JOIN dbo.tblRifiutiAutorizzazioni ad ON md.IdAutorizzazione = ad.Id

	LEFT JOIN dbo.tblSedi si ON m.IdSedeIntermediario1 = si.Id
	LEFT JOIN dbo.tblSediIndirizzi sii ON si.Id = sii.Id
	LEFT JOIN dbo.tblIndirizzi ii_ ON sii.IdIndirizzo = ii_.Id
	LEFT JOIN dbo.tblNazioni nzi ON ii_.IdNazione = nzi.Id
	LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi ON m.Id = mi.Id AND mi.Pos = 0
	LEFT JOIN dbo.tblRifiutiAutorizzazioni ai ON mi.IdAutorizzazione = ai.Id

	LEFT JOIN (
		SELECT
			mc.Id,
			ClassiPericolo = '[' + STRING_AGG('"' + c.Codice + '"', ',') WITHIN GROUP (ORDER BY c.Codice) + ']'
		FROM
			dbo.tblRifiutiMovimentiClassiPericolo mc
			LEFT JOIN dbo.tblRifiutiClassiPericolo c ON mc.IdClasse = c.Id
		GROUP BY
			mc.Id
	) cp ON m.Id = cp.Id

			OUTER APPLY (
		SELECT Registrazioni = (
			SELECT
				progressivo = rif.Numero,
				anno = YEAR(rif.Data),
				identificativoRentri = rif.RentriIdentificativo
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni rl
				INNER JOIN dbo.tblRifiutiRegistrazioni rif ON rl.Id = rif.Id
			WHERE
				rl.IdParent = r.Id
				AND rif.Lock = 0
			ORDER BY
				rif.Data, rif.Numero
			FOR JSON PATH
		)
	) assocRiferimenti
GO
