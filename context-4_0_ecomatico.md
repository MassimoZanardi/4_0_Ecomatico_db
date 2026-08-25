# Contesto sessione di revisione — 4_0_ecomatico

Ultimo aggiornamento: 2026-08-25 (nuova SP aggiunta dopo la chiusura della revisione sistematica, vedi sezione dedicata in fondo al file; la revisione stessa resta chiusa al 2026-08-14).

**PROGETTO DI REVISIONE SISTEMATICA CHIUSO 2026-08-14.** Tutte le stored procedure di `4_0_ecomatico` raggiungibili dall'applicativo sono state riviste almeno una volta, ad eccezione di: `uspSYS_*` (confermato fuori perimetro, tooling di sviluppo dell'utente) e le 4 SP confermate codice morto (`uspFunzioni_get_PermessoByUtente`, `uspSedi_del`, `uspUtenti_get_Password`, `uspSessioni_upd_AziendaByRegistro`), lasciate intenzionalmente intoccate. L'audit indici (sezione dedicata più sotto) è anch'esso chiuso. Eventuali nuove sessioni di lavoro su questo database partono da zero findings noti — usare questo file + la memoria persistente come riferimento, non ripartire da un "prossimo modulo" perché non ce n'è uno.

Revisione sistematica, modulo per modulo, delle stored procedure di `4_0_ecomatico` secondo gli standard descritti in `CLAUDE.md` (skeleton `TRY/CATCH`/`@returnValue`/`BRANCH_END`, `XACT_ABORT`, titolarità/IDOR, `dbo.` prefix, `Lock`, ecc.). Questo file riassume lo stato per poter riprendere il lavoro senza dover rileggere l'intera cronologia. Il dettaglio completo di ogni revisione è nella memoria persistente dell'assistente (`project_review_uspXxx.md`); questo file è la vista "sviluppatore" leggibile senza quel sistema.

---

## Know-how di revisione — metodologia riusabile

Questa sezione raccoglie il processo e i pattern acquisiti durante le revisioni sopra, da riapplicare tali e quali ai prossimi moduli. Gli standard "statici" (formattazione, skeleton obbligatorio, ecc.) sono in `CLAUDE.md` e non ripetuti qui — questa sezione è il **procedimento operativo** e il **catalogo dei bug ricorrenti** trovati nella pratica.

### Workflow end-to-end per ogni modulo

1. **Fetch**: recuperare la definizione corrente di tutte le SP del modulo con `SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.uspXxx'))` (o un dump concatenato via `sys.sql_modules` per moduli grandi, es. 26 SP di `uspRifiutiAutorizzazioni_*`) — **sempre fresca**, mai riusare una copia letta in un turno precedente se nel frattempo potrebbe essere stata modificata (rischio concreto: durante `uspRifiutiFormulari_*` una normalizzazione CRLF stava per sovrascrivere fix già deployati in quello stesso turno, perché riusava una copia stale).
2. **Review**: confrontare contro `CLAUDE.md` + il catalogo di bug ricorrenti sotto. Presentare i finding numerati all'utente, con un esempio concreto (dati di fantasia) se il bug non è ovvio, prima di applicare qualunque fix.
3. **Conferma prima di modificare comportamenti "strani"**: se una deviazione dallo standard potrebbe essere intenzionale, chiedere prima di correggerla (non assumere sia un bug). Esempi reali dove la deviazione era voluta: `uspRifiutiOperazioni_get_SelectList` con `Selected` hardcoded, `uspRifiutiModelli_get_ClassiPericolo_List` senza titolarità, `uspRifiutiMovimenti_del_All` senza scoping.
4. **Fix**: `Edit` chirurgico per SP grandi/critiche già ben strutturate (rischio di errori di ribattitura su logica di business complessa), riscrittura completa solo per SP piccole o già molto fuori standard.
5. **Deploy**: vedi checklist dedicata sotto.
6. **Verifica**: query batch di controllo (ANSI_NULLS/QUOTED_IDENTIFIER/CRLF/accenti/marker del fix) su tutte le SP toccate in un colpo solo.
7. **Smoke test**: `EXEC` reale con la sessione di test a basso privilegio (vedi sotto) — conferma che non ci siano errori SQL/di riferimento, anche quando la business logic nega l'accesso (un diniego pulito è un successo, un errore SQL non lo è).
8. **Se il fix tocca dati reali**: non fidarsi che il fix sia corretto solo perché compila — testarlo contro un record reale quando possibile. Lezione da `uspRifiutiMovimenti_get_Attivita_List`: il primo fix (ovvio, `@Id` non usato) nascondeva un secondo bug più profondo (tabella sbagliata), scoperto solo verificando l'output contro un movimento reale.
9. **Memoria**: al termine, salvare un file di memoria persistente (`project_review_uspXxx.md`) + aggiornare questo file di contesto.

### Checklist di deploy (comandi esatti)

Ogni fix, prima del deploy, deve avere:
- Header: `SET ANSI_NULLS ON; GO SET QUOTED_IDENTIFIER ON; GO CREATE OR ALTER PROCEDURE ...`
- Footer: `GO` finale dopo `END;`

Normalizzazione CRLF+BOM (**obbligatoria** prima di ogni deploy — `Write`/`Edit` producono LF-only, che SSMS segnala come "line endings inconsistenti" se persistito così):

```powershell
$content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)  # MAI Get-Content -Raw: corrompe gli accenti (es. "può" -> "puÃ²") su PowerShell 5.1
$content = $content -replace "`r`n", "`n"
$content = $content -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($true)))
```

Deploy (`-f 65001` obbligatorio per non corrompere gli accenti italiani):

```powershell
sqlcmd -S ".\SQLSERVER" -d "4_0_ecomatico" -E -f 65001 -i <path>
```

Verifica (usare `-o <file>` + `Read` invece di leggere lo stdout diretto, per evitare troncamenti su `NVARCHAR(MAX)`):

```powershell
sqlcmd -S ".\SQLSERVER" -d "4_0_ecomatico" -E -f 65001 -y 0 -i <verify.sql> -o <out.txt>
```

Query di verifica batch standard (adattare la lista SP e i marker `LIKE`):

```sql
SELECT
    o.name,
    ansi_nulls  = OBJECTPROPERTY(o.object_id, 'ExecIsAnsiNullsOn'),
    quoted_id   = OBJECTPROPERTY(o.object_id, 'ExecIsQuotedIdentOn'),
    modify_date = o.modify_date,
    crlf_pairs  = (LEN(m.definition) - LEN(REPLACE(m.definition, CHAR(13)+CHAR(10), ''))) / 2,
    bare_lf     = LEN(REPLACE(m.definition, CHAR(13)+CHAR(10), '')) - LEN(REPLACE(REPLACE(m.definition, CHAR(13)+CHAR(10), ''), CHAR(10), '')),  -- deve essere 0
    xact_on     = CASE WHEN m.definition LIKE '%NOCOUNT, XACT_ABORT ON%'  THEN 1 ELSE 0 END,
    xact_off    = CASE WHEN m.definition LIKE '%NOCOUNT, XACT_ABORT OFF%' THEN 1 ELSE 0 END
FROM sys.objects o
INNER JOIN sys.sql_modules m ON o.object_id = m.object_id
WHERE o.name IN (...);
```

Smoke test: sessione di test a basso privilegio disponibile in questo DB, `@IdSessione = '0192bdf492274b7f'` — tutti i permessi risultano 0, quindi ogni SP con controllo permesso correttamente scritto la nega in modo pulito (nessun errore SQL). Utile per confermare che la sintassi/i riferimenti siano corretti anche senza un dato reale a disposizione per ogni ramo.

### Catalogo delle classi di bug ricorrenti (in ordine di frequenza/gravità)

1. **Gap di titolarità/IDOR** — di gran lunga la classe più comune e più grave. Varianti trovate:
   - Nessun controllo affatto (`uspRifiutiGiacenze_get_List`, 10 SP di `uspRifiutiAutorizzazioni_*`, `uspPersone_get_Ruoli_List`).
   - Controllo che protegge solo `Lock=0`, non `Lock=2` bozze (`uspOggetti_upd`, `uspPersone_upd`, `uspRifiutiModelli_get`).
   - Controllo che ignora un ramo di condivisione legittimo (aziende esterne condivise via Area) rispetto a quanto la `_List` corrispondente già mostra (`uspOggetti_get`, `uspPersone_get`, `uspRifiutiAutorizzazioni_get`).
   - Controllo presente sull'entità principale ma assente su un riferimento secondario copiato (`uspRifiutiFormulari_ins` copiava un `@IdModello` altrui senza verificarne il possesso).
   - **Filtro titolarità "fantasma"**: subquery che referenzia una colonna inesistente nella propria FROM — T-SQL la risolve silenziosamente sulla query esterna invece di dare errore di compilazione, producendo un self-comparison sempre vero (`uspRifiutiModelli_get_Etichette_SelectList`, colonna `IdSede` inesistente su `tblRifiutiModelli`). **Sempre sospettare questo pattern quando un filtro WHERE referenzia una colonna il cui nome esiste sia dentro che fuori dalla subquery.**
   - **Pattern standard di fix**: `INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON <tabella>.IdSede = i.Id`, incatenato attraverso Registro/Sede quando serve; aggiungere un secondo ramo OR con `ufnSedi_get_AziendeEsterneCondiviseByUtente_List`/`ufnOggetti_get_CondivisiByUtente_List`/`ufnPersone_get_CondiviseByUtente_List` quando il modulo supporta condivisione cross-azienda (verificare cosa fa già la `_List` gemella).
   - **Quando NON serve**: dati di riferimento statici/globali senza colonna `IdSede`/ownership — verificare sempre lo schema prima di assumere (precedente: `uspOsepe_*`, `uspRifiutiEer_*`, `uspRifiutiMateriali_*`, `tblRifiutiClassiPericolo` — quest'ultimo un'enumerazione normativa UE fissa, decisione confermata dall'utente).
   - **Breaking change**: se il fix richiede aggiungere `@IdSessione` a una SP che non lo aveva, segnalarlo esplicitamente — il chiamante C# deve essere aggiornato (finora sempre owned dall'utente, mai fatto in autonomia).

2. **`@@ROWCOUNT = 0` mancante dopo soft-delete/UPDATE critico** — race condition tra due chiamate concorrenti sullo stesso `@Id`. Trovato ripetutamente (`uspOggetti_del`, `uspPersone_del`, `uspRifiutiAutorizzazioni_del`, `uspRifiutiModelli_del`/`_upd`). Pattern di fix standard:
   ```sql
   IF @@ROWCOUNT = 0
   BEGIN
       ROLLBACK TRANSACTION;
       SET @returnValue = -1; SET @returnMessage = '<Entità> non trovat[o/a] o già eliminat[o/a]';
       GOTO BRANCH_END;
   END
   ```

3. **NULL footgun nei confronti** — `X <> @param` o `X < @param` valuta `UNKNOWN` (non `TRUE`/`FALSE`) quando `@param` è `NULL`, quindi il ramo "correttivo" non scatta mai. Trovato su: paging (`uspRifiutiGiacenze_get_List`, `@PageNumber < 1` non catturava `@PageNumber = NULL` esplicito), esclusione riga selezionata (`Id <> @IdSelected`). Fix: `ISNULL(@param, default)` prima del confronto, oppure `(@param IS NULL OR ...)`.

4. **Riga "selezionata" nascosta dal filtro di ricerca** nelle `_SelectList` — la riga precedentemente selezionata deve restare sempre visibile anche quando `@Search`/paging la escluderebbe altrimenti. Trovato 3 volte (`uspOsepe_get_NonCondivise_SelectList`, `uspRifiutiEer_get_SelectList`, e verificato-assente-per-fortuna in `uspRifiutiMateriali_get_SelectList`). Pattern di fix standard: ramo CTE dedicato `Pos=1 WHERE Id = @IdSelected` (ignora il filtro), ramo generale `Pos=2` con `AND Id <> @IdSelected` per evitare duplicati.

5. **SQL injection via concatenazione del valore invece del nome del parametro** in `sp_executesql` dinamico — anche quando `@params`/il binding sono dichiarati correttamente, se il *valore* runtime viene concatenato nel testo `@stmt` invece del *nome letterale* del parametro, il binding dichiarato è codice morto e il valore resta iniettabile. Trovato una volta (`uspRifiutiModelli_get_List`, aggravato dall'uso della funzione vietata `ufnStringhe_get_PerConcatenazione`) ma **da controllare sempre** in ogni SP con `sp_executesql` — non assumere che un parametro dichiarato in `@params` sia effettivamente usato per il binding.

6. **Stile pre-standard non ancora modernizzato** (SP "vecchie" mai toccate): niente `dbo.` prefix, niente `TRY/CATCH`, niente skeleton `@returnValue`/`BRANCH_END`, `@returnValue = -2` invece di `-1`, rollback manuale via `IF XACT_STATE() ROLLBACK/COMMIT` nel `CATCH` invece del semplice `THROW`, `WITH(NOLOCK)` su viste. Riconoscibile a colpo d'occhio (indentazione a tab, `CREATE` senza `OR ALTER`, `SET NOCOUNT ON` senza `XACT_ABORT`). Sempre presente in almeno una SP per modulo finora — trattare come rumore di fondo da modernizzare, non necessariamente un bug di per sé, ma verificare comunque la logica sottostante (due dei bug più gravi del progetto, SQL injection e filtro fantasma, erano *dentro* SP di questo stile).

7. **Bug copy-paste tra rami paralleli** — blocchi `IF`/`ELSE` quasi identici dove uno dei rami non è stato aggiornato insieme ai gemelli (`uspRifiutiFormulari_upd`, `@IdentificativoTrenoNave1` mai azzerato mentre i campi gemelli lo erano). Quando una SP ha 2-3 blocchi strutturalmente paralleli, confrontarli riga per riga invece di leggerli separatamente.

8. **Tabella sbagliata ma sintatticamente valida** — join/FROM verso una tabella che esiste ed ha una forma plausibile ma non è quella effettivamente referenziata dalla colonna in questione (`uspRifiutiMovimenti_get_Attivita_List` interrogava `tblRifiutiAttivita` invece di `tblRifiutiAttivitaRecuperoSmaltimento`). Non dà nessun errore — solo dati sbagliati. Individuabile solo testando con un valore reale della colonna FK e verificando che esista nella tabella referenziata.

9. **Parametro obbligatorio senza `= NULL` di default** — se un parametro validato con un controllo IS NULL non ha `= NULL` come default nella firma, il controllo non scatta mai se il chiamante lo omette del tutto (SQL Server solleva un errore raw "parameter not supplied" invece del messaggio applicativo friendly). Trovato su parametri data (`@DataInizio`/`@DataFine` in `uspPersone_ins_Ruolo`, `uspRifiutiAutorizzazioni_upd`) — verificare sempre anche se le colonne sottostanti sono nullable a livello di tabella prima di decidere se il parametro deve diventare obbligatorio o restare opzionale con un controllo di range.

10. **`XACT_ABORT`/footer asimmetrico** — la classe di finding più meccanica e frequente: `XACT_ABORT ON` in testa ma footer che fa solo `SET NOCOUNT OFF` (o niente reset affatto) prima di `BRANCH_END`. Quasi sempre presente su almeno metà delle SP di ogni modulo — controllare sempre in batch con `LIKE '%NOCOUNT, XACT_ABORT OFF%'` invece di fidarsi di una lettura a occhio.

### Convenzioni di progetto scoperte durante le revisioni (oltre a `CLAUDE.md`)

- **Codici permesso modulo** (`tblFunzioni`) osservati finora: `RAT` (Autorizzazioni), `RFR` (Formulari), `RMD` (Modelli), `RRG` (Registrazioni), `RCD`/`RCZ`/`RRS`/`RRT`/`RSD` (altri moduli Rifiuti, non ancora mappati 1:1), `APC` (Persone/Anagrafiche). Quando una SP non ha un codice funzione ovvio (es. `uspRifiutiGiacenze_get_List` non aveva nessuna funzione dedicata), **chiedere all'utente** invece di indovinare — non c'è sempre un sibling da cui dedurlo.
- **`Lock` non è sempre `< 2`**: lo standard generale in `CLAUDE.md` è `Lock < 2`, ma alcuni moduli hanno una convenzione locale più stringente (`uspOsepe_*` usa `Lock = 0` ovunque, mai bozze). Controllare sempre cosa fanno le funzioni/i rami sibling della stessa SP prima di applicare la regola generica.
- **Moduli "gemelli" strutturali** condividono la classe di bug ma non necessariamente le istanze: `uspPersone_*` è un quasi-clone di `uspOggetti_*` e aveva **gli stessi identici bug, mai corretti**; `uspRifiutiModelli_*` è un quasi-clone di `uspRifiutiFormulari_*` ma aveva **due bug critici unici** (SQL injection, filtro fantasma) non presenti nel gemello. **Sempre fare il diff completo di un modulo "gemello", mai fare solo pattern-matching sulle classi di bug già note.**
- **`tblRifiutiRegistrazioniRelazioni`**: `Id` = figlio, `IdParent` = padre. Il pattern di verifica quantità già scaricata deve agganciare lo stato (`Lock`) del **padre** (`rp.Id = l.IdParent`), non del record corrente (`r.Id = l.Id`) — bug ricorrente documentato in `CLAUDE.md`, da verificare esplicitamente in `uspRifiutiRegistrazioni_*` (prossimo modulo).

---

## Moduli rivisti e chiusi

### uspOggetti_* (8 SP)
- **`uspOggetti_get`**: il controllo di ownership permetteva solo gli oggetti delle aziende interne (`ufnSedi_get_AziendeInterneByUtente_List`), ignorando gli oggetti condivisi da altre aziende via Area — negava l'accesso ad oggetti visibili in `uspOggetti_get_List`. Fix: aggiunto secondo ramo `NOT EXISTS` su `ufnOggetti_get_CondivisiByUtente_List`.
- **`uspOggetti_del`**: mancava il controllo `@@ROWCOUNT = 0` dopo l'`UPDATE ... Lock = 4` (race condition). Fix aggiunto, pattern standard.
- **`uspOggetti_del`**: (trovato dall'utente) non controllava `tblServiziOsepe` prima del soft-delete, solo `tblScadenzeOsepe`/`tblAreeOsepe` — un oggetto associato a un servizio attivo poteva essere cancellato. Fix: aggiunto controllo `EXISTS` mancante.
- **`uspOggetti_get`/`uspOggetti_get_List`**: mancava `XACT_ABORT`. Fix aggiunto.
- **`uspOggetti_upd`**: il controllo ownership proteggeva solo `Lock=0`, non `Lock=2` (bozze) — una bozza di un'altra azienda poteva essere completata se si conosceva/indovinava l'Id. Fix: check unico `Lock <= 2`.
- **CLAUDE.md aggiornato**: chiarita la convenzione `uspId_get`/`@NoLog` per Id primario vs secondario (non era un bug, era la doc obsoleta).
- **Aperto**: il ramo `Lock=2` (cancellazione bozza) di `uspOggetti_del` pulisce solo `tblAreeOsepe`, non `tblScadenzeOsepe`/`tblServiziOsepe`. Probabilmente innocuo (le bozze non sono linkabili da UI prima della finalizzazione) ma non verificato a fondo — da riconsiderare se riemerge.

### uspOsepe_* (2 SP)
- **`uspOsepe_get_NonCondivise_SelectList`**: `@IdSelected` dichiarato ma mai usato — l'elemento selezionato poteva sparire dalla select se fuori dai primi 50 risultati. Fix: aggiunto ramo CTE `Pos=1` dedicato, come nel sibling.
- Mancava `SET NOCOUNT, XACT_ABORT OFF;` nel footer (`_get_SelectList`) e `XACT_ABORT` del tutto (`_get_NonCondivise_SelectList`). Fix applicati.
- Mancava `OPTION (RECOMPILE)` su entrambe. Fix aggiunto.
- I tre rami "Selected" di `uspOsepe_get_SelectList` non filtravano su `Lock` — un record Lock=2/4 preselezionato restava visibile. Fix: allineato a `Lock = 0` (convenzione locale più stringente di `Lock < 2`, confermata verificando le funzioni sottostanti).
- Decisioni prese, nessuna azione: nessuna delle due SP chiama `uspSessione_get_FunzionePermesso` (confermato ok, gate delegato al modulo chiamante); `@Contesto = -1` di default e branch 0 "Dominio" non implementato — verificato non essere un problema di sicurezza (le funzioni sottostanti scopano già per azienda).
- **Lezione**: controllare la convenzione `Lock` dei sibling/funzioni della stessa SP prima di applicare la regola generica `Lock < 2`.

### uspPersone_* (10 SP)
Modulo quasi identico a `uspOggetti_*` — stessi bug classe per classe, mai corretti:
- `uspPersone_get`: stesso gap di ownership di `uspOggetti_get` #1 — fix analogo (`ufnPersone_get_CondiviseByUtente_List`).
- `uspPersone_del`: mancava `@@ROWCOUNT`; mancava check `tblServiziOsepe`. Entrambi fixati.
- `uspPersone_upd`: stesso gap Lock=2 di `uspOggetti_upd`. Fix: check unico `Lock <= 2`.
- Mancava `XACT_ABORT` su 4 SP, footer asimmetrico su altre 6. Fix applicati a tutte e 10.
- **`uspPersone_get_Ruoli_List` — IDOR reale**: nessun `@IdSessione`, nessun controllo permesso/ownership — chiunque conoscesse l'Id di una Persona poteva leggerne i ruoli di qualsiasi azienda. Fix: aggiunto `@IdSessione`, permesso APC≥1, titolarità. **Breaking change** — caller da aggiornare (owned dall'utente).
- `uspPersone_get_UnitaMisura_SelectList`: mancava skeleton `@returnValue`/`BRANCH_END`. Aggiunto per uniformità (non un bug funzionale).
- `uspPersone_ins_Ruolo`: `@DataInizio`/`@DataFine` senza default (errore SQL raw se omessi), nessun controllo range. Fix: default `NULL` + controllo `DataInizio > DataFine`.

### uspRifiutiAutorizzazioni_* (26 SP) — modulo più esteso e con il gap di titolarità più sistemico
- **`uspRifiutiAutorizzazioni_upd`**: nessun controllo di titolarità su `@Id` — un'autorizzazione di un'altra azienda (senza movimenti attivi) poteva essere modificata o riassegnata liberamente da chiunque con permesso RAT≥2 generico. Fix: check ownership incondizionato.
- **`uspRifiutiAutorizzazioni_get`**: titolarità incompleta — il check scattava solo per `Lock=0` (non per le bozze `Lock=2`) e ignorava le sedi esterne condivise. Fix: check reso incondizionato + aggiunto ramo condivise.
- **9 SP satellite** (`_ins/_upd/_del_Conducente/Eer/Targa`, `_upd_Attivita`): controllavano solo il permesso generico RAT≥2, mai che l'autorizzazione padre appartenesse all'azienda della sessione. Fix: stesso check ownership su tutte e 9.
- **10 SP di sola lettura** (`_get_Attivita_List`, `_get_Conducente[i]`, `_get_Eer_List`, `_get_IdSede`, `_get_Targa[Eer]/[he]`, `_get_Targhe_SelectList`): **nessun controllo di sessione/permesso/titolarità affatto** — chiamabili col solo `@Id`. Fix: aggiunto `@IdSessione`, permesso RAT≥1, titolarità duale (sedi interne OR condivise). **Breaking change su 10 call site** (owned dall'utente).
- `uspRifiutiAutorizzazioni_del`: mancava `@@ROWCOUNT`. Fix aggiunto.
- `XACT_ABORT` mancante su `_get_List`; footer asimmetrico su altre 13. Fix applicati.
- `@DataInizio`/`@DataFine` su `_upd` senza default/range check. Fix analogo a `uspPersone_ins_Ruolo`.
- **Follow-up trovato dall'utente**: il check di ownership aggiunto su `_upd` includeva `AND a.Lock <= 2`, negando erroneamente l'accesso a un'autorizzazione già cancellata con un messaggio fuorviante ("condivisa da altre aziende") invece del corretto "non trovata/già eliminata". Fix: rimosso `Lock <= 2` dal check di ownership, lasciato solo sul controllo `@@ROWCOUNT`.

### uspRifiutiDocumentiTrasportiTipi_get_SelectList + uspRifiutiEer_* (3 SP, dati di riferimento statici/nazionali, no titolarità)
- `uspRifiutiDocumentiTrasportiTipi_get_SelectList`: la SP più fuori standard vista in tutto il progetto (niente `dbo.`, niente TRY/CATCH, niente skeleton, indentazione a tab). Riscritta da zero secondo lo standard.
- `uspRifiutiEer_get_List`/`_get_SelectList`: mancava skeleton `@returnValue`/`BRANCH_END`, `SET NOCOUNT OFF`, `OPTION (RECOMPILE)`. Fix applicati.
- **`uspRifiutiEer_get_SelectList`**: la riga "selezionata" era soggetta allo stesso filtro `@Search` della lista generale (spariva cercando altro). Fix: ramo dedicato `WHERE Id = @IdSelected` sempre visibile, come nel resto della codebase.

### uspRifiutiFormulari_* (7 SP) — gap più grave del progetto (documento legale regolamentato)
- **`uspRifiutiFormulari_upd`**: **nessun controllo di titolarità** sulla SP più grande e critica del modulo — chiunque con permesso RFR≥2 poteva riscrivere completamente il Formulario (documento legale RENTRI) di un'altra azienda. Fix: check ownership via `IdMovimento → IdRegistro → IdSede`.
- **`uspRifiutiFormulari_del`**: stesso gap, sia ramo Lock=0 che Lock=2. Fix analogo.
- Mancava `dbo.` prefix, `WITH(NOLOCK)` su vista (espansa nelle tabelle base per predicate pushdown), `@returnValue = -2` invece di `-1`, rollback manuale via `XACT_STATE()` invece del pattern standard — tutto in `_del`/`_del_Undo`/`_get_Etichette_SelectList` (stile SP più vecchio del modulo). Fix applicati.
- Parametri obbligatori senza default `= NULL` + check esplicito. `_get_Etichette_SelectList` senza TRY/CATCH/skeleton del tutto. `XACT_ABORT`/footer mancanti su `_get`/`_get_List`/`_ins`. Fix applicati a tutti.
- **Bug copy-paste**: `@IdentificativoTrenoNave1` non veniva mai azzerato per trasporti non treno/nave (ramo `IF`/`ELSE` identico, a differenza dei pattern gemelli). Fix: `ELSE SET ... = NULL`.
- Investigato (non un bug): `@IdTipoTrasporto1 <> 'G'/'T'` degenera a `UNKNOWN` se NULL, ma confermato dall'utente che non può mai arrivare NULL dalla UI (picklist senza placeholder "(Selezionare)").
- **`uspRifiutiFormulari_ins`**: nessuna verifica di titolarità su `@IdModello` — si poteva copiare silenziosamente EER/autorizzazioni/imballo/ADR/etichette del Modello di un'altra azienda in un nuovo Formulario proprio. Fix: check ownership mirror di `uspRifiutiModelli_get`.

### uspRifiutiGiacenze_get_List (1 SP)
- **Nessun controllo di titolarità/permesso affatto** — chiunque conoscesse/indovinasse `@IdRegistro` poteva leggere le giacenze di un'altra azienda, senza nemmeno un permesso generico richiesto. Fix: aggiunto `@IdSessione`, permesso RRG≥1 (confermato dall'utente, nessuna funzione dedicata esisteva), titolarità via `ufnSedi_get_SediInterneBySessione_List`. **Breaking change**.
- Footer asimmetrico (mancava `XACT_ABORT OFF`). Fix.
- `@PageNumber`/`@RowsPerPage < 1` non catturava `NULL` esplicito (`UNKNOWN`, non correggeva, `OFFSET NULL ROWS` avrebbe fallito). Fix: `ISNULL(..., default)` prima del controllo `< 1`.

### uspRifiutiMateriali_get_SelectList (1 SP, dati statici, no titolarità)
- Nessun bug di logica — pattern "selected" già corretto. Solo skeleton (`@returnValue`/`BRANCH_END`) e footer `XACT_ABORT OFF` mancanti. Fix applicati.

### uspRifiutiModelli_* (9 SP) — due bug critici unici nel progetto
- **SQL injection in `uspRifiutiModelli_get_List`**: usava la funzione vietata `ufnStringhe_get_PerConcatenazione`, e nonostante `sp_executesql` avesse già un parametro `@Search` dichiarato correttamente, il codice concatenava il **valore** di `@Search` direttamente nel testo SQL dinamico invece di referenziare il **nome** del parametro — il binding dichiarato era codice morto, exploitabile. Fix: concatenato il nome letterale `@Search` (con virgolette raddoppiate) così viene risolto come parametro bindato da `sp_executesql`; normalizzazione sostituita con `NULLIF(LTRIM(RTRIM(...)))`.
- **Filtro titolarità fantasma in `uspRifiutiModelli_get_Etichette_SelectList`**: `WHERE t.IdSede = (SELECT IdSede FROM tblRifiutiModelli WHERE Id = @Id)` referenziava una colonna (`IdSede`) inesistente su `tblRifiutiModelli` — T-SQL la risolveva silenziosamente sulla query esterna, rendendo il filtro un self-comparison sempre vero (nessun errore di compilazione/esecuzione). Confermato empiricamente: restituiva tutte le 5 etichette RIF del DB indipendentemente dal Modello. Fix: join reale su `tblRifiutiRegistri`, mirror del pattern corretto in `uspRifiutiFormulari_get_Etichette_SelectList`.
- Gap di titolarità sistemici su `_upd`/`_del`/`_get` (check assente o parziale solo su `Lock=0`) e su `_get_ClassiPericolo_List`/`_get_Etichette_SelectList` (nessun `@IdSessione`). Fix applicati con lo stesso pattern.
- Modernizzazione completa del resto (dbo. prefix, no `-2`, no `XACT_STATE()` manuale, default/check obbligatori, skeleton, `XACT_ABORT`). Trovati "in omaggio" 2 `@@ROWCOUNT` mancanti su `_del`/`_upd`, fixati.
- `uspRifiutiModelli_get_SelectList`: mancava `OPTION (RECOMPILE)`. Fix.
- **Decisione presa (revertita su richiesta utente)**: l'aggiunta di `@IdSessione`/titolarità a `uspRifiutiModelli_get_ClassiPericolo_List` è stata **annullata** — `tblRifiutiClassiPericolo` è un'enumerazione normativa UE fissa (HP01-HP15), non dato proprietario; il rischio di esporre solo dei checkmark contro una lista pubblica non giustifica il breaking change. Mantenuta solo la modernizzazione dello skeleton.

### uspRifiutiMovimenti_* (4 SP)
- **`uspRifiutiMovimenti_get_Attivita_List` — due bug sovrapposti**: (a) `@Id` dichiarato ma mai usato, `[Checked]` sempre `0`; (b) **bug più profondo trovato testando il primo fix**: la SP interrogava la tabella sbagliata (`tblRifiutiAttivita`, 6 codici a lettera singola) invece di `tblRifiutiAttivitaRecuperoSmaltimento` (i veri codici R/D referenziati da `tblRifiutiMovimenti.IdAttivita`) — confermato con un movimento reale (`IdAttivita='56'` = R6, presente solo nella seconda tabella) e per coerenza con `uspRifiutiAutorizzazioni_get_Attivita_List`. **Lezione**: verificare sempre i fix con dati reali anche quando sembrano ovviamente corretti — un bug più profondo può nascondersi dietro il primo.
- `uspRifiutiMovimenti_get_ClassiPericolo_List`/`_get_TrasportiTipi_SelectList`: modernizzazione skeleton, no titolarità (dati statici, stesso precedente di ClassiPericolo su Modelli). Confermato che `_get_TrasportiTipi_SelectList` non ha placeholder "(Selezionare)" by design (`@IdTipoTrasporto1` non può arrivare NULL dalla UI).
- **`uspRifiutiMovimenti_del_All`**: confermato dall'utente essere una utility di reset per solo test/dev, mai raggiungibile in produzione — nessuna azione, non ri-segnalare in future revisioni.

### uspRifiutiOperazioni_get_SelectList / uspRifiutiProvenienze_get_SelectList / uspRifiutiRaee_get_SelectList (3 SP)
- Nessun bug di logica in nessuna delle tre — solo modernizzazione skeleton (`CREATE OR ALTER`, `ANSI_NULLS`/`QUOTED_IDENTIFIER`, `XACT_ABORT`, `@returnValue`/`BRANCH_END` dove mancante).
- **Decisione presa**: `uspRifiutiOperazioni_get_SelectList` hardcoda `Selected=1` sul placeholder / `Selected=0` su tutte le righe reali, ignorando qualunque `@IdSelected` (non lo prende nemmeno come parametro) — **confermato intenzionale dall'utente**: usata solo per nuovi inserimenti, dove nulla deve essere preselezionato. Non ri-segnalare.
- `tblRifiutiProvenienze`/`tblRifiutiRaee` confermate dati di riferimento statici, no titolarità necessaria.

### uspRifiutiRegistrazioni_* (19 SP) — gap di titolarità più esteso del progetto insieme a Formulari
- **Pattern padre/figlio (`tblRifiutiRegistrazioniRelazioni`) verificato esplicitamente in tutta la SP**: implementato **correttamente ovunque** (join su `IdParent`/Lock del padre quando si verifica un figlio, join su `Id`/Lock del figlio quando si verifica un padre) — nessun bug di questa classe trovato. `uspRifiutiRegistrazioni_upd` contiene l'esempio di riferimento esatto del pattern documentato in `CLAUDE.md`.
- **Titolarità/IDOR sistemico** — quasi tutte le SP di scrittura e metà di quelle di lettura non verificavano che l'entità appartenesse all'azienda della sessione (solo permesso generico RRG):
  - `_upd` (la SP più grande/critica del modulo), `_del`, `_ins` (rami `@IdFormulario` e `@IdModello`, stesso pattern già trovato in `uspRifiutiFormulari_ins`), `_ins_Relazione`, `_ins_RelazioniTutte`, `_del_Relazione`: aggiunto check ownership via `ufnSedi_get_SediInterneBySessione_List` incatenato su Registrazione→Movimento→Registro→Sede (nessuna nuova firma parametro, `@IdSessione` già presente).
  - `_del_Undo`: mancava il controllo di permesso funzione RRG del tutto (asimmetrico rispetto a `_del`). Fix aggiunto.
  - 7 SP di sola lettura senza `@IdSessione`/permesso/titolarità affatto: `_get_RegistrazioniAssociate_List`, `_get_RegistrazioniDaAssociare_List`, `_get_RegistrazioniRelazioni_List`, `_get_Etichette_SelectList` (esponevano dati reali), `_get_IsDataPrecedente`, `_get_IsQuantitaSuperiore`, `_get_UltimoNumero` (oracoli bool/int). **Breaking change su tutte e 7** — nuovo parametro `@IdSessione` obbligatorio, caller C# da aggiornare (owned dall'utente).
- **Race condition (`@@ROWCOUNT` mancante)**: `_del` CASO 1 (dopo `UPDATE ... Lock=4`) e `_del_Relazione` CASO 2 (dopo la seconda `DELETE`, prima di forzare `Lock=1` sul padre). Fix aggiunti, pattern standard.
- **NULL footgun**: `_upd`, `IF @IdCausaleRespingimento <> 'A' SET @CausaleRespingimentoAltro = NULL;` non azzerava `CausaleRespingimentoAltro` se `@IdCausaleRespingimento` era `NULL` (Esito='R' senza causale specificata). Fix: `ISNULL(@IdCausaleRespingimento, '') <> 'A'`.
- **`_upd_Numerazione`**: SP nello stile pre-standard, riscritta — `@returnValue=-2`→`-1`, CATCH custom→`THROW;`, `WITH(NOLOCK)` su vista (`viewRifiutiRegistrazioni`) espansa sulle tabelle base (`tblRifiutiRegistrazioni`/`tblRifiutiMovimenti`/`tblSessioni`).
- `_ins_RelazioniTutte`: rimosso anche `WITH(NOLOCK)` su tabelle base nel calcolo posizioni (non una violazione esplicita dello standard, ma rischio di dirty-read su un calcolo di quantità — rimosso su richiesta utente).
- `XACT_ABORT` assente del tutto (non solo asimmetrico) su tutte le SP di sola lettura del modulo; footer completamente mancante su `_get`/`_ins`. Fix applicati a tutte e 19.
- Deploy verificato in batch (ANSI_NULLS/QUOTED_IDENTIFIER/CRLF/XACT_ABORT) + smoke test con sessione a basso privilegio: tutte le 19 SP negano correttamente senza errori SQL.
- **Non fixato su richiesta utente**: `_upd` non filtra le etichette inserite (`@IdEtichette`) per `IdSede` come fa il picker `_get_Etichette_SelectList` — impatto giudicato trascurabile.

### uspRifiutiRegistrazioniEsiti_get_SelectList (1 SP, dato statico, no titolarità)
- Nessun bug di logica: pattern placeholder "(Selezionare)" + `UNION ALL` + `ORDER BY Pos` globale già corretto. `tblRifiutiRegistrazioniEsiti` è dato di riferimento statico (Id/Codice/Nome/Pos, nessuna colonna IdSede).
- Solo skeleton mancante (stesso trattamento di `_get_EsitiCausaliRespingimento_SelectList`/`_get_TrasportiTransfrontalieriTipi_SelectList`): aggiunto `@returnValue`/`BRANCH_END`, `XACT_ABORT`. Fix applicato e verificato.

### uspRifiutiRegistri_* (9 SP) — contenitore padre di Registrazioni/Movimenti/Formulari
- **`uspRifiutiRegistri_upd`** — finding più grave: nessun controllo di titolarità affatto (chiunque con RRT≥2 poteva riscrivere Nome/IdTipo di un Registro altrui); più un bug reale nel controllo duplicati-nome: `@IdSede` era un parametro **client-supplied obbligatorio** usato solo nella `EXISTS` anti-duplicato (mai nella `SET` della UPDATE) — un `@IdSede` stale/errato dal chiamante faceva cercare il duplicato nella sede sbagliata. Fix: `@IdSede` **rimosso dalla firma** (breaking), il controllo duplicati ora usa la vera `IdSede` del record derivata dal check di titolarità. Aggiunto anche `@@ROWCOUNT` mancante dopo la UPDATE.
- `_del`: titolarità assente del tutto + `@@ROWCOUNT` mancante dopo soft-delete. Fix applicati.
- `_del_Undo`: nessun controllo permesso — **confermato by-design** (convenzione di progetto: tutti i `_del_Undo` ripristinano solo ciò che la sessione stessa ha cancellato, scope via `tblIdCancellati.IdSessione`, nessun gate aggiuntivo necessario).
- `_get`/`_get_List`: `XACT_ABORT` assente del tutto; NULL footgun su `@PageNumber`/`@RowsPerPage < 1` in `_get_List` (stesso pattern Giacenze). Fix applicati. `_get_List` filtra per `IdSede` esatta della sessione anziché tutte le sedi interne — **confermato intenzionale dall'utente** (scope più stretto per la vista lista), non un gap.
- `_get_SelectList`: skeleton assente, `@IdSessione` senza default/check, permesso RRT≥1 assente. Fix applicati; semplificata a chiamare `ufnSedi_get_SediInterneBySessione_List` direttamente (era logicamente equivalente ma ridondante, non un bug di sicurezza).
- `_get_Tipi_SelectList`/`_get_UnitaMisura_SelectList`: dati statici, no titolarità. Solo skeleton.
- `_ins`: footer `XACT_ABORT OFF` completamente assente. Fix applicato; `uspId_get` già corretto (Id primario, no `@NoLog`).
- **Breaking**: `_upd` ha perso `@IdSede`; `_get_SelectList` ha `@IdSessione` ora effettivamente obbligatorio.
- **Follow-up 2026-08-13 (cambio schema, non finding di revisione)**: `tblRifiutiRegistri.IdUnitaMisura` rimossa dalla tabella (colonna droppata, non spostata — diversa dal fatto CLAUDE.md su `tblRifiutiRegistrazioni`/`tblRifiutiMovimenti`). Rimossa da `_get` (SELECT) e `_upd` (parametro `@IdUnitaMisura` intero, breaking) per allinearsi allo schema reale.

### uspRifiutiRuoli_get_SelectList / uspRifiutiStatiFisici_get_SelectList / uspRifiutiUnitaMisura_get_SelectList / uspRuoli_get_SelectList (4 SP, dati statici, no titolarità)
- Nessun bug di logica in nessuna delle 4. Solo skeleton/header/footer.
- `uspRuoli_get_SelectList` la più fuori standard: nessun TRY/CATCH, `tblRuoli` senza `dbo.` prefix, `@IdSelected` non normalizzato. Fix applicati. Investigato: non ha un placeholder "(Selezionare)" sintetico ma `Id='AA', Nome='(Altro)'` è una riga reale che l'ordinamento colloca comunque per prima grazie alla collation — equivalente funzionale, non un bug.

### uspScadenze_* (16 SP) — gap di titolarità più esteso trovato fino a questo punto
Catena titolarità: `tblScadenze → tblEventi(IdCalendario) → tblCalendari(IdSede)`.
- **`uspScadenze_upd`**: nessun controllo titolarità — chiunque con SCD≥2 poteva riscrivere una scadenza altrui conoscendo solo `@Id`/`@IdEvento`. Fix: `NOT EXISTS` standard su entrambi.
- **`uspScadenze_ins`** — bug di **data-integrity**, non solo lettura: quando `@IdEvento` è passato (nuova occorrenza di evento ricorrente esistente), `@idCalendario` veniva letto da `tblEventi.IdCalendario` senza verificarne il possesso — un'azienda poteva piantare una scadenza fabbricata nel calendario di un'altra azienda. Fix: gate del lookup dietro lo stesso controllo di titolarità.
- `_del`, `_ins_Osepe`, `_del_Osepe`: nessun controllo titolarità su `@Id` (Scadenza). Fix applicati a tutte.
- `_get_Etichette_SelectList`, `_get_Osepe_List`, `_get_IsRicorrente`: `@IdSessione`/permesso/titolarità assenti del tutto. Fix: aggiunto `@IdSessione` (**breaking** su tutte e 3) + permesso SCD + titolarità.
- `_ins`/`_ins_Osepe`: `@returnValue = -2` (vietato) su fallimento permesso/validazione. Fix a `-1`.
- Skeleton/footer mancanti su più SP (`get_CalendarioGiorno/Mese/Settimana_List`, `get_List`, `upd`). Fix applicati a tutte e 16.
- **By-design, nessuna azione**: `_del_All` (utility reset dev/test, stesso precedente di `uspRifiutiMovimenti_del_All`); `_del_Undo` (nessun gate, convenzione progetto); le `_get_*List` calendario scopano per `tblSessioni.IdCalendario` (singolo calendario della sessione), non tutte le sedi — consistente in tutti e 5 i sibling.
- **Lasciato aperto, non risolto**: le SP calendario costruiscono JSON via concatenazione manuale di stringhe, escapando solo `"` non `\` — un testo con backslash (es. `C:\Depositi\Nord`) produrrebbe JSON invalido. Ripetuto identico in 3 SP. Richiederebbe una riscrittura più ampia (`FOR JSON PATH`/`STRING_ESCAPE`) — non affrontato, rivalutare se riemerge. **Stesso bug notato in `uspServizi_*` (vedi sotto)**.

### uspSedi_* (17 SP) — gap più grave trovato fino a questo punto: radice della gerarchia multi-tenant
Gestisce `Dominio → tblSediInterne (azienda) → tblSedi` (sia `InternaEsterna='I'` che `'E'`). Titolarità per `'I'` è per **Dominio** (Admin stesso Dominio, o Admin di un Dominio `Master=1` — bypass cross-Dominio **intenzionale, confermato dall'utente** per supporto/oversight).
- **Gap sistemico**: ogni SP di scrittura col ramo `'I'` non aveva **alcun** controllo, mentre il ramo `'E'` parallelo nella stessa SP era sempre corretto — pattern ripetuto identico in 4 SP (`_del`, `_del_SediInterne`, `_ins` per `@IdParent`, `_upd`). Fix: inserito ovunque il check corretto già presente in `uspSedi_get` (Admin stesso Dominio OR Admin Dominio Master), con commento inline a spiegare il bypass intenzionale.
- `_upd`: anche `@InternaEsterna`/`@IdTipo` senza `= NULL` default/check — un `@InternaEsterna` NULL avrebbe bypassato **entrambi** i rami titolarità. Fix aggiunto. **Bug pre-esistente trovato via smoke test**: nessun controllo "non trovato" prima del gate titolarità — un `@Id` inesistente faceva fallire silenziosamente il check (short-circuit su `EXISTS(...Lock=0)`) e proseguiva fino a un errore SQL raw di FK invece del messaggio friendly. Riprodotto anche sul ramo `'E'` originale non toccato — pre-esistente, non introdotto dal fix. Fix: aggiunto controllo `NOT EXISTS ... Lock <= 2 → 'Sede non trovata'` prima di entrambi i rami.
- `uspSedi_get_SediAssociate_List`: nessun `@IdSessione`/permesso/titolarità — dato solo `@Id` esponeva nomi/indirizzi di sedi figlie di qualunque azienda. Fix: aggiunto `@IdSessione` (**breaking**), mirror del pattern dual-branch di `uspSedi_get`.
- Skeleton assente del tutto su `_get_Recapiti_SelectList`/`_get_Tipi_SelectList` (dati statici, no titolarità). Fix applicato.
- **Follow-up 2026-08-13 (audit FK completezza soft-delete, `Lock=0`)**: `tblRifiutiAutorizzazioni.IdSede` non controllato da nessuna delle 3 SP `_del*`, con righe attive reali su entrambi i rami — confermato sfruttabile, non teorico. Fix su `_del_SediEsterne`/`_del_SediInterne`. **`uspSedi_del` confermato non più usato dall'applicazione** — lasciato completamente non toccato (stesso trattamento riservato a SP morte altrove nel progetto). Confermato by-design: `_del_SediEsterne` non controlla Oggetti/Persone (impossibile associarli a una sede Esterna, confermato dall'utente).
- **Follow-up 2026-08-13 (stesso audit esteso a `Lock=2`, hard-delete fisico)**: tutte le 22 FK di primo livello su `tblSedi` sono `NO_ACTION` (nessun cascade automatico). Aggiunti guard/block per `tblServizi.IdRichiedente`/`tblScadenzeOsepe` (record business, bloccare non cancellare) e cascade-delete per `tblOggetti`/`tblPersone` solo su `_SediInterne` (Esterna confermata impossibile) in entrambe le SP.
- **Lasciato aperto**: `tblSediIndirizzi`/`tblSediRecapiti` mai toccate in nessun ramo (rischio basso, popolate solo via `_upd` che finalizza sempre `Lock=0`); guard `tblSedi.IdParent` (figli) nel ramo `Lock=2` non pienamente chiuso per `'E'`. `@IdTipo` di `uspSedi_del` sembra dead param ma non rimosso (in attesa di conferma). Rivalutare se riemergono.
- **Breaking**: `uspSedi_get_SediAssociate_List` ha ora `@IdSessione` obbligatorio.
- **Lezione**: quando un modulo ha "due varianti della stessa entità" (qui Interna/Esterna), verificare sempre **entrambi** i rami indipendentemente — non assumere che se un ramo è corretto l'altro lo sia altrettanto.

### uspServizi_* (16 SP) — sibling quasi identico di uspScadenze_*
Stessa forma/catena titolarità di Scadenze (`Servizio → Evento → Calendario → Sede`), stessi gap replicati 1:1: `_upd` (zero check), `_ins` (stesso data-integrity IDOR su `@IdEvento`), `_del`, `_ins_Osepe` (nessun check titolarità), `_get_Etichette_SelectList`/`_get_Osepe_List`/`_get_IsRicorrente` (nessun `@IdSessione` — **breaking** su tutte e 3, gap già previsto durante la revisione di Scadenze).
- **`uspServizi_del_Osepe`** — riscritta completamente, SP più vecchia mai vista nel modulo: `-2` invece di `-1`, rollback manuale via `XACT_STATE()`, nessun `dbo.` prefix, nessun default/check sui parametri, messaggio errore custom invece di `THROW`. Riscritta da zero secondo lo standard, mirror di `uspScadenze_del_Osepe`.
- `_ins_Osepe`: `@Quantita` senza default/check obbligatorietà. Fix aggiunto.
- **By-design**: `_del_All` (dev/test), `_del_Undo` (nessun gate), scoping per `tblSessioni.IdCalendario` nelle `_get_*List` calendario.
- **Lasciato aperto** (stessa decisione presa su Scadenze): stesso bug di JSON malformato su backslash non escapato nelle 3 SP calendario.
- **Breaking**: `_get_Etichette_SelectList`/`_get_Osepe_List`/`_get_IsRicorrente` ora richiedono `@IdSessione`.

### uspServiziAssegnati_* (6 SP) — variante per-tecnico di uspServizi_* (permesso SRA)
Assegnazione via `tblEventiUtenti` (utente tecnico assegnato a un evento/servizio).
- `_get` già corretto (titolarità standard via sede); `_get_List` scopa per utente via `ufnEventi_get_Assegnati_List`; `_ins` completamente self-scoped (proprio calendario/utente, nessun Id esterno fidato) — confermati by-design, nessuna azione.
- **`_upd`**: nessun controllo titolarità affatto (nemmeno tentato) — chiunque con SRV≥2 o SRA≥2 poteva riscrivere firme/stato di qualunque servizio assegnato nel sistema, non solo il proprio. Fix: stesso blocco `NOT EXISTS` già presente in `_get`.
- **`_del`**: stesso gap (solo permesso, nessuna ownership). Fix identico.
- `_del_Undo`: nessun gate, convenzione progetto.
- Skeleton/footer fix su tutte e 6. **Nessun breaking change** (nessuna SP ha cambiato firma).

### uspSessioni_* / uspSessione_get_FunzionePermesso (6 SP) — infrastruttura sessione/permessi
Modulo più pulito finora: nessun gap di titolarità, nessun bug `-2`, nessuna SP pre-standard da riscrivere.
- **`uspSessione_get_FunzionePermesso`**: deviazione intenzionale dallo skeleton standard, **lasciata intoccata tranne sintassi** (solo `CREATE OR ALTER`) — su qualunque errore imprevisto imposta `@Permesso = 0` (deny) invece di THROW, con commento esplicativo già presente ("un THROW qui romperebbe ogni catena chiamante"); gestisce correttamente la race condition di inserimento cache con `WITH (UPDLOCK)` + cattura errori 2627/2601. **Istruzione durevole**: non "correggere" questa SP nella forma standard in future revisioni.
- `uspSessioni_get_IdContesto`/`_ins`/`_upd`: solo skeleton fix.
- `uspSessioni_upd_AziendaByContesto`: skeleton fix + **fix approvato dall'utente**: `@@ROWCOUNT = 0` mancante dopo la UPDATE (ramo `@Contesto=3`/Registro) — prima falliva silenziosamente se la sessione non aveva `IdRegistro` impostato.
- **`uspSessioni_upd_AziendaByRegistro`**: **confermato non più usato dall'applicazione** (verificato dall'utente nel codice C#) — lasciato completamente intoccato, nessun `CREATE OR ALTER`.
- Nessun breaking change.

### uspTipi_* (11 SP) — gap di titolarità più ampio in rapporto (6 di 11 SP)
Gestisce `tblTipi`/`tblTipiProprieta`. `tblTipi.IdSede` può essere `NULL` ("tipi globali", visibili solo via `_get_SelectList`) — confermato dall'utente che i tipi globali non si aprono mai individualmente via `_get`, quindi l'`INNER JOIN` su `IdSede` che li esclude è by-design.
- **Bug reale trovato — `uspTipi_upd_ProprietaPosizione`**: dopo un riordino riuscito (`@mosso=1`), il codice faceva `SET @returnValue = -1;` senza impostare `@returnMessage` — `BRANCH_END` faceva THROW con il messaggio di default "Database exception" **dopo che il riordino era già stato committato**. Impatto concreto: la UI mostrava un errore nonostante il successo; un retry dell'utente spostava di nuovo la proprietà, corrompendo silenziosamente l'ordine. Fix: rimossa la riga erronea.
- `_del`, `_del_Proprieta`, `_ins_Proprieta`, `_upd`, `_upd_ProprietaPosizione`, `_get_Proprieta_List`: nessun controllo titolarità. `_get_Proprieta_List` inoltre senza `@IdSessione` del tutto — fix con `@IdSessione` (**breaking**) + permesso TPO + titolarità.
- `_del`: anche `@returnValue = -2` (vietato) su fallimento permesso. Fix a `-1`.
- **`_upd`** — stesso flaw class di `uspRifiutiRegistri_upd`: `@IdSede` client-supplied usato solo nel controllo duplicati, mai nella UPDATE, nessuna titolarità affatto. Fix: `@IdSede` **rimosso dalla firma** (breaking), titolarità + duplicato derivati dalla vera sede del record; aggiunto anche `@@ROWCOUNT` mancante.
- Fix minore: `uspTipi_get_SelectList` aveva `@IdModulo CHAR(16)` invece di `CHAR(3)` (copy-paste, innocuo ma corretto per coerenza); `@Verso INT` di `_upd_ProprietaPosizione` senza default/check.
- Skeleton/footer fix su tutte e 11.
- **Breaking**: `_get_Proprieta_List` ha ora `@IdSessione` obbligatorio; `_upd` ha perso `@IdSede`.

### uspUrlNavigazione_* (2 SP) — cronologia back-button per sessione
Interamente self-referenziale alla propria `@IdSessione` (stesso modello "Id sessione = bearer token" di `uspSessioni_*`) — nessun gap di titolarità, nessun permesso necessario (bookkeeping UI, non dato business). Nessun bug di logica (verificato via smoke test truncation/fallback). Solo skeleton fix. Nessun breaking change.
- **Nota operativa**: la sessione di test a basso privilegio riusata in questa serie di revisioni può scadere/essere ripulita dal cleanup a 24h di `uspSessioni_ins` — prendere una sessione fresca se il test fallisce con FK violation su `tblSessioni`.

### uspDomini_* (17 SP) — radice tenant, gate "Admin di Dominio Master"
Nessun gap di titolarità: ogni SP di scrittura e quasi tutte quelle di lettura hanno già il check corretto "Admin di un Dominio Master" (`tblSessioni→tblUtenti→tblDomini WHERE Master=1`) — modello diverso dal resto del progetto (qui non esiste "propria azienda", Domini stessa è il confine di tenant).
- **Correzione di metodologia importante**: `sys.sql_modules.definition` **normalizza silenziosamente `CREATE OR ALTER` in `CREATE`** (spazi extra al posto delle parole rimosse) indipendentemente da come la SP è stata effettivamente deployata — verificato su una SP appena deployata con `CREATE OR ALTER` esplicito in questa stessa sessione. **Non usare mai più questo check come diagnostica**: non è possibile verificare "manca CREATE OR ALTER" leggendo la definizione a posteriori. Non invalida le revisioni precedenti (gli script di deploy hanno sempre scritto `CREATE OR ALTER` esplicitamente), solo il metodo di verifica era inutilizzabile.
- Fix reali applicati: footer `SET NOCOUNT, XACT_ABORT OFF;` mancante su tutte le SP con skeleton; `XACT_ABORT` assente dall'header su 8 SP di sola lettura; skeleton **completamente assente** su `get_Moduli_SelectList`/`get_Stati_SelectList` (liste statiche, aggiunto per uniformità); `OPTION (RECOMPILE)` mancante in `get_SelectList`.
- **Bug reale corretto**: `uspDomini_del_Modulo` — `DELETE` senza `@@ROWCOUNT`, "riusciva" silenziosamente su una combinazione Id/Modulo inesistente. Fix: pattern standard con messaggio esplicito.
- **Confermato by-design, nessuna azione**: `get_IsModuloAttivo`/`get_Logo` senza `@IdSessione` — check di sistema a basso rischio / branding pre-login pubblico (stesso pattern di `get_Start`/`get_IsStart`).
- Nessun breaking change.

### uspEventi_* (11 SP, non 10 come da inventario iniziale) — infrastruttura calendario condivisa da Scadenze/Servizi/ServiziAssegnati
- **`uspEventi_upd_Sessione` — bypass di titolarità reale, il più grave**: nessun controllo affatto. Dato `@Id` (una Scadenza o Servizio), impostava `tblSessioni.IdCalendario` fidandosi ciecamente del valore — e `IdCalendario` è poi il confine di titolarità usato senza altra verifica da SP come `uspScadenze_get_CalendarioMese_List`. Un utente poteva "dirottare" la propria sessione sul calendario di un'altra azienda conoscendo/indovinando l'Id di una sua Scadenza/Servizio, poi sfogliarne i dati con le normali SP di vista calendario. Fix: aggiunto il controllo titolarità (catena Scadenza/Servizio→Evento→Calendario→Sede) prima di ciascuno dei due rami. **Verificato con prova concreta**: sessione senza titolarità bloccata su una Scadenza reale, `IdCalendario` confermato invariato dopo la chiamata (prima del fix sarebbe silenziosamente riuscita).
- **`uspEventi_get_Ricorrenza`**: nessun `@IdSessione`, leggeva `viewEventi` (dati reali per Evento, non un enum statico) senza controllo. Fix: aggiunto `@IdSessione` (**breaking**) + check titolarità standard.
- **`uspEventi_get_Utenti_SelectList`**: aveva permesso `SRA` ma non verificava mai che l'Evento appartenesse a un calendario/sede accessibile (asimmetria rispetto ai "fratelli" `upd_Utente`/`upd_Proprieta`). Fix: aggiunto lo stesso controllo.
- **Skeleton completamente assente su 7 SP** (6 SelectList statiche + `get_Ricorrenza`): aggiunto per tutte. `XACT_ABORT` mancante in header/footer su altre 4. 2 parametri senza `= NULL` default (`get_Ricorrenza`'s `@Id`, `get_RicorrenzeGiornoMeseRelativo_SelectList`'s `@Data`).
- **Breaking**: `get_Ricorrenza` ha ora `@IdSessione` obbligatorio.

### uspCalendari_* (7 SP) — CRUD `tblCalendari(IdSede, IdModulo)`, il più pulito della giornata
Nessun gap di titolarità: ogni SP ha correttamente permesso `CLD` + verifica sede via `ufnSedi_get_SediInterneBySessione_List`. `uspCalendari_upd` ha un pattern anti-manomissione parametri notevole (verifica che `@IdSede`/`@IdModulo` combacino col record reale prima del check di unicità) — l'opposto esatto del difetto trovato in `uspRifiutiRegistri_upd`/`uspTipi_upd` (che invece si fidavano di un `@IdSede` client-supplied mai verificato), utile come esempio di riferimento futuro.
- Solo fix di skeleton: footer asimmetrico su tutte e 7, `XACT_ABORT` assente dall'header su 3 SP di sola lettura, `OPTION (RECOMPILE)` mancante in `get_SelectList`.
- Nessun breaking change.

### uspEtichette_* (7 SP) — etichette usate da Rifiuti (Formulari/Registrazioni/Modelli) ed Eventi (Scadenze/Servizi)
Nessun gap di titolarità. Stesso pattern anti-manomissione parametri di `uspCalendari_upd`. Mantiene correttamente una cache JSON denormalizzata (`Etichette`) sulle tabelle che referenziano le etichette, ricalcolata in `del`/`upd`/`del_Undo` — verificata coerente.
- Fix di skeleton: footer asimmetrico su tutte e 7, skeleton assente su `get_Visualizzazioni_SelectList`, `XACT_ABORT` mancante in `get`/`get_List`.
- **Fix di coerenza titolarità (confermato dall'utente)**: `del`/`upd` non controllavano `ufnModuli_get_IsAttivoBySessione` (modulo attivo per la sessione) a differenza di `get`/`get_List`/`ins` — allineato aggiungendo lo stesso controllo.
- Rimossa una variabile morta (`@righeRipristinate` in `del_Undo`, mai usata).
- Nessun breaking change.

### uspAree_* (13 SP) — meccanismo di condivisione cross-azienda (tblAree/tblAreeOsepe/tblAreeSediInterne)
Modello confermato dall'utente: Aree condivide entità esterne (Sedi/Persone/Oggetti) tra aziende interne **dello stesso Dominio** (tenant), non tra aziende interne qualsiasi.
- **Bug reale trovato e corretto — `uspAree_ins_SedeInterna`**: verificava che `@Id` (l'Area) appartenesse al Dominio del chiamante, ma **mai** che `@IdSede` appartenesse allo stesso Dominio. Poiché `tblAreeSediInterne` viene letta dalle funzioni di condivisione **dal punto di vista di chi possiede la SedeInterna**, questo permetteva un'iniezione di dati cross-tenant: Azienda A, conoscendo la SedeInterna di Azienda B (Dominio diverso), poteva collegarla alla propria Area — facendo sì che gli utenti di Azienda B si ritrovassero a vedere le entità condivise di A come "condivise", **senza alcun consenso**. Non è il solito IDOR in lettura: è un'iniezione di visibilità indesiderata nella sessione di un altro tenant. Fix: aggiunto controllo `tblSediInterne.IdDominio = @idDominio`.
- **Stesso fix applicato preventivamente a `uspAree_ins_Osepe`**: `@IdOsepe` (polimorfico Sede/Persona/Oggetto via `tblOsepe.Tipo`) non era mai verificato come appartenente allo stesso Dominio. Risolto risalendo alla "sede governante" per ciascun tipo, poi verificandone `IdAziendaInterna → tblSediInterne.IdDominio`.
- **Verificato con dati reali**: creata un'Area di test, `ins_SedeInterna` con SedeInterna di un Dominio diverso correttamente bloccato, con SedeInterna dello stesso Dominio correttamente riuscito.
- Skeleton: footer asimmetrico su tutte e 13, `XACT_ABORT` assente dall'header su 6 SP di sola lettura, `@@ROWCOUNT` mancante in `del_Osepe`/`del_SedeInterna`.
- Nessun breaking change.

### uspUtenti_* (26 SP) — modulo auth/gestione utenti, il più critico finora
Titolarità: Admin (`IdRuolo='AD'`) dello stesso Dominio del target, OR Admin di un Dominio Master (bypass, stesso precedente di Sedi). Per le SP di scrittura già gated da `uspSessione_get_FunzionePermesso @IdFunzione='UTE'`, il fix ha aggiunto solo il layer di ownership Dominio mancante, senza toccare il gate di permesso esistente.
- **8 gap di titolarità fixati** (nessuna delle 8 controllava mai l'ownership): `_del`, `_del_SedeInterna`, `_ins_SedeInterna` (check bidirezionale su utente e sede), `_upd` (+ default/check mancanti su 4 parametri + `@@ROWCOUNT` mancante), **`_upd_FunzionePermesso`** (il più grave: **escalation di privilegio cross-tenant**, un admin di un'azienda poteva assegnare permessi a un utente di un'altra azienda), `_get_FunzioniPermessi_List`/`_get_ListByDominio`/`_get_SediInterne_List` (nessun `@IdSessione` — **breaking** su tutte e 3).
- `uspUtenti_get_List`: scopa per `tblSessioni.IdDominio` corrente (non un check esplicito) — **confermato by-design**: solo un utente Master può cambiare il Dominio operativo di una sessione, switch protetto altrove.
- **Cluster password — risolto via chiarimento utente, non per assunzione**: `get_Password` **confermato non più usato**, lasciato intoccato; `get_PasswordPolicy`/`upd_Password` confermati corretti by-design (`@Id` sempre derivato server-side da un contesto già verificato); **`ins_Password`** — l'utente ha tracciato il call site C# reale (`Utenti/Edit.cshtml.cs`) e trovato un gap concreto: `@Id` arriva da un hidden field HTML, modificabile lato client prima del submit — un IDOR reale (un admin di un Dominio poteva impostare la password di un utente di un altro Dominio manomettendo il campo). Fix: aggiunto `@IdSessione` (**breaking**) + stesso check ownership di `_upd`/`_del`.
- Gruppo pre-auth (`get_LoginByEmail`, `get_Start`, `get_TokenReset`, `upd_TokenReset`, `upd_ConfermaReset`, `upd_Login`, `del_Undo`, `ins`): confermati corretti by-design, solo skeleton fix. `get_Start` non aveva TRY/CATCH affatto — aggiunto.
- Skeleton fix su tutte le 25 SP toccate (tutte tranne `get_Password`).
- **Breaking**: `get_FunzioniPermessi_List`, `get_ListByDominio`, `get_SediInterne_List`, `ins_Password` — tutte con nuovo `@IdSessione` obbligatorio.

---

## Revisione funzioni TVF (2026-08-14) — 27 funzioni, nuovo perimetro oltre le SP

Su richiesta esplicita dell'utente ("controlla anche le funzioni TVF"), rivisitate tutte le 27 table-valued function (`ufn*`) — il motore di titolarità/condivisione usato da quasi tutti i moduli SP già rivisti. Nessun fix di codice applicato: conformità agli standard già pulita su tutta la linea (`WITH SCHEMABINDING` presente ovunque possibile — assente solo in `ufnEventi_get_List`/`_All_List`/`_Assegnati_List`, correttamente non applicabile per la dipendenza da TVP `tvpId_char_16`/`tvpId_char_1`; prefisso `dbo.` sempre presente; solo `LEFT JOIN`; filtri `Lock` coerenti con la convenzione `Lock = 0` già nota per quest'area).

- **Pattern investigato e chiuso come non-bug**: le varianti "ByDominio" (`ufnOggetti_get_NonCondivisiByDominio_List`, `ufnPersone_get_NonCondiviseByDominio_List`, `ufnOsepe_get_NonCondiviseByDominio_List`, `ufnSedi_get_AziendeEsterneNonCondiviseByDominio_List`) non hanno l'esclusione `NOT EXISTS (...tblAreeOsepe...)` presente nelle gemelle "ByUtente". Verificato a fondo: nelle "ByUtente" quell'esclusione serve solo a deduplicare uno `UNION ALL` con un ramo gemello "Condivisi" (non esiste un'analoga `CondivisiByDominio`, quindi non serve). Inoltre `tblAreeOsepe` ha PK `(Id, IdOsepe)` — un'entità **può** appartenere a più Aree contemporaneamente (già così nei dati reali) — quindi mostrare un'entità già condivisa come opzione in `uspOsepe_get_NonCondivise_SelectList`/`uspSedi_get_AziendeEsterneNonCondivise_SelectList` (i due unici chiamanti reali) è coerente col modello dati, non un errore.
- **3 funzioni confermate dead code dall'utente** (nessun chiamante T-SQL trovato via ricerca testuale su `sys.sql_modules`, confermato non usate nemmeno da C#): `ufnOggetti_get_NonCondivisiByDominio_List`, `ufnPersone_get_NonCondiviseByDominio_List`, `ufnSedi_get_SediInterneByDominio_List`. **Rimosse dall'utente il 2026-08-14** (`DROP FUNCTION`, azione fuori da queste sessioni di revisione); verificato post-rimozione: nessun oggetto residuo, nessun riferimento pendente altrove, totale TVF nel db sceso a 24.

---

## Revisione funzioni SVF/scalari (2026-08-14) — 15 funzioni

Su richiesta esplicita dell'utente ("controlla anche le funzioni SVF"), riviste tutte le funzioni scalari (`type='FN'`). `fn_diagramobjects` esclusa dal perimetro (artefatto standard del tool "Database Diagrams" di SSMS, non codice applicativo).

11 di 15 già pienamente conformi (`WITH SCHEMABINDING`, `dbo.` ovunque, `LEFT JOIN`, `Lock` coerente): `ufnDate_get_GiornoDelMeseRelativo`, `ufnEventi_get_Etichette`, `ufnEventi_get_NumberMax`, `ufnEventi_get_TipoProprieta`, `ufnModuli_get_IsAttivoBySessione`, `ufnModuli_get_IsAttivoByUtente`, `ufnRifiutiFormulari_get_Etichette`, `ufnRifiutiModelli_get_Etichette`, `ufnRifiutiRegistrazioni_get_Etichette`, `ufnStringhe_get_Compatta`, `ufnStringhe_get_SenzaSpazi` (le ultime due non accedono a tabelle: `WITH SCHEMABINDING` sarebbe privo di effetto, non è un finding).

`ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore` (calcolo disponibilità quantità con `OUTER APPLY` su relazioni padre/figlio) riletta a fondo passo-passo: algebra corretta, `p2.Lock < 2` sui genitori concorrenti rispetta il pattern documentato in `CLAUDE.md` — nessun bug.

**Fix applicati (skeleton-only, nessuna logica toccata)**:
- `ufnFunzioni_get_PermessoByUtente`, `ufnFunzioni_get_PermessoBySessione` — aggiunto `WITH SCHEMABINDING` (mancava, incoerente col resto del modulo; sono il gate di permesso usato pervasivamente).
- `ufnRifiutiRegistrazioni_get_UltimoNumero`, `ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore` — aggiunto `WITH SCHEMABINDING` (mancava, incoerente con le gemelle `ufnRifiutiXxx_get_Etichette`).
- **`ufnUtenti_get_IsAdmin`** — riscritta: accesso diretto a `dbo.tblUtenti`/`dbo.tblDomini`/`dbo.tblSessioni` al posto di `viewUtenti` (senza prefisso `dbo.` nell'originale), + `WITH SCHEMABINDING`. **Vincolo tecnico scoperto**: `viewUtenti` usa `OUTER APPLY` (lookup ultima password) — costrutto **non supportato nelle viste schema-bound** — quindi la funzione non poteva diventare schema-bound restando appoggiata alla vista; bypassarla (leggendo solo le 2 colonne realmente usate, `DominioMaster`/`Lock`, dalle tabelle base) ha risolto senza toccare `viewUtenti`. Comportamento verificato identico pre/post fix su 10 sessioni reali (valori 0/1/2 confrontati riga per riga). `viewUtenti` stessa resta non schema-bound e fuori scope (riscriverla per abilitare SCHEMABINDING end-to-end richiederebbe eliminare l'`OUTER APPLY`, intervento di logica su una vista usata pervasivamente — non richiesto).

---

## Decisioni aperte

- **`uspOggetti_del`, ramo `Lock=2`** (cancellazione bozza): pulisce solo `tblAreeOsepe`, non `tblScadenzeOsepe`/`tblServiziOsepe`. Probabile asimmetria innocua ma **non verificata a fondo** — da riconsiderare se il modulo viene toccato di nuovo o se il comportamento riemerge in una segnalazione.
- **JSON malformato su backslash non escapato** nelle SP calendario (`uspScadenze_get_CalendarioGiorno/Mese/Settimana_List`, stesso bug replicato in `uspServizi_get_CalendarioGiorno/Mese/Settimana_List`) — costruzione manuale di stringhe JSON, solo `"` escapato non `\`. Non affrontato, richiederebbe riscrittura (`FOR JSON PATH`/`STRING_ESCAPE`). Rivalutare se riemerge.
- **`uspSedi_*`**: `tblSediIndirizzi`/`tblSediRecapiti` mai ripulite in nessun ramo `_del*` (rischio basso); guard `tblSedi.IdParent` (figli) nel ramo `Lock=2` non pienamente chiuso per `'E'`; `@IdTipo` di `uspSedi_del` sembra dead param (SP comunque confermata non più usata). Nessuna azione richiesta finché non riemergono.
- SP confermate **non più usate dall'applicazione**, lasciate intenzionalmente intoccate — non "ripulire" senza riconferma: `uspSedi_del`, `uspSessioni_upd_AziendaByRegistro`, `uspUtenti_get_Password`.
- TVF confermate **non più usate dall'applicazione**, rimosse dall'utente il 2026-08-14: `ufnOggetti_get_NonCondivisiByDominio_List`, `ufnPersone_get_NonCondiviseByDominio_List`, `ufnSedi_get_SediInterneByDominio_List` (non più nel db).
- Nessun'altra decisione aperta al momento: tutti gli altri moduli elencati sopra sono chiusi, con ogni finding fixato o esplicitamente confermato non-bug/non-azionabile dall'utente (vedi dettagli per modulo).

---

## Inventario completo (2026-08-14)

Eseguito `SELECT name, create_date, modify_date FROM sys.objects WHERE type='P'` — 284 SP applicative totali (esclude le 7 `sp_*diagram*` di sistema).

**Anomalie trovate e chiuse (confermate note/intenzionali dall'utente, non richiedono azione)**:
- `uspRifiutiMovimenti_get_Attivita_List` — rivista/corretta il 2026-08-11 (vedi modulo RifiutiMovimenti sopra), **oggi assente dal database** (non un rename: verificato con `LIKE '%Attivita%'`, nessun match vicino). Rimozione confermata nota dall'utente.
- `uspSessioni_upd_AziendaByRegistro` — già segnata come "confermata non più usata, mai toccata in questa serie di revisioni"; **oggi assente dal database**. Coerente con "non più usata", rimossa da un processo esterno a queste revisioni. Confermato nota dall'utente.
- `uspSedi_del` — il `create_date` coincide col `modify_date` (2026-08-13 16:17:28, tipico di un DROP+CREATE nel batch di deploy anziché un ALTER puro), ma il **contenuto verificato via `OBJECT_DEFINITION`** corrisponde esattamente al primo giro di fix titolarità descritto nella review Sedi (branch Master-Dominio incluso) — nessuna azione necessaria, non è la stessa cosa della nota "lasciata intoccata" che si riferiva solo al secondo giro (audit FK di completezza).

### Moduli rivisti e chiusi (29 gruppi, ~266 SP)
Oggetti(8), Osepe(2), Persone(10), RifiutiAutorizzazioni(26), RifiutiDocumentiTrasportiTipi(1), RifiutiEer(2), RifiutiFormulari(7), RifiutiGiacenze(1), RifiutiMateriali(1), RifiutiModelli(9), RifiutiMovimenti(3 live, era 4), RifiutiOperazioni/Provenienze/Raee(3), RifiutiRegistrazioni(19), RifiutiRegistrazioniEsiti(1), RifiutiRegistri(9), RifiutiRuoli/StatiFisici/UnitaMisura/Ruoli(4), Scadenze(16), Sedi(17), Servizi(16), ServiziAssegnati(6), Sessione/Sessioni(5 live, era 6), Tipi(11), UrlNavigazione(2), Utenti(26), **Domini(17), Eventi(11, era 10), Calendari(7), Etichette(7), Aree(13)**.

### Moduli NON ancora rivisti: nessuno
Tutti i moduli sono stati rivisti. `uspSYS_*` resta **fuori perimetro** (confermato dall'utente 2026-08-14: tooling di sviluppo, mai chiamato dall'applicativo).

### Ultimo blocco chiuso: lookup statici finali (17 SP, 2026-08-14)
`uspAdr_get_SelectList`, `uspAvvisi_get_Count`/`get_List`, `uspCalendario_get_AnniSelectList`, `uspColori_get`/`get_SelectList`, `uspComuni_*` (6 SP), `uspImballi_get_SelectList`, `uspNazioni_get_SelectList`, `uspProvince_get_SelectList`, `uspRifiutiAttivitaRecuperoSmaltimento_get_SelectList`, `uspTipiDati_get_SelectList`.
- Nessun gap di titolarità (dati di riferimento globali; `uspAvvisi_*` scopato per `@IdUtente` server-derived, confermato dall'utente coerente con `uspMenu_get`).
- Fix di skeleton: 9 SP senza skeleton alcuno, 7 SP senza `XACT_ABORT`, `OPTION (RECOMPILE)` aggiunto a `uspNazioni_get_SelectList`/`uspComuni_get_SelectList`. `uspTipiDati_get_SelectList` già conforme.
- **Lasciato su richiesta esplicita dell'utente**: `WITH (NOLOCK)` su tabelle base in `uspAvvisi_get_List` (non viola la lettera dello standard, che vieta NOLOCK solo sulle viste).
- Nessun breaking change.

### Infrastruttura core (`uspId_get`/`uspId_upd`/`uspFunzioni_get_PermessoByUtente`/`uspMenu_get`)
- **`uspId_get` — NON toccare l'header/footer skeleton (niente `XACT_ABORT`), decisione definitiva 2026-08-14**: sembrerebbe mancare `XACT_ABORT ON/OFF` per uniformità standard, ma **non va aggiunto**. `uspId_get` contiene un loop di retry-su-collisione (`INSERT INTO tblId`, cattura errori 2627/2601) senza `BEGIN TRANSACTION` proprio — si basa sul fatto di essere quasi sempre chiamata FUORI da una transazione del chiamante. Ma **esistono eccezioni legittime e necessarie** (es. `uspRifiutiRegistrazioni_upd`, dove l'Id generato dipende dal ramo di esecuzione — pattern già documentato in `CLAUDE.md`) in cui è chiamata **dentro** una transazione aperta. Se si aggiungesse `XACT_ABORT ON`, un fallimento del retry-loop in uno di questi casi "condannerebbe" (`XACT_STATE()=-1`) la transazione del chiamante in modo silenzioso e difficile da diagnosticare. **Non riproporre questo fix in futuro** — confermato esplicitamente dall'utente che le eccezioni esistono davvero, non è un'ipotesi teorica scartata per eccesso di cautela.
- `uspId_upd`: già conforme (header/footer corretti). Un unico controllo obbligatorietà combinato per i 3 parametri invece di messaggi distinti per parametro — deviazione stilistica, non un bug, lasciata invariata (infrastruttura critica, nessun beneficio a toccarla).
- `uspFunzioni_get_PermessoByUtente`: **confermato non più usata dall'utente 2026-08-14** — nessuna SP la chiama internamente, probabile predecessore di `uspSessione_get_FunzionePermesso`. Lasciata completamente intoccata, stesso trattamento di `uspSedi_del`/`uspUtenti_get_Password`/`uspSessioni_upd_AziendaByRegistro`.
- `uspMenu_get`: header/footer già conformi, nessun fix necessario. `@IdUtente` **confermato dall'utente** essere sempre un valore server-side derivato dal cookie di autenticazione firmato, non modificabile dal client — nessun controllo aggiuntivo necessario.

**Gruppo infrastruttura chiuso 2026-08-14**: nessuna delle 4 SP ha ricevuto modifiche (solo conferme + una lasciata intoccata perché morta) — esito legittimo, non tutti i moduli richiedono fix.

**Lezione di metodologia importante (2026-08-14)**: `sys.sql_modules.definition` (e `OBJECT_DEFINITION()`) **normalizza silenziosamente `CREATE OR ALTER` in `CREATE`** (spazi extra al posto delle parole rimosse) indipendentemente da come la SP è stata effettivamente creata/alterata — **non è mai utilizzabile come diagnostica** per verificare se una SP usa `CREATE OR ALTER`. Non invalida le revisioni passate (gli script di deploy hanno sempre scritto `CREATE OR ALTER` esplicitamente nell'header), ma da qui in avanti questo "finding" va tolto dal catalogo dei controlli — non verificarlo mai più leggendo la definizione a posteriori. **Conseguenza pratica per i file del repo**: i mirror in `sql/procedures/*.sql` vanno scritti a mano con `CREATE OR ALTER` (o riusando il file di deploy già normalizzato), mai rigenerati da `OBJECT_DEFINITION`/questo script, altrimenti si perde `OR ALTER` e il prossimo deploy fallisce se la SP esiste già.

---

## Sviluppo post-revisione (dopo la chiusura 2026-08-14)

Sezione per le nuove SP create da zero (non fix di SP esistenti) dopo la chiusura del progetto di revisione sistematica. A differenza delle sezioni sopra (audit di codice preesistente), queste voci documentano funzionalità nuove.

### `uspRifiutiGiacenze_get_Quantita` (nuova, 2026-08-25)
Estende il modulo Giacenze (`uspRifiutiGiacenze_get_List`, `uspRifiutiGiacenze_get_Carichi_List`) con una terza SP che restituisce come **scalare** (result set a una riga/colonna `rtn`, non un OUTPUT param) la giacenza residua per una singola combinazione Registro+Eer+StatoFisico, invece di liste aggregate/dettaglio carichi.

- **Firma**: `@IdRegistro, @IdSessione, @IdEer, @IdStatoFisico, @Data = NULL` — nessun OUTPUT param.
- **Design corretto in corsa (2026-08-25)**: la prima versione usava un vero `@Giacenza DECIMAL(18,2) OUTPUT`. Verificando l'integrazione lato app si è scoperto che `ISqlDataAccess`/`SqlDataAccess` (Dapper) non ha **mai**, in tutto il progetto, un meccanismo per leggere `ParameterDirection.Output` — l'unico metodo scalare esistente, `ScalarAsync<T,U>`, legge la prima colonna del primo result set (`ExecuteScalarAsync`). Le SP scalari esistenti (`uspRifiutiAutorizzazioni_get_IdSede`, `uspRifiutiRegistrazioni_get_IsQuantitaSuperiore`) infatti fanno tutte `SELECT ... AS rtn`, mai `OUTPUT`. Riallineata a quel pattern per riusare `ScalarAsync` senza toccare l'infrastruttura condivisa (usata da altri 24 file) — scelta confermata dall'utente.
- **Logica**: stessa formula `Quantita - QuantitaAssegnata` delle due SP sorelle (CTE `QuantitaAssegnata` su `tblRifiutiRegistrazioniRelazioni`, filtrata `p.[Data] <= @Data` cosicché gli scarichi con data futura rispetto a `@Data` non riducono la giacenza calcolata a quella data — verificato esplicitamente su richiesta dell'utente). I due rami "Rifiuto prodotto" (`IdOperazione<>'R'`, `Operazione='C'`) e "Rifiuto trattato" (`IdOperazione='R'`, `Operazione='S'`) sono uniti in un solo `SUM` con `OR` invece di due `UNION ALL`, essendo mutuamente esclusivi sullo stesso record.
- **Permessi/titolarità**: stessi controlli delle SP sorelle (`RRG≥1` + `ufnSedi_get_SediInterneBySessione_List` su Registro→Sede).
- **Deviazione nota dallo standard generale**: filtro `r.Lock = 0` (non `Lock < 2`) per coerenza con le due SP sorelle dello stesso modulo, non con lo standard generico del progetto.
- **Verificata**: smoke test sessione basso privilegio (diniego pulito) + confronto su dati reali con `uspRifiutiGiacenze_get_List` sullo stesso Registro (`fd73e743a19b44c0`), ripetuto due volte a distanza (i dati reali dell'ambiente cambiano nel tempo — non fidarsi di un confronto fatto in momenti diversi): match esatto entrambe le volte (22.00 su un solo ramo la prima volta, 2.00+4.00=6.00 la seconda).
- **Consumer applicativo**: `IRifiutoGiacenzaRepository`/`RifiutoGiacenzaRepository`/`IRifiutoGiacenzaService`/`RifiutoGiacenzaService.GetQuantitaAsync` in `4_0_Ecomatico` (repo app separato), via `ScalarAsync<decimal, dynamic>`.
- Deploy + mirror committati (`375eeb6`, poi corretto in un commit successivo per il cambio OUTPUT→result set).

### `tblRifiutiRegistrazioni.IdAttivitaProvenienza` (nuova colonna, 2026-08-25)
Nuova colonna `CHAR(1) NULL`, FK verso `tblRifiutiAttivitaProvenienze.Id` (tabella creata live dall'utente lo stesso giorno, non ancora tracciata nel repo — mirror aggiunto in `sql/tables/tblRifiutiAttivitaProvenienze.sql`).

**Propagazione a get/upd (stesso giorno)**: aggiunta a `uspRifiutiRegistrazioni_get` (default `'0'` se NULL, come `IdEsito`/`IdRaee`/`IdStatoFisico`) e a `uspRifiutiRegistrazioni_upd` (nuovo `@IdAttivitaProvenienza`, gate speculare a `IdAttivitaRs`: `IF @isAttivitaProvenienza = 0 OR @IdAttivitaProvenienza = '0' SET @IdAttivitaProvenienza = NULL`, propagato nella `UPDATE` finale). Flag `IsAttivitaProvenienza` su `tblRifiutiOperazioni` attivo solo per l'operazione `'F'` (Carico di rifiuto prodotto al di fuori dell'unità locale) — unica riga su 10 operazioni. **Non toccato**: il blocco `@aggiornaLog`/`tblRifiutiMovimentiLog` — quella tabella non ha una colonna per questo campo, aggiungerla sarebbe un secondo intervento fuori dallo scope richiesto (solo get/upd + modello C#).

**`uspRifiutiAttivitaProvenienze_get_SelectList`** (nuova, stesso giorno): SP di lookup standard per il picklist (4 righe statiche, nessuna titolarità — stesso trattamento di Raee/Provenienze/Attivita), pattern placeholder `Id='0'`/`(Selezionare)` + righe reali ordinate per `Id` (nessuna colonna `Pos` sulla tabella, a differenza di `tblRifiutiRaee`). Rinominata rispetto al nome chiesto dall'utente (`uspRifiutiAttivitaProvenienze_SelectList`) per rispettare la convenzione `*_get_SelectList` del progetto — segnalato, non semplicemente deciso in autonomia senza nota.

**Riordino fisico colonne (stesso giorno)**: su richiesta esplicita dell'utente, la colonna è stata posizionata fisicamente sopra `IdUnitaMisuraQuantitaRespinta` (non solo nello script di documentazione) — in T-SQL `ALTER TABLE ADD` accoda sempre in fondo, quindi l'unico modo è stato un **rebuild completo della tabella**:
1. Drop delle 2 funzioni `WITH SCHEMABINDING` che referenziano la tabella (`ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore`, `ufnRifiutiRegistrazioni_get_UltimoNumero`) — altrimenti bloccano il `DROP TABLE`.
2. Drop delle 4 FK in entrata da altre tabelle (`tblRifiutiRegistrazioniEtichette`, `tblRifiutiRegistrazioniRelazioni` ×2, `tblEoWMovimenti`).
3. `CREATE TABLE ..._new` con l'ordine colonne desiderato, `INSERT INTO ..._new SELECT ... FROM` la vecchia (7 righe, verificato `COUNT(*)` invariato), `DROP TABLE` vecchia, `sp_rename` tabella e PK ai nomi originali.
4. Ricreati i 2 indici nonclustered, le 8 FK in uscita, le 4 FK in entrata, le 2 funzioni schema-bound (contenuto identico, invariato).
5. Tutto in un'unica transazione (`XACT_ABORT ON`/`TRY-CATCH`/`ROLLBACK`), **fuori** però dal footer standard delle SP (è uno script DDL one-shot, non una stored procedure — non va confuso con lo skeleton `uspXxx`).
6. Verificato: ordine colonne, conteggio righe, indici, FK uscita/entrata, `is_schema_bound=1` sulle 2 funzioni, smoke test reale su `uspRifiutiRegistrazioni_get` + `uspRifiutiGiacenze_get_Quantita` (dati reali, invariati) + diniego pulito basso privilegio.
7. **Lezione**: prima di un rebuild tabella, controllare sempre `sys.sql_expression_dependencies` (SP/funzioni che referenziano la tabella) **e** `sys.sql_modules.is_schema_bound` sui referenzianti — solo gli oggetti schema-bound bloccano davvero il `DROP TABLE`; le SP normali (non schema-bound) restano valide anche a tabella ricreata, deferred name resolution permettendo.
8. Fattibile senza rischi solo perché la tabella aveva 7 righe (ambiente dev) — su una tabella di produzione con molte righe/foreign key aggiuntive questa operazione andrebbe pianificata con più cautela (finestra di manutenzione, backup, downtime).
