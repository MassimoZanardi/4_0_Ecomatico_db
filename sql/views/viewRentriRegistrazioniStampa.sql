SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Vista di supporto per la stampa PDF del registro (uspRegistrazioni_get_Stampa_List, branch @App='40',
-- DB 1_0_rentri), analoga a viewRentriRegistrazioni (usata per l'invio) ma con proiezione e regole di
-- soppressione per-causale specifiche per il report stampato, allineate al branch gemello @App='31'
-- (3_1_ecomatico..viewRentriRegistrazioniStampa + le IIF/CASE della SP, ispezionate live il 2026-09-03).
-- A differenza di viewRentriRegistrazioni: qui la soppressione per causale/rettifica-annullata e' gia'
-- incorporata nella vista (non nella SP, che resta un passthrough di sola formattazione FORMAT/IIF-'X',
-- stesso principio del branch @App='40' di uspRegistrazioni_get_List) - i valori NULL prodotti qui sono
-- voluti (campo non applicabile a quella causale/tipo di registrazione), non un gap.
--
-- Mappatura causali 3_1 (IDCausale) -> codice RENTRI reale (o.Codice, dominio chiuso: aT/DT/I/M/NP/RE/SI/
-- T*/T*aT/TR), derivata da dbo.tblRifiutiMovimentiCausali.RentriCodice (3_1_ecomatico) per ciascun gruppo
-- usato dalla SP 3_1 uspRegistrazioni_get_Stampa_List:
--   Provenienza                         : CSF/CSM/CST/CSX/TRD -> {T*aT, TR}      (identico a viewRentriRegistrazioni)
--   Esito/DataEsito/QuantitaDestino     : STT/STP/CST/CSX/CSM -> {aT, T*aT}      (= tblRifiutiOperazioni.IsEsito, verificato riga per riga)
--   FormularioDataInizioTrasporto       : STT/STP/CST/CSX/TRD -> {aT, T*aT, TR}
--   Produttore/Trasportatore            : CPT/CTT/TRD         -> {T*, TR}
--   Destinatario                        : TRD                 -> {TR}
--   Intermediario                       : CPT/CTT (Interm.1) + TRD (Interm.2) -> {T*, TR} (un solo slot
--                                          Intermediario in questo schema, nessuna distinzione 1/2 - vedi
--                                          viewRentriRegistrazioni)
-- StoccaggioIstantaneoData              : IDCausale='SIS' -> o.Codice='SI' (mapping 1:1 diretto)
--
-- Nomi soggetti (Produttore/Trasportatore/Destinatario/Intermediario) e ISO 3166 non gestiti qui: riuso
-- diretto di tblSedi.NomeCompleto/CodiceFiscale/PartitaIva, stessi campi gia' verificati/in uso da
-- viewRentriRegistrazioni (nessun fallback su sede padre necessario in questo schema).
CREATE OR ALTER VIEW [dbo].[viewRentriRegistrazioniStampa]
AS
SELECT
    IDRegistro                     = g.Id,
    IDRentri                       = z.IdRentri,
    IdRegistrazione                = r.Id,
    RentriIdentificativo           = r.RentriIdentificativo,

    Numero                          = r.Numero,
    Anno                            = YEAR(r.Data),
    Data                            = r.Data,

    RettificaNumero                 = ro.Numero,
    RettificaAnno                   = YEAR(ro.Data),
    RettificaData                   = ro.Data,
    RettificaIsAnnullata            = CAST(ISNULL(rett.Annullata, 0) AS BIT),

    StoccaggioIstantaneoData        = CASE WHEN o.Codice = 'SI' AND ISNULL(rett.Annullata, 0) = 0 THEN r.Data ELSE NULL END,

    Operazione                      = CASE WHEN ISNULL(rett.Annullata, 0) = 0 THEN o.Codice ELSE NULL END,

    -- Eer = codice esteso con separatori (equivalente a 3_1_ecomatico..tblRifiutiCER.CodiceEsteso),
    -- con marcatore '*' per i codici pericolosi - non il codice RENTRI grezzo usato da viewRentriRegistrazioni
    Eer                              = CASE WHEN ISNULL(rett.Annullata, 0) = 0 THEN eer.Nome + IIF(eer.Pericoloso = 1, '*', '') ELSE NULL END,
    EerDescrizione                   = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND m.IdEer LIKE '%99' THEN ISNULL(m.EerDescrizione, eer.Descrizione) ELSE NULL END,

    StatoFisico                      = CASE WHEN ISNULL(rett.Annullata, 0) = 0 THEN sf.Codice ELSE NULL END,

    Provenienza                      = CASE
        WHEN ISNULL(rett.Annullata, 0) = 1 THEN NULL
        WHEN o.Codice IN ('T*aT', 'TR') THEN NULL
        ELSE ISNULL(m.IdProvenienza, 'S')
    END,

    Quantita                         = CASE WHEN ISNULL(rett.Annullata, 0) = 0 THEN m.Quantita ELSE NULL END,
    UnitaMisura                      = CASE WHEN ISNULL(rett.Annullata, 0) = 0 THEN LOWER(um.Codice) ELSE NULL END,
    ClassiPericolo                   = CASE WHEN ISNULL(rett.Annullata, 0) = 0 THEN cp.ClassiPericolo ELSE NULL END,

    VeicoloFuoriUso                  = CASE WHEN ISNULL(rett.Annullata, 0) = 1 THEN NULL ELSE ISNULL(r.VeicoloFuoriUso, 0) END,
    VeicoloFuoriUsoNumero            = CASE WHEN ISNULL(rett.Annullata, 0) = 1 THEN NULL ELSE r.VeicoloFuoriUsoNumero END,
    VeicoloFuoriUsoData              = CASE WHEN ISNULL(rett.Annullata, 0) = 1 THEN NULL ELSE r.VeicoloFuoriUsoData END,

    CategorieAee                     = CASE WHEN ISNULL(rett.Annullata, 0) = 0 THEN raee.Codice ELSE NULL END,

    -- 'A' -> 'Altro' (mat.Nome), stessa resa testuale di 3_1 (li' hardcoded in SP, qui via lookup)
    MaterialeSecondario              = CASE
        WHEN ISNULL(rett.Annullata, 0) = 1 THEN NULL
        WHEN mat.Codice = 'A' THEN mat.Nome
        ELSE mat.Codice
    END,
    MaterialeSecondarioDescrizione   = CASE WHEN ISNULL(rett.Annullata, 0) = 0 THEN r.MaterialeDescrizione ELSE NULL END,

    Esito                            = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice IN ('aT', 'T*aT') THEN ISNULL(es.Codice, 'A') ELSE NULL END,
    DataEsito                        = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice IN ('aT', 'T*aT') THEN r.DataFineTrasporto ELSE NULL END,
    QuantitaDestino                  = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice IN ('aT', 'T*aT') THEN ISNULL(r.QuantitaVerificata, m.Quantita) ELSE NULL END,

    EsitoCausaleRespingimento        = CASE
        WHEN ISNULL(rett.Annullata, 0) = 1 THEN NULL
        WHEN ISNULL(es.Codice, 'A') = 'A' THEN NULL
        ELSE ISNULL(ecr.Codice, 'NC')
    END,
    RespingimentoMotivo              = CASE
        WHEN ISNULL(rett.Annullata, 0) = 1 THEN NULL
        WHEN ISNULL(es.Codice, 'A') = 'A' THEN NULL
        ELSE ISNULL(r.CausaleRespingimentoAltro, 'Non conforme')
    END,
    -- Non gated da RettificaIsAnnullata/causale: replica fedele di 3_1 (unico campo del gruppo Esito
    -- senza IIF nella SP originale, verificato live) - possibile incoerenza preesistente in 3_1, non
    -- "corretta" qui per restare fedeli al comportamento di riferimento.
    RespingimentoQuantita            = ISNULL(r.QuantitaRespinta, m.Quantita),

    Destinazione                     = CASE WHEN ISNULL(rett.Annullata, 0) = 0 THEN attv.Codice ELSE NULL END,

    RegistrazioniAssociate           = CASE
        WHEN ISNULL(rett.Annullata, 0) = 1 THEN NULL
        WHEN o.Operazione = 'S' OR o.Codice = 'M' THEN assocRiferimentiTxt.Registrazioni
        ELSE NULL
    END,

    FormularioNumero                 = CASE WHEN ISNULL(rett.Annullata, 0) = 0 THEN m.FormularioNumero ELSE NULL END,
    FormularioDataInizioTrasporto    = CASE
        WHEN ISNULL(rett.Annullata, 0) = 1 THEN NULL
        WHEN o.Codice IN ('aT', 'T*aT', 'TR') THEN m.DataInizioTrasporto
        ELSE NULL
    END,

    Transfrontaliero                 = CASE WHEN ISNULL(rett.Annullata, 0) = 1 THEN NULL ELSE CAST(IIF(r.IdTrasportoTransfrontalieroTipo IS NOT NULL, 1, 0) AS BIT) END,
    -- tt.Nome e' gia' l'etichetta testuale ("Allegato VII"/"Allegato I-B"), stessa resa di 3_1 (li' hardcoded in SP)
    TransfrontalieroTipo             = CASE WHEN ISNULL(rett.Annullata, 0) = 0 THEN tt.Nome ELSE NULL END,

    ProduttoreNome                   = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice IN ('T*', 'TR') THEN sp.NomeCompleto ELSE NULL END,
    ProduttoreCodiceFiscale          = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice IN ('T*', 'TR') THEN ISNULL(sp.CodiceFiscale, sp.PartitaIva) ELSE NULL END,
    ProduttoreIndirizzo              = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice IN ('T*', 'TR') THEN ip.Indirizzo + ISNULL(', ' + ip.CAP + ' ' + ip.Localita, '') ELSE NULL END,

    TrasportatoreNome                = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice IN ('T*', 'TR') THEN st.NomeCompleto ELSE NULL END,
    TrasportatoreCodiceFiscale       = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice IN ('T*', 'TR') THEN ISNULL(st.CodiceFiscale, st.PartitaIva) ELSE NULL END,
    TrasportatoreAutorizzazione      = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice IN ('T*', 'TR') THEN at.Numero ELSE NULL END,

    DestinatarioNome                 = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice = 'TR' THEN sd.NomeCompleto ELSE NULL END,
    DestinatarioCodiceFiscale        = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice = 'TR' THEN ISNULL(sd.CodiceFiscale, sd.PartitaIva) ELSE NULL END,
    DestinatarioAutorizzazione       = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice = 'TR' THEN ad.Numero ELSE NULL END,

    IntermediarioNome                = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice IN ('T*', 'TR') THEN si.NomeCompleto ELSE NULL END,
    IntermediarioCodiceFiscale       = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice IN ('T*', 'TR') THEN ISNULL(si.CodiceFiscale, si.PartitaIva) ELSE NULL END,
    IntermediarioAutorizzazione      = CASE WHEN ISNULL(rett.Annullata, 0) = 0 AND o.Codice IN ('T*', 'TR') THEN ai.Numero ELSE NULL END,

    Note                              = LEFT(r.Note, 500),

    Lock                              = r.Lock
FROM
    dbo.tblRifiutiRegistrazioni                        r
    INNER JOIN dbo.tblRifiutiMovimenti                 m    ON r.IdMovimento               = m.Id
    INNER JOIN dbo.tblRifiutiRegistri                  g    ON m.IdRegistro                = g.Id
    LEFT  JOIN dbo.tblRentriRegistri                   z    ON g.Id                        = z.Id
    LEFT  JOIN dbo.tblRifiutiOperazioni                o    ON m.IdOperazione              = o.Id
    LEFT  JOIN dbo.tblRifiutiEer                       eer  ON m.IdEer                     = eer.Id
    LEFT  JOIN dbo.tblRifiutiStatiFisici               sf   ON m.IdStatoFisico             = sf.Id
    LEFT  JOIN dbo.tblUnitaMisura                      um   ON m.IdUnitaMisura             = um.Id
    LEFT  JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento attv ON m.IdAttivita              = attv.Id
    LEFT  JOIN dbo.tblRifiutiRaee                      raee ON r.IdRaee                    = raee.Id
    LEFT  JOIN dbo.tblRifiutiMateriali                 mat  ON r.IdMateriale               = mat.Id
    LEFT  JOIN dbo.tblRifiutiRegistrazioniEsiti        es   ON r.IdEsito                   = es.Id
    LEFT  JOIN dbo.tblRifiutiRegistrazioniEsitiCausaliRespingimento ecr ON r.IdCausaleRespingimento = ecr.Id
    LEFT  JOIN dbo.tblRifiutiTrasportiTransfrontalieriTipi tt ON r.IdTrasportoTransfrontalieroTipo = tt.Id
    LEFT  JOIN dbo.tblRentriRegistrazioniRettifiche    rett ON r.Id                        = rett.IdRettifica
    LEFT  JOIN dbo.tblRifiutiRegistrazioni             ro   ON rett.Id                     = ro.Id

    LEFT  JOIN dbo.tblSedi                             sp   ON m.IdSedeProduttoreDetentore = sp.Id
    LEFT  JOIN dbo.tblSediIndirizzi                    sip  ON sp.Id                       = sip.Id
    LEFT  JOIN dbo.tblIndirizzi                        ip   ON sip.IdIndirizzo             = ip.Id

    LEFT  JOIN dbo.tblSedi                             st   ON m.IdSedeTrasportatore1      = st.Id
    LEFT  JOIN dbo.tblRifiutiMovimentiTrasportatori    mt   ON m.Id                        = mt.Id AND mt.Pos = 0
    LEFT  JOIN dbo.tblRifiutiAutorizzazioni            at   ON mt.IdAutorizzazione         = at.Id

    LEFT  JOIN dbo.tblSedi                             sd   ON m.IdSedeDestinatario        = sd.Id
    LEFT  JOIN dbo.tblRifiutiMovimentiDestinatari      md   ON m.Id                        = md.Id AND md.Pos = 0
    LEFT  JOIN dbo.tblRifiutiAutorizzazioni            ad   ON md.IdAutorizzazione         = ad.Id

    LEFT  JOIN dbo.tblSedi                             si   ON m.IdSedeIntermediario1      = si.Id
    LEFT  JOIN dbo.tblRifiutiMovimentiIntermediari     mi   ON m.Id                        = mi.Id AND mi.Pos = 0
    LEFT  JOIN dbo.tblRifiutiAutorizzazioni            ai   ON mi.IdAutorizzazione         = ai.Id

    LEFT JOIN (
        SELECT
            mc.Id,
            -- Spazio come delimitatore (non ';' come in viewRentriRegistrazioni): stessa resa di
            -- 3_1_ecomatico..viewRentriRegistrazioniStampa (STRING_AGG('HP'+IDClasse, ' ')), qui senza
            -- concatenare 'HP' perche' c.Codice lo include gia' (verificato su dbo.tblRifiutiClassiPericolo)
            ClassiPericolo = STRING_AGG(c.Codice, ' ') WITHIN GROUP (ORDER BY c.Codice)
        FROM
            dbo.tblRifiutiMovimentiClassiPericolo mc
            LEFT JOIN dbo.tblRifiutiClassiPericolo c ON mc.IdClasse = c.Id
        GROUP BY
            mc.Id
    ) cp ON m.Id = cp.Id

    OUTER APPLY (
        -- Testo leggibile "anno/numero anno/numero ...", stesso universo di righe (rl.IdParent = r.Id)
        -- gia' verificato empiricamente in viewRentriRegistrazioni, qui in formato stampa anziche' JSON
        SELECT Registrazioni = (
            SELECT STRING_AGG(CAST(YEAR(rif.Data) AS VARCHAR(4)) + '/' + CAST(rif.Numero AS VARCHAR(6)), ' ') WITHIN GROUP (ORDER BY rif.Data, rif.Numero)
            FROM
                dbo.tblRifiutiRegistrazioniRelazioni rl
                INNER JOIN dbo.tblRifiutiRegistrazioni rif ON rl.Id = rif.Id
            WHERE
                rl.IdParent = r.Id
                AND rif.Lock = 0
        )
    ) assocRiferimentiTxt
GO
