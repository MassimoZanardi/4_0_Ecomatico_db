SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Vista consumata dall'hub condiviso 1_0_rentri (branch @App='40' di uspRegistrazioni_get_List/uspRegistrazioni_upd_ByRegistrazioni),
-- referenziata letteralmente come [4_0_ecomatico]..viewRentriRegistrazioni: nome e insieme di colonne NON sono
-- rinominabili/estendibili senza coordinarsi con l'hub. Colonne allineate alla versione più aggiornata (produzione)
-- del branch gemello @App='31' (3_1_ecomatico..viewRentriRegistrazioni, fornita dall'utente il 2026-09-01) - stesso
-- sottoinsieme, non di più. Hanno un equivalente reale in questo schema e sono implementate: ClassiPericolo
-- (tblRifiutiMovimentiClassiPericolo), RegistrazioniAssociate (tblRifiutiRegistrazioniRelazioni, Id=figlio/scarico,
-- IdParent=padre/carico), MaterialeSecondarioDescrizione (tblRifiutiRegistrazioni.MaterialeDescrizione),
-- EsitoCausaleRespingimento/RespingimentoMotivo/RespingimentoQuantita (IdCausaleRespingimento/
-- CausaleRespingimentoAltro/QuantitaRespinta), TransfrontalieroTipo (IdTrasportoTransfrontalieroTipo). Restano
-- invece a NULL/0 (nessun concetto equivalente, l'hub li gestisce già con ISNULL/CASE lato C#): rettifica/
-- annullamento di una registrazione precedente (RettificaNumero/RettificaAnno/RettificaIdentificativo/
-- RettificaIsAnnullata - nessuna tabella tblRentriRegistrazioniRettifiche o simile in questo schema) e il secondo
-- Intermediario (Intermediario2* lato 31 - qui tblRifiutiMovimenti ha solo IdSedeIntermediario1, nessun supporto
-- multi-intermediario su Registrazioni). La logica di Provenienza=NULL per le operazioni di Trasporto/
-- Intermediazione (equivalente delle causali CSF/CSM/CST/CSX/TRD di 3_1) è replicata filtrando su
-- tblRifiutiOperazioni.Codice ('T*aT'/'TR', i codici RENTRI reali - non su Operazione CHAR(1), che è solo una
-- classificazione interna C/S/X senza mappatura univoca verso le causali di 3_1), confermato dall'utente.
CREATE OR ALTER VIEW [dbo].[viewRentriRegistrazioni]
AS
SELECT
    IDRegistro                  = g.Id,
    IDRentri                    = z.IdRentri,

    IdRegistrazione             = r.Id,
    RentriIdentificativo        = r.RentriIdentificativo,
    Numero                      = r.Numero,
    Anno                        = YEAR(r.Data),

    RettificaNumero              = 0,
    RettificaAnno                 = 0,
    RettificaIdentificativo      = CAST(NULL AS VARCHAR(50)),
    RettificaIsAnnullata          = CAST(0 AS BIT),

    Data                         = r.Data,
    Operazione                   = r.Operazione,

    Eer                          = m.IdEer,
    EerDescrizione               = m.EerDescrizione,
    StatoFisico                  = sf.Codice,
    -- Provenienza non applicabile per operazioni di Trasporto/Intermediazione (equivalente delle
    -- causali CSF/CSM/CST/CSX/TRD di 3_1 - qui filtrate sul codice RENTRI o.Codice, non su Operazione)
    Provenienza                  = CASE WHEN o.Codice IN ('T*aT', 'TR') THEN NULL ELSE ISNULL(m.IdProvenienza, 'S') END,

    -- CAST a FLOAT: Registrazione.Quantita lato hub e' double, Dapper non converte DECIMAL->double/long
    -- automaticamente (InvalidCastException in unboxing) - stesso motivo per QuantitaDestino/RespingimentoQuantita sotto.
    Quantita                     = CAST(m.Quantita AS FLOAT),
    UnitaMisura                  = LOWER(um.Codice),
    ClassiPericolo               = cp.ClassiPericolo,

    VeicoloFuoriUso               = ISNULL(r.VeicoloFuoriUso, 0),
    VeicoloFuoriUsoNumero        = r.VeicoloFuoriUsoNumero,
    -- Non NULL: il modello C# lato hub (Registrazione.VeicoloFuoriUsoData) e' un DateTime non nullable,
    -- Dapper lancia un'eccezione non gestita (500 generico) se la colonna arriva NULL. Il valore e'
    -- comunque irrilevante quando VeicoloFuoriUso=0 (non inviato/non consumato dall'hub in quel caso).
    VeicoloFuoriUsoData          = ISNULL(r.VeicoloFuoriUsoData, r.Data),

    CategorieAee                 = raee.Codice,

    MaterialeSecondario           = mat.Codice,
    MaterialeSecondarioDescrizione = r.MaterialeDescrizione,

    Esito                        = es.Codice,
    -- Stesso motivo di VeicoloFuoriUsoData: Registrazione.DataEsito e' DateTime non nullable lato hub.
    DataEsito                    = ISNULL(r.DataFineTrasporto, r.Data),
    QuantitaDestino               = CAST(ISNULL(r.QuantitaVerificata, m.Quantita) AS BIGINT),

    EsitoCausaleRespingimento    = CASE WHEN ISNULL(es.Codice, 'A') = 'A' THEN NULL ELSE ISNULL(ecr.Codice, 'NC') END,
    RespingimentoMotivo          = CASE WHEN ISNULL(es.Codice, 'A') = 'A' THEN NULL ELSE ISNULL(r.CausaleRespingimentoAltro, 'Non conforme') END,
    RespingimentoQuantita        = CAST(ISNULL(r.QuantitaRespinta, m.Quantita) AS FLOAT),

    Destinazione                 = attv.Codice,

    RegistrazioniAssociate       = IIF(r.Operazione <> 'M', assocA.Registrazioni, assocB.Registrazioni),

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

    -- Nessun supporto multi-intermediario su Registrazioni in questo schema (solo IdSedeIntermediario1)
    Intermediario2Nome            = CAST(NULL AS VARCHAR(200)),
    Intermediario2CodiceFiscale   = CAST(NULL AS VARCHAR(20)),
    Intermediario2Nazione         = CAST(NULL AS CHAR(2)),
    Intermediario2Autorizzazione  = CAST(NULL AS VARCHAR(20)),

    -- ISNULL su tutti gli Is*: Registrazione lato hub li mappa su bool non nullable, o e' una LEFT JOIN
    IsProduttore                  = ISNULL(o.IsProduttore, 0),
    IsTrasportatore                = ISNULL(o.IsTrasportatore, 0),
    IsDestinatario                 = ISNULL(o.IsDestinatario, 0),
    IsIntermediario                = ISNULL(o.IsIntermediario, 0),
    IsEsito                        = ISNULL(o.IsEsito, 0),
    IsFormulario                   = ISNULL(o.IsFormulario, 0),
    IsTransfrontaliero            = CAST(IIF(r.IdTrasportoTransfrontalieroTipo IS NOT NULL, 1, 0) AS BIT),
    IsStoccaggioIstantaneo        = ISNULL(o.IsStoccaggioIstantaneo, 0),

    Lock                          = r.Lock,

    Note                          = LEFT(r.Note, 500)
FROM
    dbo.tblRifiutiRegistrazioni                        r
    INNER JOIN dbo.tblRifiutiMovimenti                 m    ON r.IdMovimento               = m.Id
    INNER JOIN dbo.tblRifiutiRegistri                  g    ON m.IdRegistro                = g.Id
    LEFT  JOIN dbo.tblRentriRegistri                   z    ON g.Id                        = z.Id
    LEFT  JOIN dbo.tblRifiutiOperazioni                o    ON m.IdOperazione              = o.Id
    LEFT  JOIN dbo.tblRifiutiStatiFisici               sf   ON m.IdStatoFisico             = sf.Id
    LEFT  JOIN dbo.tblUnitaMisura                      um   ON m.IdUnitaMisura             = um.Id
    LEFT  JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento attv ON m.IdAttivita              = attv.Id
    LEFT  JOIN dbo.tblRifiutiRaee                      raee ON r.IdRaee                    = raee.Id
    LEFT  JOIN dbo.tblRifiutiMateriali                 mat  ON r.IdMateriale               = mat.Id
    LEFT  JOIN dbo.tblRifiutiRegistrazioniEsiti        es   ON r.IdEsito                   = es.Id
    LEFT  JOIN dbo.tblRifiutiRegistrazioniEsitiCausaliRespingimento ecr ON r.IdCausaleRespingimento = ecr.Id
    LEFT  JOIN dbo.tblRifiutiTrasportiTransfrontalieriTipi tt ON r.IdTrasportoTransfrontalieroTipo = tt.Id

    LEFT  JOIN dbo.tblSedi                             sp   ON m.IdSedeProduttoreDetentore = sp.Id
    LEFT  JOIN dbo.tblSediIndirizzi                    sip  ON sp.Id                       = sip.Id
    LEFT  JOIN dbo.tblIndirizzi                        ip   ON sip.IdIndirizzo             = ip.Id
    LEFT  JOIN dbo.tblNazioni                          nzp  ON ip.IdNazione                = nzp.Id

    LEFT  JOIN dbo.tblSedi                             st   ON m.IdSedeTrasportatore1      = st.Id
    LEFT  JOIN dbo.tblSediIndirizzi                    sit  ON st.Id                       = sit.Id
    LEFT  JOIN dbo.tblIndirizzi                        it_  ON sit.IdIndirizzo             = it_.Id
    LEFT  JOIN dbo.tblNazioni                          nzt  ON it_.IdNazione               = nzt.Id
    LEFT  JOIN dbo.tblRifiutiMovimentiTrasportatori    mt   ON m.Id                        = mt.Id AND mt.Pos = 0
    LEFT  JOIN dbo.tblRifiutiAutorizzazioni            at   ON mt.IdAutorizzazione         = at.Id

    LEFT  JOIN dbo.tblSedi                             sd   ON m.IdSedeDestinatario        = sd.Id
    LEFT  JOIN dbo.tblSediIndirizzi                    sid  ON sd.Id                       = sid.Id
    LEFT  JOIN dbo.tblIndirizzi                        id_  ON sid.IdIndirizzo             = id_.Id
    LEFT  JOIN dbo.tblNazioni                          nzd  ON id_.IdNazione               = nzd.Id
    LEFT  JOIN dbo.tblRifiutiMovimentiDestinatari      md   ON m.Id                        = md.Id AND md.Pos = 0
    LEFT  JOIN dbo.tblRifiutiAutorizzazioni            ad   ON md.IdAutorizzazione         = ad.Id

    LEFT  JOIN dbo.tblSedi                             si   ON m.IdSedeIntermediario1      = si.Id
    LEFT  JOIN dbo.tblSediIndirizzi                    sii  ON si.Id                       = sii.Id
    LEFT  JOIN dbo.tblIndirizzi                        ii_  ON sii.IdIndirizzo             = ii_.Id
    LEFT  JOIN dbo.tblNazioni                          nzi  ON ii_.IdNazione               = nzi.Id
    LEFT  JOIN dbo.tblRifiutiMovimentiIntermediari     mi   ON m.Id                        = mi.Id AND mi.Pos = 0
    LEFT  JOIN dbo.tblRifiutiAutorizzazioni            ai   ON mi.IdAutorizzazione         = ai.Id

    LEFT JOIN (
        SELECT
            mc.Id,
            ClassiPericolo = STRING_AGG(c.Codice, ';') WITHIN GROUP (ORDER BY c.Codice)
        FROM
            dbo.tblRifiutiMovimentiClassiPericolo mc
            LEFT JOIN dbo.tblRifiutiClassiPericolo c ON mc.IdClasse = c.Id
        GROUP BY
            mc.Id
    ) cp ON m.Id = cp.Id

    OUTER APPLY (
        -- Registrazioni "carico" (padre) da cui questa registrazione (scarico/figlio) ha attinto
        SELECT Registrazioni = (
            SELECT
                progressivo = rp.Numero,
                anno = YEAR(rp.Data)
            FROM
                dbo.tblRifiutiRegistrazioniRelazioni rl
                INNER JOIN dbo.tblRifiutiRegistrazioni rp ON rl.IdParent = rp.Id
            WHERE
                rl.Id = r.Id
                AND rl.Quantita > 0
                AND rp.Lock = 0
            ORDER BY
                rp.Data, rp.Numero
            FOR JSON PATH
        )
    ) assocA
    OUTER APPLY (
        -- Registrazioni "scarico" (figlie) che hanno attinto da questa registrazione (carico/padre)
        SELECT Registrazioni = (
            SELECT
                progressivo = rc.Numero,
                anno = YEAR(rc.Data)
            FROM
                dbo.tblRifiutiRegistrazioniRelazioni rl
                INNER JOIN dbo.tblRifiutiRegistrazioni rc ON rl.Id = rc.Id
            WHERE
                rl.IdParent = r.Id
                AND rc.Lock = 0
            ORDER BY
                rc.Data, rc.Numero
            FOR JSON PATH
        )
    ) assocB
GO
