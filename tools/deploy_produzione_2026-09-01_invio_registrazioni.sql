/*
	Deploy produzione - 2026-09-01 - Invio registrazioni al RENTRI (Rifiuti/Registrazioni)

	PREREQUISITO/COMPAGNO DA GESTIRE SEPARATAMENTE (fuori da questo script, manuale
	sull'hub condiviso 1_0_rentri - nessun repo Git lo traccia, se ne occupa l'utente):
	branch "ELSE IF @App = '40'" da aggiungere a due SP dell'hub:
		- dbo.uspRegistrazioni_get_List (legge da [4_0_ecomatico]..viewRentriRegistrazioni,
		  richiede COLLATE DATABASE_DEFAULT sul join z.Id = r.IDRentri)
		- dbo.uspRegistrazioni_upd_ByRegistrazioni (scrive RentriIdentificativo/RentriData
		  su [4_0_ecomatico]..tblRifiutiRegistrazioni)
	Verificare anche che entrambe abbiano SET ANSI_NULLS/QUOTED_IDENTIFIER ON come header
	(sys.sql_modules.uses_quoted_identifier/uses_ansi_nulls devono valere 1) - una delle due
	era stata trovata con QUOTED_IDENTIFIER OFF durante lo sviluppo, causa di un errore reale
	("SET options incorrect: QUOTED_IDENTIFIER") su una UPDATE.
	Senza questo lato hub, la UI di invio (bottone su Rifiuti/Registrazioni/Index) fallisce.

	Contenuto di questo script (solo 4_0_ecomatico, verificato su dev con dati reali,
	idempotente, nessuna modifica di schema/dati oltre a quanto segue):

	1) dbo.viewRentriRegistrazioni (nuova - prima vista del progetto)
	   - Mappa lo schema di questa app alle colonne attese dall'hub, allineate alla versione
	     più aggiornata (produzione) del branch gemello @App='31', fornita dall'utente il
	     2026-09-01. ClassiPericolo, RegistrazioniAssociate, MaterialeSecondarioDescrizione,
	     EsitoCausaleRespingimento/RespingimentoMotivo/RespingimentoQuantita e
	     TransfrontalieroTipo hanno un equivalente reale in questo schema e sono popolate;
	     rettifica/annullamento e secondo Intermediario restano NULL/0 (nessun concetto
	     equivalente). La CASE che azzera Provenienza per Trasporto/Intermediazione (equivalente
	     delle causali CSF/CSM/CST/CSX/TRD di 3_1) è replicata filtrando su
	     tblRifiutiOperazioni.Codice ('T*aT'/'TR', i codici RENTRI reali), confermato dall'utente.

	2) dbo.uspRifiutiRegistrazioni_get_InvioControllo (nuova)
	   - Pre-controllo di coerenza (sequenzialità, causale, quantità, Lock, autorizzazioni,
	     comune Produttore) sulle registrazioni non ancora inviate nell'intervallo scelto
	     dall'utente in UI, si ferma al primo problema. Adattata dalla SP di riferimento di
	     3_1_ecomatico fornita dall'utente. Riusa viewRentriRegistrazioni.

	3) dbo.uspRifiutiRegistrazioni_get_InvioDefault (nuova)
	   - Data e numero/anno dell'ultima registrazione non ancora inviata, per precompilare
	     la modale "Invio registrazioni" in UI. Ritorna sempre 1 riga (OUTER APPLY su riga
	     fittizia), colonne NULL se non ci sono registrazioni da inviare.

	Verificato su DB dev: build pulita, header ANSI_NULLS/QUOTED_IDENTIFIER su tutti e 3 gli
	oggetti (uses_quoted_identifier/uses_ansi_nulls = 1 su sys.sql_modules), test funzionale
	su dati reali per vista/entrambe le SP (incl. branch data/branch numero+anno del
	controllo, riscontro con l'invio reale via hub in dev tramite un collegamento RENTRI
	fittizio temporaneo, poi ripulito). Nessun test end-to-end contro il servizio RENTRI
	vero (nessuna credenziale/accesso browser disponibile in questa sessione).

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-01_invio_registrazioni.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- 1) dbo.viewRentriRegistrazioni
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

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
    -- Il codice RENTRI reale (DT/aT/T*aT/RE/I/NP/M/TR/SI/T*) e' tblRifiutiOperazioni.Codice, non
    -- r.Operazione (CHAR(1) C/S/X/..., solo una classificazione interna) - confermato confrontando
    -- con l'esito di uspRegistrazioni_get_List sul DB gemello 3_1_ecomatico (causale_operazione='DT'/'aT').
    Operazione                   = o.Codice,

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

    -- Solo per gli Scarichi (o.Operazione = 'S', la classificazione C/S/X di tblRifiutiOperazioni,
    -- non il codice RENTRI o.Codice): RENTRI rifiuta un riferimento_operazione su un Carico, e
    -- accetta solo riferimenti a Carichi con Anno/Numero MINORE dello Scarico stesso (confermato
    -- dall'utente - vincolo già applicato lato UI quando si associano le registrazioni).
    RegistrazioniAssociate       = IIF(o.Operazione = 'S', assocA.Registrazioni, NULL),

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
GO

--------------------------------------------------------------------------------
-- 2) dbo.uspRifiutiRegistrazioni_get_InvioControllo
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_InvioControllo]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@AllaData DATE = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IsData BIT = CAST(IIF(@AllaData IS NOT NULL, 1, 0) AS BIT);

		IF @IsData = 0 AND (@AlNumero IS NULL OR @Anno IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Specificare una data oppure un numero e un anno';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistri WHERE Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro non è associato al rispettivo sul RENTRI';
			GOTO BRANCH_END;
		END

		DECLARE @DataInizioRegistrazioni DATE;

		IF EXISTS (
			SELECT 1
			FROM dbo.viewRentriRegistrazioni WITH (NOLOCK)
			WHERE IDRegistro = @IdRegistro AND RentriIdentificativo IS NOT NULL AND Lock < 2
		)
			SELECT @DataInizioRegistrazioni = MAX(Data)
			FROM dbo.viewRentriRegistrazioni WITH (NOLOCK)
			WHERE IDRegistro = @IdRegistro AND RentriIdentificativo IS NOT NULL AND Lock < 2;
		ELSE
			SELECT @DataInizioRegistrazioni = z.DataInizioInvio
			FROM
				dbo.tblRentriRegistri                    g
				LEFT JOIN [1_0_rentri]..tblRegistri z ON g.IdRentri = z.Id COLLATE DATABASE_DEFAULT
			WHERE g.Id = @IdRegistro;

		DECLARE
			@Numero INT, @Data DATE, @NumeroBak INT = 0, @DataBak DATE,
			@Operazione VARCHAR(10), @Quantita DECIMAL(18, 3), @Anno_ CHAR(4),
			@IsTrasportatore BIT, @TrasportatoreAutorizzazione VARCHAR(20),
			@IsDestinatario BIT, @DestinatarioAutorizzazione VARCHAR(20),
			@IsIntermediario BIT, @IntermediarioAutorizzazione VARCHAR(20),
			@IsProduttore BIT, @ProduttoreIdComune CHAR(6), @ProduttoreNazione CHAR(2),
			@RecLock TINYINT, @Count INT = 0, @CountMax INT = 100;

		DECLARE c CURSOR LOCAL FAST_FORWARD FOR
		SELECT
			r.Numero, r.Data, r.Operazione, r.Quantita,
			r.IsTrasportatore, r.TrasportatoreAutorizzazione,
			r.IsDestinatario, r.DestinatarioAutorizzazione,
			r.IsIntermediario, r.IntermediarioAutorizzazione,
			r.IsProduttore, r.ProduttoreIdComune, r.ProduttoreNazione,
			r.Lock
		FROM dbo.viewRentriRegistrazioni r WITH (NOLOCK)
		WHERE
			r.IDRegistro = @IdRegistro
			AND r.RentriIdentificativo IS NULL
			AND r.Lock < 2
			AND (@DataInizioRegistrazioni IS NULL OR r.Data >= @DataInizioRegistrazioni)
			AND (
				(@IsData = 1 AND r.Data <= @AllaData)
				OR (@IsData = 0 AND ((r.Anno < @Anno) OR (r.Anno = @Anno AND r.Numero BETWEEN 1 AND @AlNumero)))
			)
		ORDER BY r.Data, r.Numero;

		OPEN c;
		FETCH c INTO @Numero, @Data, @Operazione, @Quantita, @IsTrasportatore, @TrasportatoreAutorizzazione, @IsDestinatario, @DestinatarioAutorizzazione, @IsIntermediario, @IntermediarioAutorizzazione, @IsProduttore, @ProduttoreIdComune, @ProduttoreNazione, @RecLock;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF @Count >= @CountMax
			BEGIN
				SET @returnMessage = 'Il numero massimo di registrazioni inviabile è ' + CAST(@CountMax AS VARCHAR(20));
				BREAK;
			END
			ELSE IF (@IsData = 1 AND YEAR(@Data) <> YEAR(@AllaData)) OR (@IsData = 0 AND YEAR(@Data) <> @Anno)
			BEGIN
				SET @returnMessage = 'Le registrazioni devono appartenere allo stesso anno, registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF @Operazione IS NULL
			BEGIN
				SET @returnMessage = 'Causale non valida, registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF @Quantita < 0
			BEGIN
				SET @returnMessage = 'Q.tà negativa non valida, registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF ISNULL(@RecLock, 0) <> 0
			BEGIN
				SET @returnMessage = 'Registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy') + ' non confermata';
				BREAK;
			END
			ELSE IF (@NumeroBak > 0 AND @Numero - @NumeroBak <> 1)
			BEGIN
				SET @returnMessage = 'Salto di numerazione registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF (@NumeroBak > 0 AND @Data < @DataBak)
			BEGIN
				SET @returnMessage = 'Data inferiore alla precedente reg. N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF (ISNULL(@IsTrasportatore, 0) = 1 AND @TrasportatoreAutorizzazione IS NOT NULL AND @TrasportatoreAutorizzazione NOT LIKE '[A-Z][A-Z]/[0-9][0-9][0-9][0-9][0-9][0-9]')
			BEGIN
				SET @returnMessage = 'Il nr. di autoriz. del trasportatore deve essere indicato nel formato "AA/123456". Reg. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yy');
				BREAK;
			END
			ELSE IF (ISNULL(@IsDestinatario, 0) = 1 AND (@DestinatarioAutorizzazione IS NULL OR LEN(@DestinatarioAutorizzazione) = 0 OR LEN(@DestinatarioAutorizzazione) > 20))
			BEGIN
				SET @returnMessage = 'Nr. errato autoriz. destinatario. Reg. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yy');
				BREAK;
			END
			ELSE IF (ISNULL(@IsIntermediario, 0) = 1 AND @IntermediarioAutorizzazione IS NOT NULL AND @IntermediarioAutorizzazione NOT LIKE '[A-Z][A-Z]/[0-9][0-9][0-9][0-9][0-9][0-9]')
			BEGIN
				SET @returnMessage = 'Il nr. di autoriz. dell''intermediario deve essere indicato nel formato "AA/123456". Reg. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yy');
				BREAK;
			END
			ELSE IF (ISNULL(@IsProduttore, 0) = 1 AND @ProduttoreNazione = 'IT' AND @ProduttoreIdComune IS NULL)
			BEGIN
				SET @returnMessage = 'Comune del Produttore non valido. Aggiornare l''anagrafica. Reg. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yy');
				BREAK;
			END

			SET @Count = @Count + 1;
			SET @NumeroBak = @Numero;
			SET @DataBak = @Data;

			FETCH c INTO @Numero, @Data, @Operazione, @Quantita, @IsTrasportatore, @TrasportatoreAutorizzazione, @IsDestinatario, @DestinatarioAutorizzazione, @IsIntermediario, @IntermediarioAutorizzazione, @IsProduttore, @ProduttoreIdComune, @ProduttoreNazione, @RecLock;
		END
		CLOSE c;
		DEALLOCATE c;

		IF @returnMessage IS NULL AND @Count = 0
			SET @returnMessage = 'Nessuna registrazione trovata nell''intervallo indicato';

	END TRY
	BEGIN CATCH
		IF CURSOR_STATUS('local', 'c') >= -1
		BEGIN
			CLOSE c;
			DEALLOCATE c;
		END;
		THROW;
	END CATCH

	BRANCH_END:

	SET NOCOUNT, XACT_ABORT OFF;

	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

	SELECT Count = @Count, Messaggio = @returnMessage;

END
GO

--------------------------------------------------------------------------------
-- 3) dbo.uspRifiutiRegistrazioni_get_InvioDefault
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_InvioDefault]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- OUTER APPLY su una riga fittizia: garantisce sempre esattamente 1 riga in output
		-- (con colonne NULL se non ci sono registrazioni non inviate), richiesto da QuerySingleAsync lato C#.
		SELECT
			UltimaData = t.Data,
			UltimoNumero = t.Numero,
			UltimoAnno = t.Anno
		FROM
			(SELECT 1 AS Dummy) d
			OUTER APPLY (
				SELECT TOP 1
					r.Data, r.Numero, r.Anno
				FROM
					dbo.viewRentriRegistrazioni r WITH (NOLOCK)
				WHERE
					r.IDRegistro = @IdRegistro
					AND r.RentriIdentificativo IS NULL
					AND r.Lock = 0
				ORDER BY
					r.Data DESC, r.Numero DESC
			) t;

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

END
GO
