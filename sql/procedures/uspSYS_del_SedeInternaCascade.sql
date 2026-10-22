SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_SedeInternaCascade
    @IdSede   CHAR(16)    = NULL,
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSede   = NULLIF(LTRIM(RTRIM(@IdSede)),   '');
        SET @Conferma = NULLIF(LTRIM(RTRIM(@Conferma)), '');

        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @IdSede AND InternaEsterna = 'I')
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La sede indicata non esiste o non è una sede interna';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- Sede di partenza + tutte le sotto-sedi collegate (tblSedi.IdParent, tblSedi.IdAziendaInterna,
        -- tblSediEsterne.IdSedeInterna), a qualunque profondità. Ciclo con deduplica esplicita anziché
        -- CTE ricorsiva: le tre relazioni unite possono formare cicli sui dati reali, e una CTE
        -- ricorsiva pura non deduplica tra un livello e l'altro, rischiando MAXRECURSION anche in
        -- assenza di un vero ciclo logico.
        -- COLLATE DATABASE_DEFAULT esplicito: senza, la colonna erediterebbe la collation di tempdb
        -- (non convertita insieme al DB, vedi project_collation_conversion), in conflitto con le
        -- colonne CHAR(16) del database nei confronti/JOIN sottostanti.
        CREATE TABLE #Sedi (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
        INSERT INTO #Sedi (Id) VALUES (@IdSede);

        DECLARE @nuoveRighe INT = 1;
        WHILE @nuoveRighe > 0
        BEGIN
            INSERT INTO #Sedi (Id)
            SELECT DISTINCT x.Id
            FROM (
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdParent = c.Id
                UNION
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdAziendaInterna = c.Id
                UNION
                SELECT se.Id FROM dbo.tblSediEsterne se INNER JOIN #Sedi c ON se.IdSedeInterna = c.Id
            ) x
            WHERE NOT EXISTS (SELECT 1 FROM #Sedi t WHERE t.Id = x.Id);

            SET @nuoveRighe = @@ROWCOUNT;
        END

        DECLARE @totaleSedi INT = (SELECT COUNT(*) FROM #Sedi);

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui)
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #Etichette FROM dbo.tblEtichette WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Calendari FROM dbo.tblCalendari WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Eventi FROM dbo.tblEventi WHERE IdCalendario IN (SELECT Id FROM #Calendari);
        SELECT Id INTO #Tipi FROM dbo.tblTipi WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #TipiProprieta FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #Tipi);
        SELECT Id INTO #Persone FROM dbo.tblPersone WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Oggetti FROM dbo.tblOggetti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Gestione EoW: lotti/allocazioni/magazzini specifici EoW di proprietà della sede (solo sedi
        -- interne, IdSede diretto su tutte e tre le tabelle) - vedi project_eow_module_design in
        -- memoria persistente.
        SELECT Id INTO #EoWLotti FROM dbo.tblEoWLotti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #EoWAllocazioni FROM dbo.tblEoWAllocazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #EoWMagazzini FROM dbo.tblEoWMagazzini WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Modulo Magazzino: Articoli/Movimenti hanno IdSede = Azienda; Lotti hanno IdSede = sede
        -- operativa (può essere una sede figlia diversa dall'Azienda) - vedi project_magazzino
        -- in memoria persistente.
        SELECT Id INTO #MagArticoli FROM dbo.tblMagazziniArticoli WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #MagLotti FROM dbo.tblMagazziniLotti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #MagMovimenti FROM dbo.tblMagazziniMovimenti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Anagrafica estesa e Fatturazione: schede dell'azienda (o sul soggetto, se nella cascata),
        -- banche/casse e aliquote IVA proprie dell'azienda
        SELECT Id INTO #ClientiFornitori FROM dbo.tblClientiFornitori
        WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi) OR IdSede IN (SELECT Id FROM #Sedi);
        -- Schede amministratore dell'azienda (o su un soggetto della cascata)
        SELECT Id INTO #Amministratori FROM dbo.tblAmministratori
        WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi) OR IdSede IN (SELECT Id FROM #Sedi);
        -- Fatture dell'azienda (o di una scheda della cascata) e conti dell'azienda
        SELECT Id INTO #Fatture FROM dbo.tblFatture
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);
        SELECT Id INTO #FattureConti FROM dbo.tblFattureConti WHERE IdSede IN (SELECT Id FROM #Sedi);        SELECT Id INTO #BancheCasse FROM dbo.tblBancheCasse WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #AliquoteIva FROM dbo.tblAliquoteIva WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Dichiarazioni MUD dell'azienda o che citano una sede della cascata
        SELECT Id INTO #RifiutiMud FROM dbo.tblRifiutiMud
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdSedeLegale IN (SELECT Id FROM #Sedi) OR IdSedeUnitaLocale IN (SELECT Id FROM #Sedi);

        -- tblSedi/tblPersone/tblOggetti sono sottotipi a chiave condivisa di tblOsepe (stesso Id)
        SELECT Id INTO #OsepeIds FROM (
            SELECT Id FROM #Sedi
            UNION
            SELECT Id FROM #Persone
            UNION
            SELECT Id FROM #Oggetti
        ) x;

        SELECT Id INTO #RifiutiRegistri FROM dbo.tblRifiutiRegistri WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiAutorizzazioni FROM dbo.tblRifiutiAutorizzazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblRifiutiLimiti.IdSede è NOT NULL (proprietà della sede) e IdRegistro è nullable (scoping
        -- opzionale a un registro specifico della stessa sede) - entrambi i rami coperti per sicurezza.
        SELECT Id INTO #RifiutiLimiti FROM dbo.tblRifiutiLimiti
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblDiwassCredenziali.IdAziendaInterna: credenziale DIWASS dell'azienda interna, con la sua riga nell'hub
        SELECT Id, IdDiwass INTO #DiwassCredenziali FROM dbo.tblDiwassCredenziali WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);

        SELECT Id INTO #RifiutiMovimenti
        FROM dbo.tblRifiutiMovimenti
        WHERE IdSedeProduttoreDetentore IN (SELECT Id FROM #Sedi)
           OR IdSedeDestinatario        IN (SELECT Id FROM #Sedi)
           OR IdSedeTrasportatore1      IN (SELECT Id FROM #Sedi)
           OR IdSedeIntermediario1      IN (SELECT Id FROM #Sedi)
           OR IdRegistro                IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        SELECT Id INTO #Scadenze
        FROM dbo.tblScadenze
        WHERE IdEvento IN (SELECT Id FROM #Eventi)
           OR IdTipo   IN (SELECT Id FROM #Tipi);

        SELECT Id INTO #Servizi
        FROM dbo.tblServizi
        WHERE IdEvento      IN (SELECT Id FROM #Eventi)
           OR IdRichiedente IN (SELECT Id FROM #Sedi)
           OR IdTipo        IN (SELECT Id FROM #Tipi);

        -- tblAreeSediInterne/tblAreeOsepe/tblUtentiSediInterne sono giunzioni a chiave composita
        -- verso risorse condivise a livello di Dominio (tblAree, tblUtenti), non di proprietà della
        -- sede: si cancellano solo le righe di giunzione, mai tblAree/tblUtenti stesse.
        SELECT Id, IdSede  INTO #AreeSediInterne FROM dbo.tblAreeSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id, IdOsepe INTO #AreeOsepe       FROM dbo.tblAreeOsepe       WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

        -- Fatturazione: righe e rate delle fatture della cascata e pagamenti che potrebbero essere
        -- cancellati (quelli dell'azienda o delle sue banche e casse, e quelli che coprono rate di
        -- queste fatture), raccolti qui per la pulizia finale degli Id. Un pagamento che copre anche
        -- rate di altre fatture non viene cancellato: la pulizia toglie solo gli Id dei pagamenti
        -- che alla fine non esistono più
        SELECT Id INTO #FattureRighe FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #FattureRate FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #PagamentiCandidati FROM (
            SELECT Id FROM dbo.tblPagamenti
            WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi)
            UNION
            SELECT rp.IdPagamento FROM dbo.tblFattureRatePagamenti rp
            WHERE rp.IdRata IN (SELECT Id FROM #FattureRate)
        ) x;

        -- Offerte e contratti: importi (con le righe) e offerte o contratti dell'azienda, o di una
        -- scheda cliente della cascata
        SELECT Id INTO #Importi FROM dbo.tblImporti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #ImportiRighe FROM dbo.tblImportiRighe WHERE IdImporto IN (SELECT Id FROM #Importi);
        SELECT Id INTO #OfferteContratti FROM dbo.tblOfferteContratti
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            -- Offerte e contratti, per primi: referenziano fatture, schede cliente, conti, aliquote,
            -- etichette, tipi e sedi cancellati più sotto. I documenti fatturabili (registrazioni,
            -- movimenti di magazzino, servizi) hanno lo stesso Id del documento
            DELETE FROM dbo.tblFattureDocumenti
            WHERE
                Id IN (SELECT Id FROM #RifiutiRegistrazioni)
                OR Id IN (SELECT Id FROM #MagMovimenti)
                OR Id IN (SELECT Id FROM #Servizi)
                OR IdFattura IN (SELECT Id FROM #Fatture)
                OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori)
                OR IdImporto IN (SELECT Id FROM #Importi)
                OR IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContrattiImporti
            WHERE IdOffertaContratto IN (SELECT Id FROM #OfferteContratti) OR IdImporto IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblOfferteContratti WHERE Id IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblImportiRigheDettagli WHERE Id IN (SELECT Id FROM #ImportiRighe);
            DELETE FROM dbo.tblImportiRighe WHERE Id IN (SELECT Id FROM #ImportiRighe);
            DELETE FROM dbo.tblImportiRifiuti WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImportiMagazzino WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImportiServizi WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImporti WHERE Id IN (SELECT Id FROM #Importi);
            -- Importi di ALTRE aziende che citano una sede, un'etichetta, un tipo, un conto o
            -- un'aliquota della cascata (non previsto dalle regole): perdono solo il collegamento
            UPDATE dbo.tblImportiRifiuti SET IdProduttoreParent = NULL WHERE IdProduttoreParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdProduttore = NULL WHERE IdProduttore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdTrasportatore = NULL WHERE IdTrasportatore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdIntermediario = NULL WHERE IdIntermediario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiMagazzino SET IdSedePartenza = NULL WHERE IdSedePartenza IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatarioParent = NULL WHERE IdDestinatarioParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdRichiedenteParent = NULL WHERE IdRichiedenteParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdRichiedente = NULL WHERE IdRichiedente IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdSedeInterna = NULL WHERE IdSedeInterna IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdTipo = NULL WHERE IdTipo IN (SELECT Id FROM #Tipi);
            -- Righe di listino di ALTRE aziende su un articolo della cascata (non previsto): perdono l'articolo
            DELETE FROM dbo.tblImportiRigheMagazzino WHERE IdArticolo IN (SELECT Id FROM #MagArticoli);
            -- Righe di listino di ALTRE aziende su una persona o un oggetto della cascata (condivisi): perdono la risorsa
            DELETE FROM dbo.tblImportiRigheServizi WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);
            UPDATE dbo.tblImportiRigheDettagli SET IdConto = NULL WHERE IdConto IN (SELECT Id FROM #FattureConti);
            UPDATE dbo.tblImportiRigheDettagli SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);

            DELETE FROM dbo.tblRifiutiAutorizzazioniAttivita         WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniConducenti       WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniEer              WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTarghe           WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            -- FK NO_ACTION verso tblRifiutiModelli: righe della generazione automatica dei carichi
            -- (IdModello NOT NULL, si cancellano) e movimenti creati dal modello (IdModello nullable,
            -- perdono solo il collegamento)
            DELETE ae
            FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette ae
            INNER JOIN dbo.tblRifiutiModelliRegistrazioniAuto a ON ae.Id = a.Id
            WHERE a.IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAuto WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            UPDATE dbo.tblRifiutiMovimenti SET IdModello = NULL WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            DELETE FROM dbo.tblRifiutiFormulariEtichette             WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti     WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                      WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Modulo Magazzino: cascata figlio->genitore (FK NO_ACTION, nessun ON DELETE CASCADE).
            -- Va fatta prima della Gestione EoW: le righe EoW di scarico referenziano tblEoWLotti.
            -- Relazioni carico/scarico in entrambi i versi (righe della sede, dei suoi movimenti o
            -- dei suoi lotti): FK NO_ACTION su Id e IdParent verso tblMagazziniMovimentiRighe.
            DELETE rel
            FROM dbo.tblMagazziniMovimentiRigheRelazioni rel
            INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rel.Id = r.Id OR rel.IdParent = r.Id
            WHERE r.IdSede IN (SELECT Id FROM #Sedi) OR r.IdMovimento IN (SELECT Id FROM #MagMovimenti) OR r.IdLotto IN (SELECT Id FROM #MagLotti);

            DELETE rel
            FROM dbo.tblMagazziniMovimentiRigheEoWLotti rel
            INNER JOIN dbo.tblMagazziniMovimentiRigheEoW re ON rel.Id = re.Id
            WHERE
                re.IdSede IN (SELECT Id FROM #Sedi)
                OR re.IdMovimento IN (SELECT Id FROM #MagMovimenti)
                OR re.IdLotto IN (SELECT Id FROM #EoWLotti)
                OR rel.IdLotto IN (SELECT Id FROM #EoWLotti);

            DELETE FROM dbo.tblMagazziniDdt
            WHERE
                IdSede IN (SELECT Id FROM #Sedi)
                OR IdMittente IN (SELECT Id FROM #Sedi)
                OR IdDestinatario IN (SELECT Id FROM #Sedi)
                OR IdDestinazione IN (SELECT Id FROM #Sedi)
                OR IdTrasportatore IN (SELECT Id FROM #Sedi)
                OR IdMovimento IN (SELECT Id FROM #MagMovimenti);

            DELETE FROM dbo.tblMagazziniMovimentiRighe
            WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdMovimento IN (SELECT Id FROM #MagMovimenti) OR IdLotto IN (SELECT Id FROM #MagLotti);
            DELETE FROM dbo.tblMagazziniMovimentiRigheEoW
            WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdMovimento IN (SELECT Id FROM #MagMovimenti) OR IdLotto IN (SELECT Id FROM #EoWLotti);

            DELETE FROM dbo.tblMagazziniMovimenti WHERE Id IN (SELECT Id FROM #MagMovimenti);
            DELETE FROM dbo.tblMagazziniLotti WHERE Id IN (SELECT Id FROM #MagLotti);
            DELETE FROM dbo.tblMagazziniArticoli WHERE Id IN (SELECT Id FROM #MagArticoli);

            -- Gestione EoW: va fatta prima di cancellare Registrazioni sottostanti, per rispettare
            -- la FK di tblEoWLottiRifiutiRegistrazioni.IdRegistrazione (NOT NULL, parte della PK
            -- composta con IdLotto - non azzerabile, la riga di collegamento va sempre rimossa,
            -- anche quando referenzia una Registrazione di questa sede legata a un Lotto di un'altra:
            -- stesso motivo dell'OR su #RifiutiRegistrazioni). I lotti/allocazioni EoW di questa sede
            -- vengono invece cancellati per intero (non azzerati) perché sono risorse di proprietà
            -- esclusiva della sede stessa, non condivise con altre sedi.
            DELETE FROM dbo.tblEoWLottiRifiutiRegistrazioni
            WHERE IdLotto        IN (SELECT Id FROM #EoWLotti)
               OR IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblEoWLottiAllocazioni
            WHERE IdLotto      IN (SELECT Id FROM #EoWLotti)
               OR IdAllocazione IN (SELECT Id FROM #EoWAllocazioni);
            DELETE FROM dbo.tblEoWLotti       WHERE Id IN (SELECT Id FROM #EoWLotti);
            DELETE FROM dbo.tblEoWAllocazioni WHERE Id IN (SELECT Id FROM #EoWAllocazioni);

            -- tblEoWLotti.IdMagazzino (nullable, nessun vincolo strutturale che lo leghi allo stesso
            -- IdSede del Lotto) può referenziare un Magazzino di questa sede anche da un Lotto esterno
            -- alla cascata - i Lotti di questa sede sono già stati cancellati sopra, quindi qui restano
            -- solo eventuali riferimenti esterni: azzerati, non cancellati (stessa logica "UPDATE=NULL
            -- dove possibile" delle risorse condivise più sotto).
            DECLARE @eoWLottiScollegati INT;
            UPDATE dbo.tblEoWLotti SET IdMagazzino = NULL WHERE IdMagazzino IN (SELECT Id FROM #EoWMagazzini);
            SET @eoWLottiScollegati = @@ROWCOUNT;
            DELETE FROM dbo.tblEoWMagazzini WHERE Id IN (SELECT Id FROM #EoWMagazzini);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va rimossa prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se una registrazione in cancellazione è coinvolta in una rettifica.
            DELETE FROM dbo.tblRentriRegistrazioniRettifiche
            WHERE Id          IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdRettifica IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRifiutiLimiti* va rimosso prima di tblRifiutiRegistri: FK NO_ACTION su IdRegistro
            -- bloccherebbe altrimenti la cancellazione del registro sottostante.
            DELETE FROM dbo.tblRifiutiLimitiEer        WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiEtichette  WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiOperazioni WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimiti           WHERE Id IN (SELECT Id FROM #RifiutiLimiti);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL, nessun
            -- ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante fallisce per FK.
            DELETE FROM dbo.tblRentriRegistri  WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            -- Dichiarazioni MUD: registri della dichiarazione (FK su tblRifiutiMud e su
            -- tblRifiutiRegistri), poi la dichiarazione
            DELETE FROM dbo.tblRifiutiMudRegistri
            WHERE Id IN (SELECT Id FROM #RifiutiMud) OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblRifiutiMud WHERE Id IN (SELECT Id FROM #RifiutiMud);

            DELETE FROM dbo.tblRifiutiRegistri WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            DELETE FROM dbo.tblScadenzeOsepe
            WHERE Id      IN (SELECT Id FROM #Scadenze)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblScadenze WHERE Id IN (SELECT Id FROM #Scadenze);

            DELETE FROM dbo.tblServiziOsepe
            WHERE Id      IN (SELECT Id FROM #Servizi)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblServizi WHERE Id IN (SELECT Id FROM #Servizi);

            DELETE FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipi          WHERE Id IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblEventiFirme      WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiProprieta  WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiUtenti     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenzeEccezioni
            WHERE Id       IN (SELECT Id FROM #Eventi)
               OR IdEvento IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenze WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventi     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblCalendari  WHERE Id IN (SELECT Id FROM #Calendari);

            -- Risorse riutilizzabili di proprietà della sede: prima di cancellarle si liberano da
            -- eventuali riferimenti di ALTRE sedi non coinvolte nella cascata. Dove la colonna è
            -- nullable si azzera il riferimento (la riga esterna resta, perde solo il collegamento);
            -- dove è NOT NULL non è possibile azzerarla, quindi si cancella la riga di giunzione
            -- esterna stessa. Scelta esplicita dell'utente: tocca dati di altre sedi pur di
            -- garantire che Etichette/Autorizzazioni di questa sede vengano sempre rimosse.
            DECLARE @rifEsterniRimossi INT = 0;

            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneDestinatario = NULL         WHERE IdAutorizzazioneDestinatario         IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneIntermediario1 = NULL       WHERE IdAutorizzazioneIntermediario1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneProduttoreDetentore = NULL  WHERE IdAutorizzazioneProduttoreDetentore  IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore1 = NULL       WHERE IdAutorizzazioneTrasportatore1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore2 = NULL       WHERE IdAutorizzazioneTrasportatore2       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiMovimentiDestinatari   WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari  WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiProduttori    WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiFormulariEtichette     WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblEtichette             WHERE Id IN (SELECT Id FROM #Etichette);
            DELETE FROM dbo.tblRifiutiAutorizzazioni WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblPersoneRuoli WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblPersone      WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblOggetti      WHERE Id IN (SELECT Id FROM #Oggetti);

            -- Anagrafica estesa e Fatturazione: prima le schede, che referenziano banche/casse e
            -- aliquote; le schede di ALTRE aziende che usano un'aliquota o una banca di questa
            -- (non previsto dalle regole) perdono solo il collegamento
            -- Fatturazione: fatture con righe, rate e pagamenti (prima delle schede, delle banche e
            -- delle aliquote, che le fatture referenziano)
            DELETE FROM dbo.tblFattureRigheImporti WHERE Id IN (SELECT Id FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
            SELECT DISTINCT rp.IdPagamento AS Id INTO #Pagamenti
            FROM dbo.tblFattureRatePagamenti rp INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
            WHERE r.IdFattura IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFattureRatePagamenti WHERE IdRata IN (SELECT Id FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblPagamenti
            WHERE Id IN (SELECT Id FROM #Pagamenti) AND Id NOT IN (SELECT IdPagamento FROM dbo.tblFattureRatePagamenti);
            DELETE FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
            UPDATE dbo.tblFatture SET IdFatturaRiferimento = NULL WHERE IdFatturaRiferimento IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFatture WHERE Id IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblClientiFornitori WHERE Id IN (SELECT Id FROM #ClientiFornitori);
            DELETE FROM dbo.tblAmministratoriSedi
            WHERE Id IN (SELECT Id FROM #Amministratori) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblAmministratori WHERE Id IN (SELECT Id FROM #Amministratori);
            UPDATE dbo.tblClientiFornitori SET IdBancaCassa = NULL WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse);
            UPDATE dbo.tblClientiFornitori SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);
            -- Conti: le righe di ALTRE aziende che li usano (non previsto dalle regole) perdono solo il
            -- collegamento, come per banche/casse e aliquote
            UPDATE dbo.tblFattureRigheImporti SET IdConto = NULL WHERE IdConto IN (SELECT Id FROM #FattureConti);
            DELETE FROM dbo.tblFattureConti WHERE Id IN (SELECT Id FROM #FattureConti);
            DELETE FROM dbo.tblFattureDatiFiscali WHERE Id IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblFattureRigheImporti SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);
            UPDATE dbo.tblFatture SET IdBancaCassa = NULL WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse);
            DELETE FROM dbo.tblFattureRatePagamenti
            WHERE IdPagamento IN (SELECT Id FROM dbo.tblPagamenti WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi));
            DELETE FROM dbo.tblPagamenti WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi);            DELETE FROM dbo.tblBancheCasse WHERE Id IN (SELECT Id FROM #BancheCasse);
            DELETE FROM dbo.tblAliquoteIva WHERE Id IN (SELECT Id FROM #AliquoteIva);

            -- Giunzioni a chiave composita verso risorse condivise (tblAree/tblUtenti non toccate)
            DELETE asi FROM dbo.tblAreeSediInterne asi INNER JOIN #AreeSediInterne t ON t.Id = asi.Id AND t.IdSede  = asi.IdSede;
            DELETE ao  FROM dbo.tblAreeOsepe       ao  INNER JOIN #AreeOsepe       t ON t.Id = ao.Id  AND t.IdOsepe = ao.IdOsepe;
            DELETE FROM dbo.tblUtentiSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL (nessuna
            -- colonna da azzerare) - si cancella la riga di associazione, mai tblRentriCredenziali stessa.
            DELETE FROM dbo.tblRentriCredenzialiSedi WHERE IdSede IN (SELECT Id FROM #Sedi);

            DELETE FROM dbo.tblSediDatiEstesi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediReport WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediRecapiti  WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediEsterne   WHERE Id IN (SELECT Id FROM #Sedi);
            -- tblDiwassCredenziali prima di tblSediInterne (FK su IdAziendaInterna), con la riga dell'hub 1_0_diwass
            DELETE FROM [1_0_diwass]..tblCredenziali WHERE Id IN (SELECT IdDiwass FROM #DiwassCredenziali);
            DELETE FROM dbo.tblDiwassCredenziali WHERE Id IN (SELECT Id FROM #DiwassCredenziali);
            DELETE FROM dbo.tblSediInterne   WHERE Id IN (SELECT Id FROM #Sedi);

            -- Radice e sotto-sedi cancellate in un'unica istruzione set-based: i vincoli
            -- auto-referenziati IdParent/IdAziendaInterna sono verificati a fine istruzione (non
            -- riga per riga), quindi non si bloccano a vicenda anche su gerarchie a più livelli.
            DELETE FROM dbo.tblSedi WHERE Id IN (SELECT Id FROM #Sedi);

            -- tblOsepe: supertipo condiviso di Sedi/Persone/Oggetti, cancellato per ultimo
            DELETE FROM dbo.tblOsepe WHERE Id IN (SELECT Id FROM #OsepeIds);

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get), solo per le entità con Id
            -- proprio (non per le tabelle a chiave condivisa/giunzione, già coperte a monte)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #OsepeIds
                UNION SELECT Id FROM #Calendari
                UNION SELECT Id FROM #Etichette
                UNION SELECT Id FROM #Eventi
                UNION SELECT Id FROM #MagArticoli
                UNION SELECT Id FROM #MagLotti
                UNION SELECT Id FROM #MagMovimenti
                UNION SELECT Id FROM #ClientiFornitori
                UNION SELECT Id FROM #Fatture
                UNION SELECT Id FROM #FattureRighe
                UNION SELECT Id FROM #FattureRate
                UNION SELECT Id FROM #FattureConti
                UNION SELECT Id FROM #PagamentiCandidati WHERE Id NOT IN (SELECT Id FROM dbo.tblPagamenti)
                UNION SELECT Id FROM #Importi
                UNION SELECT Id FROM #ImportiRighe
                UNION SELECT Id FROM #OfferteContratti
                UNION SELECT Id FROM #Amministratori
                UNION SELECT Id FROM #BancheCasse
                UNION SELECT Id FROM #AliquoteIva
                UNION SELECT Id FROM #RifiutiMud
                UNION SELECT Id FROM #EoWLotti
                UNION SELECT Id FROM #EoWAllocazioni
                UNION SELECT Id FROM #EoWMagazzini
                UNION SELECT Id FROM #RifiutiAutorizzazioni
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiRegistri
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT Id FROM #RifiutiLimiti
                UNION SELECT Id FROM #DiwassCredenziali
                UNION SELECT Id FROM #Scadenze
                UNION SELECT Id FROM #Servizi
                UNION SELECT Id FROM #Tipi
                UNION SELECT Id FROM #TipiProprieta
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT('Cancellazione completata. Sedi rimosse: ', @totaleSedi, '. Riferimenti esterni azzerati/rimossi su Etichette/Autorizzazioni condivise: ', @rifEsterniRimossi, '. Lotti EoW rimossi: ', (SELECT COUNT(*) FROM #EoWLotti), ', Allocazioni EoW rimosse: ', (SELECT COUNT(*) FROM #EoWAllocazioni), ', Magazzini EoW rimossi: ', (SELECT COUNT(*) FROM #EoWMagazzini), ' (Lotti esterni scollegati: ', @eoWLottiScollegati, ')', ', Limiti rifiuti rimossi: ', (SELECT COUNT(*) FROM #RifiutiLimiti), '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
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
