/*
	Deploy produzione - 2026-09-03 - Conservazione sostitutiva + fix Stampa registro/ConservazioniMax

	Contenuto (solo 4_0_ecomatico - le colonne ConservazioniMax (tblDomini) e ConservazioneSostitutiva
	(tblRifiutiRegistri) sono gia' presenti in produzione, confermato dall'utente):

	1) Fix viewRentriRegistrazioniStampa: ClassiPericolo delimitato da spazio (non ';', errore nel
	   primo deploy di questa vista) - allineato a 3_1_ecomatico..viewRentriRegistrazioniStampa.

	2) uspDomini_get/_upd/_ins: propaga tblDomini.ConservazioniMax (stesso pattern di RentriMax).
	   ISNULL(ConservazioniMax, 0) in _get - tutti i domini hanno la colonna NULL finche' non
	   salvata almeno una volta da uspDomini_upd, altrimenti Dapper lancia eccezione mappando
	   su Dominio.ConservazioniMax (int non nullable).

	3) uspRentriRegistri_get/_upd: nuova sezione Conservazione sostitutiva (4 campi gia' presenti
	   su tblRifiutiRegistri, stesso Id di tblRentriRegistri - nessun join aggiuntivo). In _upd:
	   limite per Dominio su tblDomini.ConservazioniMax (record corrente escluso dal conteggio),
	   e lo scollegamento esplicito (@Scollega=1) azzera anche la conservazione sostitutiva.

	Tutte le SP sono CREATE OR ALTER (idempotenti, nessun DROP/rebuild tabella necessario).
	Testato con dati reali su dev: round-trip salvataggio/lettura, blocco su ConservazioniMax
	raggiunto, azzeramento su scollega. Ordine di deploy sotto irrilevante (nessuna dipendenza
	tra gli oggetti in questo bundle).
*/
-- ============================================================
-- viewRentriRegistrazioniStampa.sql
-- ============================================================
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


-- ============================================================
-- uspDomini_get.sql
-- ============================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDomini_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controllo permesso: solo Admin di dominio Master
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSessioni e
			INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
			INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
			WHERE
				e.Id = @IdSessione
				AND d.[Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Dominio non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			Id,
			Nome = ISNULL(Nome, ''),
			Riferimento = ISNULL(Riferimento, ''),
			Registrazione,
			Scadenza,
			ScadenzaAuto,
			UtentiMax,
			AziendeMax,
			SediMax,
			RegistriMax,
			MagazziniMax,
			ServiziMax,
			RentriMax,
			ConservazioniMax = ISNULL(ConservazioniMax, 0),
			Demo,
			Logo,
			Codice = LOWER(ISNULL(Codice, RIGHT(CONVERT(VARCHAR(36), NEWID()), 5))),
			[Url] = ISNULL([Url], ''),
			Lock
		FROM
			dbo.tblDomini
		WHERE Id = @Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;


-- ============================================================
-- uspDomini_upd.sql
-- ============================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDomini_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdStato CHAR(2) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Riferimento VARCHAR(50) = NULL,
	@Scadenza DATE = NULL,
	@ScadenzaAuto BIT = 1,
	@UtentiMax INT = 1,
	@AziendeMax INT = 1,
	@SediMax INT = 1,
	@RegistriMax INT = 0,
	@MagazziniMax INT = 0,
	@ServiziMax INT = 0,
	@RentriMax INT = 0,
	@ConservazioniMax INT = 0,
	@Demo BIT = 0,
	@Codice CHAR(5) = NULL,
	@NoLogo BIT = 0,
	@Url VARCHAR(200) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	DECLARE @returnValue INT = 0;
	DECLARE @returnMessage NVARCHAR(200) = NULL;
	DECLARE @primaAttivazione BIT = 0;
	DECLARE @returnIdUtente CHAR(16) = NULL;
	DECLARE @returnIdSede CHAR(16) = NULL;
	DECLARE @returnIdIndirizzo CHAR(16) = NULL;

	BEGIN TRY

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdStato = NULLIF(LTRIM(RTRIM(@IdStato)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdStato IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdStato non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSessioni e
			INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
			INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
			WHERE
				e.Id = @IdSessione
				AND d.[Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblDominiStati
		WHERE Id = @IdStato)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Stato dominio non valido';
			GOTO BRANCH_END;
		END

		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Riferimento = dbo.ufnStringhe_get_SenzaSpazi(@Riferimento, 0, 1);
		SET @Url = dbo.ufnStringhe_get_SenzaSpazi(@Url, 0, 1);
		SET @Codice = NULLIF(LTRIM(RTRIM(@Codice)), '');

		IF @Nome IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblDomini
			WHERE
				Id <> @Id
				AND Nome = @Nome
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non possono esistere 2 domini con lo stesso nome';
			GOTO BRANCH_END;
		END

		IF @Codice IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblDomini
			WHERE
				Id <> @Id
				AND Codice = @Codice
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non possono esistere 2 domini con lo stesso codice';
			GOTO BRANCH_END;
		END

		IF EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE
			Id = @Id
			AND Lock = 2
		)
			SET @primaAttivazione = 1;

		IF @primaAttivazione = 1
		BEGIN
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnIdUtente OUTPUT;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnIdSede OUTPUT;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnIdIndirizzo OUTPUT;
		END

		BEGIN TRANSACTION;

			IF @primaAttivazione = 1
			BEGIN
				INSERT INTO dbo.tblUtenti
					(Id, IdDominio, IdRuolo, IdStato, Email, Scadenza, [Master],
					 PasswordScadenzaGiorni, PasswordLunghezzaMinima,
					 PasswordPrecedenti, Lock)
				VALUES
					(@returnIdUtente, @Id, 'AD', 'AT',
					 RTRIM(@Id) + '@ecomatico.it',
					 '20501231',
					 1, 0, 8, 0, 0);

				INSERT INTO dbo.tblUtentiPassword (Id, [Password], [Data])
				SELECT @returnIdUtente, p.[Password], GETDATE()
				FROM dbo.tblUtentiPassword p
				INNER JOIN dbo.tblSessioni e ON p.Id = e.IdUtente
				WHERE e.Id = @IdSessione;

				INSERT INTO dbo.tblUtentiDefault (Id)
				VALUES (@returnIdUtente);

				INSERT INTO dbo.tblSedi
					(Id, IdParent, IdAziendaInterna, InternaEsterna, IdTipo,
					 Disabilitata, Nome, CodiceFiscale, PartitaIva,
					 NomeCompleto, Lock)
				VALUES
					(@returnIdSede, NULL, @returnIdSede, 'I', 'L',
					 0, '(Da indicare)', '00000000000', '00000000000',
					 '(Da indicare)', 0);

				INSERT INTO dbo.tblSediInterne (Id, IdDominio)
				VALUES (@returnIdSede, @Id);

				INSERT INTO dbo.tblIndirizzi
					(Id, Indirizzo, CAP, Localita, IdComune, IdNazione)
				VALUES
					(@returnIdIndirizzo,
					 '(Indicare la via e numero civico)',
					 '20100', NULL, '015146', '380');

				INSERT INTO dbo.tblSediIndirizzi (Id, IdIndirizzo)
				VALUES (@returnIdSede, @returnIdIndirizzo);

				INSERT INTO dbo.tblDominiModuli (Id, IdModulo)
				SELECT @Id, Id
				FROM dbo.tblModuli
				WHERE Id IN ('BAS', 'IMP');
			END

			DELETE f
			FROM dbo.tblUtentiFunzioni f
			INNER JOIN dbo.tblUtenti u ON f.Id = u.Id
			WHERE
				u.IdDominio = @Id
				AND f.IdFunzione NOT IN ( SELECT mf.IdFunzione FROM dbo.tblModuliFunzioni mf INNER JOIN dbo.tblDominiModuli dm ON mf.Id = dm.IdModulo WHERE dm.Id = @Id );

			UPDATE dbo.tblDomini
			SET
				Lock = 0,
				IdStato = @IdStato,
				Nome = ISNULL(@Nome, Nome),
				Riferimento = ISNULL(@Riferimento, Riferimento),
				Scadenza = ISNULL(@Scadenza, Scadenza),
				ScadenzaAuto = @ScadenzaAuto,
				UtentiMax = @UtentiMax,
				AziendeMax = @AziendeMax,
				SediMax = @SediMax,
				RegistriMax = @RegistriMax,
				MagazziniMax = @MagazziniMax,
				ServiziMax = @ServiziMax,
				RentriMax = @RentriMax,
				ConservazioniMax = @ConservazioniMax,
				Demo = @Demo,
				Codice = ISNULL(@Codice, Codice),
				Logo = IIF(@NoLogo = 1, NULL, Logo),
				[Url] = ISNULL(@Url, [Url])
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Dominio non trovato o già eliminato';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;


-- ============================================================
-- uspDomini_ins.sql
-- ============================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDomini_ins]
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @returnId CHAR(16) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSessioni e
			INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
			INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
			WHERE
				e.Id = @IdSessione
				AND d.[Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT INTO dbo.tblDomini
				(Id, IdStato, [Master], Registrazione, Scadenza, ScadenzaAuto,
				 UtentiMax, AziendeMax, SediMax, RegistriMax, MagazziniMax, ServiziMax, RentriMax, ConservazioniMax, Demo, Lock)
			VALUES (
				@returnId,
				'AT',
				0,
				GETDATE(),
				DATEADD(YEAR, 1, EOMONTH(GETDATE())),
				1,
				1, 1, 1,
				0, 0, 0, 0, 0,
				0,
				2
			);
		COMMIT TRANSACTION;

		SELECT @returnId AS Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;


-- ============================================================
-- uspRentriRegistri_get.sql
-- ============================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistri_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistri WHERE Id = @Id AND Lock = 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registro non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			g.Id,
			g.Nome,
			g.IdSede,
			SedeNome = s.NomeCompleto,
			s.IndirizzoCompleto,
			Identificativo = h.Identificativo,
			BloccoFormulari = h.BloccoFormulari,
			DataInizioInvio = h.DataInizioInvio,
			IsCollegato = CAST(IIF(r.IdRentri IS NULL, 0, 1) AS BIT),
			ConservazioneSostitutiva = ISNULL(g.ConservazioneSostitutiva, 0),
			ConservazioneSostitutivaRagioneSociale = ISNULL(g.ConservazioneSostitutivaRagioneSociale, ''),
			ConservazioneSostitutivaPartitaIva = ISNULL(g.ConservazioneSostitutivaPartitaIva, ''),
			ConservazioneSostitutivaEmail = ISNULL(g.ConservazioneSostitutivaEmail, '')
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			LEFT JOIN dbo.tblRentriRegistri r ON g.Id = r.Id
			LEFT JOIN [1_0_rentri]..tblRegistri h ON r.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
		WHERE g.Id = @Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO


-- ============================================================
-- uspRentriRegistri_upd.sql
-- ============================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistri_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Scollega BIT = 0,
	@Identificativo VARCHAR(20) = NULL,
	@BloccoFormulari VARCHAR(10) = NULL,
	@DataInizioInvio DATE = NULL,
	@ConservazioneSostitutiva BIT = 0,
	@ConservazioneSostitutivaRagioneSociale VARCHAR(50) = NULL,
	@ConservazioneSostitutivaPartitaIva VARCHAR(20) = NULL,
	@ConservazioneSostitutivaEmail VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Scollega = ISNULL(@Scollega, 0);
		SET @Identificativo = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Identificativo, 0, 1));
		SET @BloccoFormulari = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@BloccoFormulari, 0, 1));
		SET @ConservazioneSostitutiva = ISNULL(@ConservazioneSostitutiva, 0);
		SET @ConservazioneSostitutivaRagioneSociale = dbo.ufnStringhe_get_SenzaSpazi(@ConservazioneSostitutivaRagioneSociale, 0, 1);
		SET @ConservazioneSostitutivaPartitaIva = dbo.ufnStringhe_get_SenzaSpazi(@ConservazioneSostitutivaPartitaIva, 0, 1);
		SET @ConservazioneSostitutivaEmail = dbo.ufnStringhe_get_SenzaSpazi(@ConservazioneSostitutivaEmail, 0, 1);

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede del registro
		DECLARE @idSede CHAR(16);
		SELECT @idSede = g.IdSede
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			g.Id = @Id
			AND g.Lock = 0;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idRentri CHAR(16);
		SELECT @idRentri = IdRentri
		FROM dbo.tblRentriRegistri
		WHERE Id = @Id;

		-- Scollegamento esplicito: la conservazione sostitutiva non ha senso su un registro non
		-- collegato a RENTRI, azzerata insieme allo scollegamento (libera anche il posto nel
		-- conteggio ConservazioniMax del Dominio)
		IF @Scollega = 1
		BEGIN
			BEGIN TRANSACTION;
				IF @idRentri IS NOT NULL
				BEGIN
					DELETE dbo.tblRentriRegistri WHERE Id = @Id;
					DELETE [1_0_rentri]..tblRegistri WHERE Id = @idRentri;
				END

				UPDATE dbo.tblRifiutiRegistri
				SET
					ConservazioneSostitutiva = 0,
					ConservazioneSostitutivaRagioneSociale = NULL,
					ConservazioneSostitutivaPartitaIva = NULL,
					ConservazioneSostitutivaEmail = NULL
				WHERE Id = @Id;
			COMMIT TRANSACTION;
			SELECT ReturnValue = @returnValue;
			GOTO BRANCH_END;
		END

		-- Il registro non ha una propria credenziale: eredita sempre la Primaria (Pos=0) della Sede su cui si appoggia
		DECLARE @idRentriSede CHAR(16);
		SELECT @idRentriSede = IdRentri
		FROM dbo.tblRentriCredenzialiSedi
		WHERE
			IdSede = @idSede
			AND Pos = 0;

		IF @idRentriSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede non ha ancora una credenziale primaria collegata a RENTRI';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista già un altro registro con lo stesso identificativo
		IF @Identificativo IS NOT NULL AND EXISTS (
			SELECT 1
			FROM
				dbo.tblRentriRegistri r
				INNER JOIN [1_0_rentri]..tblRegistri h ON r.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
			WHERE
				r.Id <> @Id
				AND h.Identificativo = @Identificativo
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro registro con lo stesso identificativo è già presente';
			GOTO BRANCH_END;
		END

		-- Limite di registri con conservazione sostitutiva abilitata per Dominio (tblDomini.ConservazioniMax);
		-- @Id escluso dal conteggio: se già abilitata su questo stesso registro non va contata come "nuova"
		IF @ConservazioneSostitutiva = 1
		BEGIN
			DECLARE @idDominio CHAR(16);
			SELECT @idDominio = IdDominio FROM dbo.tblSessioni WHERE Id = @IdSessione;

			IF ISNULL((SELECT ConservazioniMax FROM dbo.tblDomini WHERE Id = @idDominio), 0)
				<=
				(SELECT COUNT(*)
				 FROM
					 dbo.tblRifiutiRegistri r
					 INNER JOIN dbo.tblSediInterne i ON r.IdSede = i.Id
				 WHERE
					 i.IdDominio = @idDominio
					 AND r.ConservazioneSostitutiva = 1
					 AND r.Lock = 0
					 AND r.Id <> @Id
				)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'È stato raggiunto il numero massimo di registri con conservazione sostitutiva abilitata';
				GOTO BRANCH_END;
			END
		END

		BEGIN TRANSACTION;
			IF @idRentri IS NULL
			BEGIN
				SET @idRentri = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));
				INSERT INTO [1_0_rentri]..tblRegistri (Id, IdSede, Identificativo, BloccoFormulari, DataInizioInvio)
				VALUES (@idRentri, @idRentriSede, @Identificativo, @BloccoFormulari, @DataInizioInvio);

				INSERT INTO dbo.tblRentriRegistri (Id, IdRentri)
				VALUES (@Id, @idRentri);
			END
			ELSE
			BEGIN
				UPDATE [1_0_rentri]..tblRegistri
				SET
					IdSede = @idRentriSede,
					Identificativo = @Identificativo,
					BloccoFormulari = @BloccoFormulari,
					DataInizioInvio = @DataInizioInvio
				WHERE Id = @idRentri;
			END

			UPDATE dbo.tblRifiutiRegistri
			SET
				ConservazioneSostitutiva = @ConservazioneSostitutiva,
				ConservazioneSostitutivaRagioneSociale = @ConservazioneSostitutivaRagioneSociale,
				ConservazioneSostitutivaPartitaIva = @ConservazioneSostitutivaPartitaIva,
				ConservazioneSostitutivaEmail = @ConservazioneSostitutivaEmail
			WHERE Id = @Id;
		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO


