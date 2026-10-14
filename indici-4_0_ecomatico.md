# Audit indici — 4_0_ecomatico

Metodologia e stato di avanzamento dell'audit indici sul database `4_0_ecomatico` (istanza `.\SQLSERVER`), condotto dopo la chiusura della revisione stored procedure (vedi `context-4_0_ecomatico.md`). Questo file è la controparte "indici" di quel documento: stessa logica — leggibile senza dover rileggere l'intera cronologia della sessione.

Standard di coding, schema facts e convenzioni generali del progetto sono in `context-4_0_ecomatico.md` e in `CLAUDE.md` — non ripetuti qui.

---

## 1. Obiettivo e perimetro

Verificare lo stato di salute degli indici del database applicativo (`dbo.tbl*`), in particolare sulle tabelle del dominio Rifiuti (`tblRifiuti*`, le più scritte/lette dal modulo transazionale) e sulle tabelle anagrafiche/infrastrutturali toccate dalla revisione SP appena chiusa. Non tocca le tabelle di sistema/diagramma né database diversi da `4_0_ecomatico`.

**Fatto chiave che condizionava la metodologia fino al 2026-08-14**: all'apertura di questo audit `4_0_ecomatico` era un database di **solo sviluppo/test** — nessun ambiente di produzione con volumi di dati reali (confermato dall'utente il 2026-08-14). Tutte le tabelle del dominio Rifiuti avevano tra 0 e poche centinaia di righe.

**Aggiornamento 2026-09-23**: questo non è più vero. Esiste oggi un tag `deployed-prod` nel repo (allineato a HEAD) e più moduli sono confermati in produzione con traffico reale. Il metodo primario resta comunque l'analisi statica del carico di lavoro (§2) anche ora che esiste produzione: le DMV runtime restano rumorose finché non si accumula un ciclo di uptime rappresentativo sull'istanza di produzione, ma la cautela nel valutare il beneficio di un indice su una tabella già grande/hot-path (es. `tblRifiutiMovimenti`, `tblRifiutiRegistrazioni`, `tblRifiutiAutorizzazioni`) è oggi maggiore che in fase di solo sviluppo, perché il costo di un indice ridondante o mal progettato si paga con traffico reale.

Non è un audit "una tantum": ogni fix (statistiche, indice nuovo/rimosso, rebuild) va proposto, mai applicato senza conferma esplicita dell'utente — stessa disciplina già seguita per le stored procedure.

---

## 2. Metodologia generale

**Le DMV runtime (missing index, usage stats, frammentazione) sono strutturalmente inaffidabili in questo ambiente** — non solo "poco significative": `sys.dm_db_missing_index_*` riflette solo i piani compilati dall'ultimo restart, senza traffico applicativo reale resta vuota o quasi; `sys.dm_db_index_usage_stats` si azzera a ogni restart e richiede un ciclo d'uso reale; la frammentazione/le statistiche non hanno senso su tabelle da poche decine di righe (vedi §4.1, verificato l'2026-08-14). Vanno **riservate a un momento successivo**, se/quando emergeranno volumi di dati reali (produzione o un dataset di test realistico).

**Metodo primario in questo ambiente: analisi statica del carico di lavoro.** Dato che l'intero corpo di stored procedure del database è stato appena rivisto modulo per modulo (vedi `context-4_0_ecomatico.md`), i pattern di accesso reali alle tabelle sono noti con precisione — non ipotizzati: `JOIN ON`/`WHERE`/`ORDER BY` effettivi nel codice T-SQL, non piani di query stimati. Il procedimento per ogni tabella (o gruppo di tabelle di uno stesso modulo):

1. **Estrarre gli indici esistenti** sulla tabella (chiave + `INCLUDE` + eventuale `filter_definition`) — query §4.4 filtrata sulla tabella.
2. **Estrarre i pattern di predicato reali** dalle SP che referenziano quella tabella: `JOIN`/`WHERE`/`ORDER BY` — via ricerca testuale su `sys.sql_modules` (§4.0) + lettura mirata delle SP più significative (già note dalla revisione: catena titolarità `IdSede`/`Lock`, relazioni padre/figlio, paging in `_get_List`, filtri `_SelectList`).
3. **Confrontare**: per ogni combinazione ricorrente di colonne di filtro/join (in particolare quelle usate nel check di titolarità aggiunto sistematicamente durante la revisione SP — quello è oggi il predicato più frequente su quasi ogni tabella `IdSede`-scoped), verificare se esiste un indice che la copre come prefisso sinistro. Segnalare sia i gap (indice mancante) sia le ridondanze (indici già coperti da un altro più ampio).
4. **Presentare i risultati grezzi + l'analisi da DBA** prima di proporre qualunque modifica — cosa cambierebbe, perché, con quale beneficio atteso *quando* i volumi cresceranno (un indice ha senso oggi anche con 5 righe, se il pattern di accesso è quello reale dell'applicazione: il costo di mantenerlo è basso, il beneficio si materializza con la crescita dei dati).
5. **Proporre l'azione** (`CREATE`/`DROP`/`ALTER INDEX`) con la query pronta, **non eseguirla** senza conferma esplicita.
6. **Aggiornare la sezione 6** (Stato avanzamento) dopo ogni tabella/gruppo chiuso.

Le query DMV runtime (§4.1–§4.3, §4.5 sotto) restano documentate e pronte all'uso per quando torneranno utili, ma non sono il metodo guida per questa fase.

---

## 3. Soglie di decisione standard

| Controllo | Soglia | Azione tipica |
|---|---|---|
| Frammentazione indice | `avg_fragmentation_in_percent` 5–30% e `page_count` > 1000 | `ALTER INDEX ... REORGANIZE` |
| Frammentazione indice | `avg_fragmentation_in_percent` > 30% e `page_count` > 1000 | `ALTER INDEX ... REBUILD` (valutare `ONLINE = ON` se Enterprise/2019+, altrimenti finestra di manutenzione) |
| Frammentazione indice | `page_count` < 1000 | Ignorare (rumore, il costo del rebuild supera il beneficio) |
| Statistiche obsolete | `modification_counter` / `rows` > 20% (tabelle piccole) o formula standard `sqrt(1000 * rows)` (tabelle grandi, soglia dinamica introdotta da SQL 2016+ trace flag 2371, comunque attivo di default se database in compatibility level ≥130) | `UPDATE STATISTICS ... WITH FULLSCAN` (tabelle piccole/medie) o `WITH SAMPLE` (tabelle molto grandi) |
| Indice mancante | `avg_user_impact` alto (>70) e `user_seeks`/`user_scans` non trascurabili, `ImprovementMeasure` tra i più alti del batch | Proporre `CREATE INDEX`, mai crearlo alla cieca: verificare sempre che non esista già un indice quasi-equivalente (vedi duplicati) |
| Indice inutilizzato | `user_seeks + user_scans + user_lookups` = 0 su una finestra di uptime significativa, `user_updates` > 0 (costa in scrittura senza mai essere letto) | Proporre `DROP INDEX`, mai su PK/UNIQUE senza verifica esplicita del motivo (constraint applicativo, non solo performance) |
| Indici duplicati/ridondanti | Stesse colonne chiave (stesso ordine) con `INCLUDE` diversi, o un indice le cui colonne chiave sono un prefisso esatto di un altro sulla stessa tabella | Proporre consolidamento (drop del sottoinsieme ridondante), mai automatico — verificare `INCLUDE` e filtri (`WHERE`) prima di assumere ridondanza |

Queste soglie sono un punto di partenza da DBA, non regole rigide: ogni proposta di modifica va motivata caso per caso con i numeri reali della tabella (dimensione, pattern di accesso OLTP vs report), non applicata meccanicamente solo perché supera una soglia.

---

## 4. Query diagnostiche

### 4.0 Analisi statica — SP che referenziano una tabella + indici esistenti

Prima query per ogni tabella oggetto di analisi: elenco delle SP che la referenziano (per poi leggerne il testo mirato) e, in un colpo solo, gli indici esistenti con le colonne chiave/incluse.

```sql
-- SP che referenziano la tabella (adattare @tabella)
DECLARE @tabella SYSNAME = 'tblRifiutiRegistrazioni';

SELECT DISTINCT o.name AS StoredProcedure
FROM sys.sql_modules m
INNER JOIN sys.objects o ON m.object_id = o.object_id
WHERE o.type = 'P'
  AND m.definition LIKE '%' + @tabella + '%'
ORDER BY o.name;
```

```sql
-- Indici esistenti sulla tabella (stessa forma di §4.4, filtrata)
SELECT
    i.name AS Indice,
    i.is_unique,
    i.filter_definition,
    STUFF((
        SELECT ', ' + c.name + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE '' END
        FROM sys.index_columns ic
        INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH('')
    ), 1, 2, '') AS ColonneChiave,
    STUFF((
        SELECT ', ' + c.name
        FROM sys.index_columns ic
        INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1
        FOR XML PATH('')
    ), 1, 2, '') AS ColonneIncluse
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('dbo.tblRifiutiRegistrazioni')  -- adattare
  AND i.type > 0
ORDER BY i.type, ColonneChiave;
```

Il passo successivo (lettura dei `JOIN`/`WHERE`/`ORDER BY` reali nelle SP elencate) è manuale/mirato — via `OBJECT_DEFINITION`/lettura diretta delle SP più significative per quella tabella, non ulteriormente automatizzabile in una query generica.

### 4.1 Statistiche obsolete

```sql
SELECT
    t.name                                       AS Tabella,
    s.name                                       AS Statistica,
    STATS_DATE(s.object_id, s.stats_id)          AS UltimoAggiornamento,
    sp.rows                                      AS RigheTabella,
    sp.modification_counter                      AS RigheModificate,
    CASE WHEN sp.rows > 0
         THEN CAST(100.0 * sp.modification_counter / sp.rows AS DECIMAL(5,2))
         ELSE NULL
    END                                           AS PercentualeModifiche
FROM sys.tables t
INNER JOIN sys.stats s ON t.object_id = s.object_id
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE t.name LIKE 'tblRifiuti%'
ORDER BY PercentualeModifiche DESC;
```

Estendibile ad altri prefissi (`tblSedi%`, `tblUtenti%`, ecc.) semplicemente cambiando il `LIKE`, o rimuovendo il filtro per un giro completo del database.

### 4.2 Indici mancanti (missing index DMV)

```sql
SELECT
    OBJECT_NAME(mid.object_id)                    AS Tabella,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    migs.user_seeks,
    migs.user_scans,
    migs.avg_total_user_cost,
    migs.avg_user_impact,
    (migs.user_seeks + migs.user_scans)
        * migs.avg_total_user_cost
        * (migs.avg_user_impact / 100.0)          AS ImprovementMeasure
FROM sys.dm_db_missing_index_details mid
INNER JOIN sys.dm_db_missing_index_groups mig
    ON mid.index_handle = mig.index_handle
INNER JOIN sys.dm_db_missing_index_group_stats migs
    ON mig.index_group_handle = migs.group_handle
WHERE mid.database_id = DB_ID()
ORDER BY ImprovementMeasure DESC;
```

Nota: questa DMV riflette solo i piani di query già compilati/eseguiti dall'ultimo restart — non è un'analisi statica dello schema, va incrociata con l'uso reale dell'applicazione.

### 4.3 Indici esistenti + utilizzo

```sql
SELECT
    OBJECT_NAME(i.object_id)   AS Tabella,
    i.name                     AS Indice,
    i.type_desc,
    i.is_unique,
    i.is_primary_key,
    us.user_seeks,
    us.user_scans,
    us.user_lookups,
    us.user_updates,
    us.last_user_seek,
    us.last_user_scan
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats us
    ON i.object_id = us.object_id
   AND i.index_id  = us.index_id
   AND us.database_id = DB_ID()
WHERE i.object_id IN (SELECT object_id FROM sys.tables WHERE is_ms_shipped = 0)
  AND i.type > 0  -- esclude heap (type 0)
ORDER BY Tabella, ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0) ASC;
```

Righe con `user_seeks`/`user_scans`/`user_lookups` tutti NULL o 0 e `user_updates` > 0 sono candidate a "indice inutilizzato" (vedi soglia in §3) — ma verificare sempre l'uptime del server prima di proporre il `DROP`.

### 4.4 Indici duplicati/ridondanti (colonne chiave)

```sql
SELECT
    OBJECT_NAME(i.object_id) AS Tabella,
    i.name                   AS Indice,
    i.is_unique,
    i.filter_definition,
    STUFF((
        SELECT ', ' + c.name + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE '' END
        FROM sys.index_columns ic
        INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH('')
    ), 1, 2, '') AS ColonneChiave,
    STUFF((
        SELECT ', ' + c.name
        FROM sys.index_columns ic
        INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1
        FOR XML PATH('')
    ), 1, 2, '') AS ColonneIncluse
FROM sys.indexes i
WHERE i.object_id IN (SELECT object_id FROM sys.tables WHERE is_ms_shipped = 0)
  AND i.type > 0
ORDER BY Tabella, ColonneChiave;
```

Da leggere a occhio per tabella: cercare stesso `ColonneChiave` (o uno prefisso esatto dell'altro) con `ColonneIncluse`/`filter_definition` diversi.

### 4.5 Frammentazione

```sql
SELECT
    OBJECT_NAME(ips.object_id)          AS Tabella,
    i.name                              AS Indice,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count,
    ips.record_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i
    ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.page_count > 100
ORDER BY ips.avg_fragmentation_in_percent DESC;
```

`'LIMITED'` è sufficiente per uno screening iniziale (economico); se una tabella specifica risulta borderline, rieseguire su quella singola con `'DETAILED'` prima di decidere REBUILD vs REORGANIZE.

---

## 5. Comandi operativi (esecuzione)

Stessa disciplina già stabilita per le stored procedure — vedi `context-4_0_ecomatico.md` §"Checklist di deploy" per il razionale completo (`-f 65001` per gli accenti, `-o <file>` + `Read` per evitare troncamenti):

```powershell
sqlcmd -S ".\SQLSERVER" -d "4_0_ecomatico" -E -f 65001 -y 0 -i <query.sql> -o <output.txt>
```

**Nota tool**: la sessione ha usato finora `sqlcmd` locale via PowerShell/Bash, non l'MCP `mssql` (scartato in una sessione precedente per via dei prompt di autenticazione Azure che genera). Se in questa fase si preferisce l'MCP, confermarlo esplicitamente — altrimenti resta `sqlcmd` come da convenzione stabilita.

**Nota operativa — tabelle con indici filtrati (`WHERE ...`)**: richiedono `SET QUOTED_IDENTIFIER ON;` esplicito nella sessione non solo per il `CREATE INDEX` stesso, ma per **qualunque DML successivo** (`DELETE`/`UPDATE`/`INSERT`) sulla tabella — altrimenti errore `Msg 1934`, la sessione `sqlcmd` di default ha `QUOTED_IDENTIFIER OFF`. Includerlo sempre come primo statement (con `GO` separato) negli script che toccano tabelle con indici filtrati, anche solo per query di pulizia/test manuali (scoperto prima durante la creazione di `IX_RifiutiModelli_IdRegistro_Lock`, poi di nuovo durante uno script di cleanup dati di test su `tblAree`, che ha un indice filtrato `IX_Aree_IdDominio_Lock` — 2026-08-14).

### Naming convention (dedotta dal database esistente, 2026-08-14)

Analizzati tutti i 30 indici non-clustered "reali" del database (esclusi PK clustered, statistiche auto-generate `_WA_Sys%`, indice di sistema di `sysdiagrams`).

**Regola di base, rispettata al 100% nei 23 indici `IX_*`:**
`IX_<Tabella senza prefisso "tbl">_<ColonneChiave in ordine>` — i satelliti mantengono il nome tabella completo, mai abbreviato (es. `tblRifiutiFormulariEtichette` → `IX_RifiutiFormulariEtichette_IdEtichetta`).

**Colonna di filtro (`WHERE Lock<2`/`Lock=0` ecc.) — qui la codebase esistente NON è coerente**: compare in coda (`IX_RifiutiAutorizzazioni_IdSede_IdRuolo_Lock`), in testa (`IX_RifiutiRegistrazioni_Lock_Data`), in mezzo (`IX_RifiutiRegistrazioni_IdMovimento_Lock_Data_Numero`), oppure omessa pur essendo l'indice filtrato (`IX_RifiutiFormulari_IdMovimento`). Un caso (`IX_Aree_Lock`) è francamente fuorviante: il nome dice "Lock" ma la vera colonna chiave è `IdDominio`.

**Convenzione adottata per i nuovi indici proposti in questa revisione**: `IX_<Tabella>_<ColonneChiave>[_Lock]` — colonna di filtro sempre in coda, mai in testa o in mezzo. Non si tocca retroattivamente il nome degli indici esistenti (nessun beneficio funzionale, puramente cosmetico, fuori perimetro di questa revisione).

**Indici univoci**: prefisso `UX_`, stessa regola degli `IX_` (`UX_<Tabella senza "tbl">_<ColonneChiave>[_Lock]`). Deciso il 2026-10-11 sui primi due casi reali, nati con i moduli Anagrafica estesa e Amministratori: `UX_ClientiFornitori_IdAziendaInterna_IdSede_Tipo_Lock` e `UX_Amministratori_IdAziendaInterna_IdSede_Lock`, entrambi filtrati `Lock = 0` (una sola scheda attiva per soggetto). L'ipotesi iniziale `UQ_` non è stata adottata.

**Rename eseguito 2026-08-14 (su richiesta esplicita dell'utente, deviazione dal "non toccare retroattivamente" iniziale)**: tutti i 14 indici non conformi rinominati allo standard `IX_<Tabella>_<ColonneChiave>[_Lock]`, verificato preventivamente che nessuna SP li referenziasse via index hint esplicito (`WITH (INDEX(...))`) — nessun hint trovato, rename innocuo per l'optimizer. Il database è ora **100% conforme** alla convenzione.

| Tabella | Nome precedente | Nuovo nome |
|---|---|---|
| `tblAree` | `IX_Aree_Lock` | `IX_Aree_IdDominio_Lock` |
| `tblRifiutiFormulari` | `IX_RifiutiFormulari_IdMovimento` | `IX_RifiutiFormulari_IdMovimento_Lock` |
| `tblRifiutiFormulari` | `IX_RifiutiFormulari_Lock_DataEmissione` | `IX_RifiutiFormulari_DataEmissione_Lock` |
| `tblRifiutiRegistrazioni` | `IX_RifiutiRegistrazioni_IdMovimento_Lock_Data_Numero` | `IX_RifiutiRegistrazioni_IdMovimento_Data_Numero_Lock` |
| `tblRifiutiRegistrazioni` | `IX_RifiutiRegistrazioni_Lock_Data` | `IX_RifiutiRegistrazioni_Data_Lock` |
| `tblSedi` | `IX_Sedi_InternaEsterna_Lock_IdAziendaInterna` | `IX_Sedi_InternaEsterna_IdAziendaInterna_Lock` |
| `tblCalendari` | `idxIdSede` | `IX_Calendari_IdSede` |
| `tblComuni` | `idx_IdProvincia` | `IX_Comuni_IdProvincia` |
| `tblIndirizzi` | `idx_IdComune` | `IX_Indirizzi_IdComune` |
| `tblIndirizzi` | `idx_IdNazione` | `IX_Indirizzi_IdNazione` |
| `tblSediInterne` | `idxIdDominio` | `IX_SediInterne_IdDominio` |
| `tblUtentiLogin` | `idxId` | `IX_UtentiLogin_Id` |
| `tblUtentiPassword` | `idxId` | `IX_UtentiPassword_Id` |
| `tblUtentiPassword` | `idxtblUtentiPassword_Id_Data` | `IX_UtentiPassword_Id_Data` |

Nota bene per il resto della revisione: qualunque riferimento nella cronologia della sessione (o in query/appunti precedenti) ai vecchi nomi `IX_RifiutiRegistrazioni_Lock_Data`/`IX_RifiutiRegistrazioni_IdMovimento_Lock_Data_Numero` (citati così nell'analisi del punto 2, §6) va inteso come i nuovi nomi `IX_RifiutiRegistrazioni_Data_Lock`/`IX_RifiutiRegistrazioni_IdMovimento_Data_Numero_Lock` — stesso indice, solo rinominato, nessun cambio di struttura/comportamento.

---

## 6. Ordine di lavoro e stato avanzamento

Ultimo aggiornamento: 2026-08-14.

**Pivot metodologico 2026-08-14**: dopo aver verificato che le statistiche sono irrilevanti su questi volumi (punto 1 originale, chiuso senza azione — vedi nota), l'utente ha confermato che `4_0_ecomatico` è l'unico ambiente esistente (nessuna produzione). L'ordine di lavoro è stato quindi convertito da "audit runtime via DMV" ad **analisi statica del carico di lavoro per tabella/gruppo di tabelle**, stesso ordine di priorità già usato per la revisione SP (dominio Rifiuti core → anagrafiche/infrastrutturali). Le query DMV restano in §4.1–§4.3/§4.5 per un giro successivo, se/quando emergeranno volumi reali.

**Decisione 2026-08-14 — qualità query (non-sargability ecc.)**: durante il punto 2 è emerso un predicato non-sargable (`YEAR(r.Data)=@Anno` in `upd_Numerazione`). Deciso con l'utente di **non aprire una passata dedicata** di revisione qualità su tutte le 284 SP (sforzo paragonabile alla revisione SP appena chiusa, e con questi volumi di dati l'impatto è comunque nullo oggi) — questi pattern vengono annotati come sottoprodotto dell'analisi indici tabella per tabella già in corso, senza fronte separato.

**Decisione 2026-08-14 — soglia per modifiche strutturali invasive**: l'utente ha chiarito che, non esistendo un ambiente di produzione, il costo operativo di un cambio invasivo (drop/recreate di una PK, riordino chiave, ecc.) non è più un freno — **da qui in avanti propongo anche modifiche strutturali (non solo indici secondari) ogni volta che c'è un beneficio di performance reale**, non necessariamente solo `CREATE`/`DROP INDEX`. Resta comunque valido il criterio di **non proporre un cambio quando il beneficio è oggettivamente nullo** (es. riordino della PK clustered sulle tabelle satellite `tblRifiutiMovimenti{Produttori,Trasportatori,Destinatari,Intermediari}`, scartato al punto 3 non per prudenza ma perché il fan-out per `Id` è vincolato a ≤3 righe dalla logica applicativa — stesso costo di lettura a qualunque scala, nessun guadagno possibile riordinando la chiave).

### Ordine di lavoro (nuovo, per tabella/gruppo)

**Dominio Rifiuti — core:**
1. `tblRifiutiRegistrazioni` (+ `tblRifiutiRegistrazioniRelazioni`, satelliti Etichette/Esiti)
2. `tblRifiutiMovimenti` (+ satelliti Produttori/Trasportatori/Destinatari/Intermediari/ClassiPericolo/Log)
3. `tblRifiutiFormulari` (+ Etichette)
4. `tblRifiutiAutorizzazioni` (+ satelliti Conducenti/Eer/Targhe/Attivita)
5. `tblRifiutiRegistri`
6. `tblRifiutiModelli` (+ satelliti ClassiPericolo/Etichette)

**Anagrafiche/infrastrutturali (toccate dalla revisione SP):**
7. `tblSedi` (+ `tblSediInterne`/`tblSediEsterne`)
8. `tblUtenti`
9. `tblScadenze`/`tblServizi`/`tblServiziAssegnati` (+ `tblEventi`/`tblCalendari`, catena titolarità condivisa)
10. `tblDomini`, `tblTipi`, `tblAree`, `tblEtichette` (moduli non ancora rivisti come SP ma rilevanti per gli indici, vedi `context-4_0_ecomatico.md` §"Moduli NON ancora rivisti")

### Stato avanzamento

| # | Punto | Stato | Note |
|---|---|---|---|
| 1 | Statistiche obsolete `tblRifiuti*` (DMV) | ✅ Completato | Volumi troppo piccoli (0-839 righe) perché le statistiche siano un problema reale. Nessuna azione. 2 statistiche con `STATS_DATE` NULL (`IX_RifiutiRegistrazioniEtichette_IdEtichetta`, `IX_RifiutiFormulariEtichette_IdEtichetta`) — innocuo, non approfondito. |
| 2 | `tblRifiutiRegistrazioni` + satelliti | ✅ Completato | Nessuna azione: indici esistenti già ben allineati ai pattern reali letti dalle 9 SP di lettura principali (vedi tabella di analisi in conversazione). Nessun indice mancante, nessuna ridondanza. Nota soft (non indicizzazione): `upd_Numerazione` usa `YEAR(r.Data)=@Anno` non-sargable — da rivalutare in una futura passata qualità SP. |
| 3 | `tblRifiutiMovimenti` + satelliti | ✅ Completato | `IX_RifiutiMovimenti_IdRegistro`: covering index ben progettato, nessuna azione. Satelliti (Produttori/Trasportatori/Destinatari/Intermediari/ClassiPericolo): solo PK clustered, fan-out per Id limitato a poche righe dalla logica applicativa (≤3) — nessuna azione anche a piena scala. **`IX_RifiutiMovimentiLog_Id_Data` rimosso (DROP eseguito 2026-08-14)**: chiave ridondante con la PK clustered (backward scan), `INCLUDE` copriva 16/19 colonne senza che nessuna query reale ne avesse bisogno (l'unica query nel codebase seleziona solo `Data`). Verificato: nessun trigger/funzione coinvolti, solo 3 SP (`uspRifiutiFormulari_upd`, `uspRifiutiRegistrazioni_upd`, `uspRifiutiMovimenti_del_All`). |
| 4 | `tblRifiutiFormulari` + Etichette | ✅ Completato | Nessuna azione: stessa struttura a due indici di `tblRifiutiRegistrazioni` (punto 2), pattern reali tutti coperti (catena Sessione→Registro→Movimento→Formulario, filtro Etichette). Nota: `IX_RifiutiFormulari_DataEmissione_Lock` (e il suo gemello `IX_RifiutiRegistrazioni_Data_Lock` al punto 2) non hanno un percorso d'uso "certo" nelle SP lette, ma restano piani alternativi legittimi per range-query dirette su Data — non abbastanza certezza per un DROP come nel caso del Log (punto 3), lasciati. |
| 5 | `tblRifiutiAutorizzazioni` + satelliti | ✅ Completato | Nessuna azione: `IX_RifiutiAutorizzazioni_IdSede_IdRuolo_Lock` combacia quasi perfettamente col pattern dominante (`#sediUtente`/sedi azienda → autorizzazioni per IdSede+IdRuolo, `Lock<2`/`Lock=0`). Tutti i satelliti (Conducenti/Eer/Targhe/TargheEerEsclusi/Attivita) interrogati sempre via `Id` (leftmost PK) o combacianti con l'ordine esatto della PK composita — nessun indice secondario necessario, fan-out per riga limitato dalla logica applicativa. |
| 6 | `tblRifiutiRegistri` | ✅ Completato | **`IX_RifiutiRegistri_IdSede` creato (2026-08-14)** — finding più significativo dell'audit finora: tabella con 44 SP referenzianti (snodo centrale titolarità dell'intero dominio Rifiuti) e zero indici non-clustered. Il join inverso `g.IdSede = i.Id` (verifica titolarità via `ufnSedi_get_SediInterneBySessione_List`) è il pattern più ripetuto di tutto l'audit, prima serviva solo da scan completo. Costo di mantenimento nullo: `IdSede` è immutabile dopo `_ins`. |
| 7 | `tblRifiutiModelli` + satelliti | ✅ Completato | Satelliti (ClassiPericolo/Etichette): nessuna azione, stesso pattern degli altri satelliti. **Bug di titolarità reale trovato e corretto** (non un finding di indicizzazione): `get_SelectList` scopava i Modelli per Tipo di registro invece che per Registro specifico, leak cross-azienda — confermato dall'utente, fix deployato, dettaglio in memoria persistente (`project_review_uspRifiutiModelli.md`, riaperta). **`IX_RifiutiModelli_IdRegistro_Lock` creato** (filtrato `Lock<2`): `IdRegistro` è il pattern dominante sia in `get_List` che nel `get_SelectList` appena corretto, tabella senza alcun indice secondario prima. |
| 8 | `tblSedi`/`tblSediInterne`/`tblSediEsterne` | ✅ Completato | Nessuna azione: fan-in più alto dell'audit (71 SP) ma già ben indicizzato. Verificato anche il percorso critico condiviso da ogni titolarità check del DB (`ufnSedi_get_SediInterneByUtente_List` e derivate) — tutti e 3 i rami coperti (`IX_SediInterne_IdDominio`, `IX_Sedi_IdParent_Lock`, PK di `tblUtentiSediInterne`). `IX_Sedi_IdParent_Lock` è un match esatto anche nell'`INCLUDE` per `get_SediAssociate_List`. |
| 9 | `tblUtenti` | ✅ Completato | **3 indici creati (2026-08-14)**: tabella con solo PK su `Id`, ma il percorso di autenticazione (login/reset password) cerca sempre per `Email`/`TokenReset`/`IdDominio`, mai per `Id`. `IX_Utenti_Email` (no filtro: `get_Start` non filtra `Lock`), `IX_Utenti_TokenReset` (filtrato `WHERE TokenReset IS NOT NULL`, dato sparso), `IX_Utenti_IdDominio_Lock` (filtrato `Lock<2`). Non proposto `UNIQUE` su `Email`: il `TOP 1 ORDER BY Id` difensivo in `get_LoginByEmail` suggerisce email duplicate tollerate/possibili — vincolo di integrità dati fuori perimetro senza verifica dedicata. |
| 10 | `tblScadenze`/`tblServizi`/`tblEventi`/`tblCalendari` | ✅ Completato | La maggior parte del gruppo già ben indicizzata (`IX_Eventi_IdCalendario_IdTipo_Lock`, `IX_Scadenze_IdEvento`, `IX_Servizi_IdEvento`, `IX_Calendari_IdSede`, verificati contro i pattern reali di `uspCalendari_*`/`uspScadenze_get_CalendarioMese_List`). **`IX_EventiUtenti_IdUtente` creato (2026-08-14)**: `ufnEventi_get_Assegnati_List` (dietro `uspServiziAssegnati_get_List`, la vista "miei servizi assegnati" dei tecnici) filtrava `IdUtente` — colonna non-leftmost della PK `(Id, IdUtente)`, nessun seek possibile prima. |
| 11 | `tblDomini`/`tblTipi`/`tblAree`/`tblEtichette` | ✅ Completato | `tblAree` già coperta da `IX_Aree_IdDominio_Lock`. `tblDomini`: nessuna azione, cardinalità intrinsecamente piccola (tabella tenant). **`IX_Etichette_IdSede_IdModulo_Lock` e `IX_Tipi_IdSede_IdModulo_Lock` creati (2026-08-14)**: pattern `IdSede+IdModulo+Lock=0` ripetuto identico in almeno 6 moduli diversi (`get_Etichette_SelectList` di Formulari/Modelli/Registrazioni/Scadenze/Servizi + le SP proprie di Etichette/Tipi) — secondo finding più diffuso dell'audit dopo `tblRifiutiRegistri`. |

### Ordine di lavoro — moduli introdotti dopo il 2026-08-14

Il modulo core era stato chiuso col DB ancora "solo sviluppo". Nel mese successivo sono nati 5 moduli nuovi (25 tabelle) più nuovi campi RENTRI/Avvisi su 4 tabelle già "chiuse" sopra — riaperte solo per i nuovi pattern, non per una rirevisione completa. Deploy: `tools/deploy_produzione_2026-09-23_indici_moduli_nuovi.sql`.

| # | Tabella/gruppo | Stato | Note |
|---|---|---|---|
| 12 | `tblRifiutiLimiti` (+ `tblRifiutiLimitiEer`/`Etichette`/`Operazioni`) | ✅ Completato | **`IX_RifiutiLimiti_IdSede_Lock` creato**: zero indici secondari su una tabella che alimenta `ufnRifiutiLimiti_get_Verifica_List`, invocata a ogni refresh badge/dashboard Avvisi. Le 3 tabelle ponte satelliti: nessuna azione, filtrate sempre per `IdLimite` (leading PK). |
| 13 | Modulo EoW (`tblEoWLotti`, `tblEoWMagazzini`, `tblEoWAllocazioni`, `tblEoWAllocazioniTipi`, `tblEoWLottiAllocazioni`, `tblEoWLottiRifiutiRegistrazioni`) | ✅ Completato | **5 indici creati**: `IX_EoWLotti_IdSede_Lock`, `IX_EoWMagazzini_IdSede_Lock`, `IX_EoWAllocazioni_IdSede_Lock`, `IX_EoWLottiAllocazioni_IdAllocazione` (2ª colonna PK, non seek-friendly da sola), `IX_EoWLottiRifiutiRegistrazioni_IdLotto` (stesso motivo). `tblEoWAllocazioniTipi`: nessuna azione, lookup a bassa cardinalità. |
| 14 | Modulo RENTRI — Certificati/Credenziali (`tblRentriCredenziali`, `tblRentriCertificati`) | ✅ Completato | **`IX_RentriCredenziali_IdDominio_Lock` e `IX_RentriCertificati_IdDominio_Lock` creati**: filtri ricorrenti `IdDominio`/`Lock`, PK solo su `Id` senza copertura. `tblRentriAccreditamenti`, `tblRentriRegistri`, `tblRentriCredenzialiSedi`, `tblRentriFirmeOperazioni`, `tblRentriFirmeCredenziali`, `tblRentriRegistrazioniRettifiche`: nessuna azione, già coperti da PK/indici creati contestualmente alla tabella. |
| 15 | Modulo MUD (`tblRifiutiMud`, `tblRifiutiMudRegistri`, `tblSediDatiEstesi`, `tblAteco`) | ✅ Completato | Nessuna azione: nessun pattern `_List` con filtro ripetuto emerso, tutte le tabelle interrogate per `Id`/PK o join 1:1. Da riaprire solo se emergesse in futuro una `_get_List` filtrata per `IdSede+Anno`. |
| 16 | Carichi automatici da Modello (`tblRifiutiModelliRegistrazioniAuto`, `tblRifiutiModelliRegistrazioniAutoEtichette`) | ✅ Completato | **`IX_RifiutiModelliRegistrazioniAuto_IdModello` creato**: righe multiple per `IdModello` (split percentuali), PK `Id` standalone non copre il filtro. Tabella ponte Etichette: nessuna azione, interrogata per `Id` (leading PK). |
| 17 | `tblRifiutiMovimenti` — riaperta solo per i campi RENTRI formulario digitale | ✅ Completato | **`IX_RifiutiMovimenti_IdRegistro` esteso** (stessa chiave, `CREATE ... WITH DROP_EXISTING=ON`): `INCLUDE` ampliato con le 6 colonne `RentriFormularioStato`/4 date/`RentriFormularioInviiConservazione`, lette/filtrate come residuo in 5+ SP RENTRI senza mai essere in `INCLUDE`. Scartato un indice filtrato standalone su `RentriFormularioStato`: nessun pattern di scan globale nel codice, il seek resta sempre via `IdRegistro`. |
| 18 | `tblRifiutiRegistrazioni` — riaperta solo per i campi RENTRI | ✅ Completato | **`IX_RifiutiRegistrazioni_IdMovimento_Data_Numero_Lock` esteso** (stessa chiave e filtro `Lock<2`): `INCLUDE` ampliato con `RentriIdentificativo`/`RentriData`. `ConservazioneSostitutiva` escluso: mai un predicato di ricerca, solo lettura/scrittura per PK. |
| 19 | `tblRifiutiAutorizzazioni` — riaperta per il pattern nuovo del modulo Avvisi | ✅ Completato | **`IX_RifiutiAutorizzazioni_IdSede_DataFine_Lock` creato** (nuovo, non sostituisce `_IdSede_IdRuolo_Lock`): pattern distinto dalla titolarità classica, 3 SP Avvisi filtrano `IdSede`+booleani+range `DataFine` con `ORDER BY DataFine` paginato, mai per `IdRuolo`. **Voce aperta non risolta in questo giro**: `uspRifiutiAutorizzazioni_get_MatchImportazione` filtra `tblSedi.CodiceFiscale` (5 varianti per ruolo) senza indice dedicato su quella colonna — segnalato, non incluso nello script perché fuori dal perimetro esplicito di questa riapertura (tabella `tblSedi` già chiusa al punto 8 su altri pattern) e serve una verifica dedicata sul volume di `#sediUtente` in scenari multi-sede. |
| 20 | `tblCalendari` — riaperta per il pattern del modulo Avvisi | ✅ Completato | **`IX_Calendari_IdSede` rinominato/esteso in `IX_Calendari_IdSede_IdModulo_Lock`** (drop + create, chiave `IdSede+IdModulo` filtrata `Lock<2`): stesso pattern già risolto due volte nello stesso DB (`IX_Etichette_IdSede_IdModulo_Lock`, `IX_Tipi_IdSede_IdModulo_Lock`); Avvisi aggiunge frequenza (polling) a un gap preesistente non prioritizzato quando i volumi erano irrilevanti. Verificato nessun hint `WITH (INDEX(...))` nelle SP referenzianti. |

### Modulo Fatturazione e Anagrafica estesa (2026-10-11)

23 tabelle nate fra il 2026-10-06 e il 2026-10-10 (fatture, righe, rate, pagamenti, prima nota, clienti e fornitori, banche e casse, aliquote IVA, conti, dati fiscali, 12 tabelle di decodifica), 93 SP e 3 funzioni. Le tabelle avevano già 7 indici secondari creati insieme a loro, con "tbl" nel nome. Script: `tools/fatturazione_indici.sql` (rieseguibile); deploy: `tools/deploy_produzione_2026-10-11_indici_fatturazione.sql`, che comprende le 5 SP modificate.

Verifica in sviluppo con 160.000 fatture, 160.000 rate e 152.000 pagamenti inseriti in una transazione poi annullata (16 aziende, 5 anni), letture logiche da `SET STATISTICS IO`.

| # | Tabella/gruppo | Stato | Note |
|---|---|---|---|
| 21 | Nomi alla convenzione | ✅ Completato | **10 indici rinominati** (`sp_rename`): i 7 del modulo (`IX_tblFatture_…` → `IX_Fatture_…`, ecc.) e i 3 di `tblAmministratori`/`tblAmministratoriSedi`. I due unici filtrati prendono il suffisso `_Lock`. Nessuna SP li richiamava con un hint. |
| 22 | `tblFattureRatePagamenti` | ✅ Completato | **`IX_FattureRatePagamenti_IdPagamento` creato** (`INCLUDE (Importo)`): `IdPagamento` è la seconda colonna della PK `(IdRata, IdPagamento)`. Lo cercano la prima nota (due volte per movimento), `uspPagamenti_get_List`/`_get_Rate_List`/`_del`/`_del_Manuale`/`_upd_Manuale` e il controllo della chiave esterna all'eliminazione di un pagamento. Misura: 3 letture. |
| 23 | `tblPagamenti` | ✅ Completato | **`IX_Pagamenti_IdSede_IdBancaCassa_DataContabile_DataRegistrazione_Lock` creato** (filtrato `Lock = 0`, `INCLUDE (Tipo, Importo, IdModalita, IdConto, Causale)`): la tabella non aveva indici secondari. La chiave è l'ordine della finestra del saldo progressivo della prima nota (`PARTITION BY IdBancaCassa ORDER BY DataContabile, DataRegistrazione, Id`), che legge tutti i movimenti attivi dell'azienda. Misura: prima nota, una pagina, 81-119 letture su 2.188 pagine della tabella. `uspBancheCasse_del` e `uspFattureConti_del` ora filtrano anche per `IdSede` e usano questo indice (4 letture invece di 2.037). |
| 24 | `tblFatture` | ✅ Completato | **`IX_Fatture_IdSede_Tipo_DataEmissione` esteso** con `INCLUDE (Lock, IdTipo, Numero, Sezionale, IdClienteFornitore, DataRegistrazione)`: ogni query filtra `Lock = 0`, prima con un lookup per fattura. Non filtrato, perché la cancellazione di un'azienda cerca per `IdSede` senza `Lock`. **`IX_Fatture_IdFatturaRiferimento` creato** (filtrato `IS NOT NULL`, `INCLUDE (Lock)`): `uspFatture_del` e la chiave esterna di `tblFatture` su sé stessa cercano per questa colonna a ogni eliminazione. Misura: 2 letture. `IX_Fatture_IdClienteFornitore`: solo rinominato. |
| 25 | `tblFattureRate`, `tblFattureRighe`, `tblFattureRigheImporti` | ✅ Completato | **`IX_FattureRate_IdFattura` esteso** con `INCLUDE (Importo, Abbuono, DataScadenza)`, lette da scadenziario ed elenco fatture. `IX_FattureRighe_IdFattura`: solo rinominato, copre già `ufnFatture_get_Totali`. `tblFattureRigheImporti`: nessun indice su `IdAliquotaIva`/`IdConto`, usati solo dai controlli di cancellazione di aliquote e conti (rari) a fronte di un costo su ogni riga inserita. Da riaprire se quelle cancellazioni diventassero lente. |
| 26 | `tblBancheCasse`, `tblAliquoteIva`, `tblFattureConti`, `tblClientiFornitori` | ✅ Completato | **`IX_BancheCasse_IdSede` e `IX_AliquoteIva_IdSede` creati**, come quello che `tblFattureConti` aveva già: il filtro per azienda è l'unico accesso oltre la PK. `tblClientiFornitori`: l'unico filtrato `(IdAziendaInterna, IdSede, Tipo)` copre elenco, select e duplicati; `(IdSede)` copre il controllo di cancellazione della sede esterna. Tabelle di decodifica e `tblFattureDatiFiscali`: solo PK, nessuna azione. |

**Numerazione delle fatture (`uspFatture_upd`, `uspFatture_get_ProssimoNumero`)**: il filtro `IIF(@tipo = 'C', DataEmissione, DataRegistrazione) >= …` non permetteva il seek sulla data, e con `UPDLOCK, HOLDLOCK` bloccava tutte le fatture di quell'azienda e tipo. Riscritto in due letture, una per tipo, con il filtro sulla colonna: per i clienti 12 letture invece di 49 e blocco limitato all'anno; per i fornitori (anno della `DataRegistrazione`, che non è in chiave) resta il blocco sulle fatture fornitore dell'azienda. In `uspFatture_upd_Xml` tolto l'hint `UPDLOCK, HOLDLOCK` dall'`UPDATE` di `tblFattureDatiFiscali`, superfluo.

**Elenco fatture (`uspFatture_get_List`)**: calcolava `ufnFatture_get_Totali` e la somma delle rate per tutte le fatture che passavano il filtro, non solo per la pagina. Ora una CTE filtra, ordina e prende la pagina con le sole colonne dell'indice, e solo per quelle righe si leggono le altre colonne e si calcolano totali e rate. Con 846 fatture nell'anno e 20 righe a video: circa 1.000 letture invece di 38.350 (`tblFattureRighe` 600 invece di 25.380, `tblFatture` 136 invece di 5.153). Stesso schema da verificare nelle altre `_get_List` che usano una funzione di totali.

**Scadenziario (`uspFattureRate_get_Scadenzario_List`)**: il residuo serve al filtro per stato, quindi va calcolato per tutte le rate dell'azienda. Ora lo si calcola con le sole colonne di filtro e ordinamento, e tipo, modalità e banca si leggono solo per le rate della pagina. Con 5.000 rate: circa 46.300 letture invece di 71.500 (`tblFatture` 129 invece di 15.393, `tblFattureTipi` 41 invece di 10.005). Restano circa 15.000 letture ciascuna su `tblFattureRate`, `tblFattureRatePagamenti` e `tblPagamenti`.

Entrambe confrontate con la versione precedente su 11 combinazioni di filtri e pagine, a volume: stesse righe.

**Voci aperte, non di indicizzazione:**
- Scadenziario: per scendere ancora serve il pagato memorizzato sulla rata (colonna su `tblFattureRate` aggiornata da `uspPagamenti_ins` e `uspPagamenti_del`), che toglie le letture su `tblFattureRatePagamenti` e `tblPagamenti` (da circa 46.000 a circa 16.000). È una modifica al modello dei dati, con due fonti da tenere allineate: non fatta.
- Numerazione delle registrazioni rifiuti: **risolta il 2026-10-11** (`deploy_produzione_2026-10-11_registrazioni_numerazione.sql`). `uspRifiutiRegistrazioni_upd`, `_ins_CaricoAuto` e `_upd_Numerazione` controllavano e calcolavano il numero fuori dalla transazione e senza blocco; ora bloccano la riga del registro (`UPDLOCK, HOLDLOCK` su `tblRifiutiRegistri`) e leggono la numerazione dopo il blocco. `_upd_Rettifica` e `_upd_Annullamento` bloccano il registro prima delle relazioni (stesso ordine, niente attese incrociate); `_del_Undo` rifiuta il ripristino se il numero è stato riassegnato. Regole: R11 di `registrazioni-rettifiche.md`.
- Da verificare (comportamento precedente, non toccato): `uspRifiutiRegistrazioni_upd` con `@RinumeraRegistro = 1` su una registrazione già confermata a cui si dà il numero di un'altra sposta solo i numeri maggiori (`r.Numero > @RegistrazioneNumero`), lasciando due registrazioni con lo stesso numero; riprodotto chiamando la SP direttamente, da capire se l'applicazione può mandare quella combinazione.

### Modulo Offerte e contratti (2026-10-13)

11 tabelle nate fra il 2026-10-11 e il 2026-10-12 (`tblImporti*`, `tblOfferteContratti*`, `tblFattureDocumenti`), 6 funzioni e circa 40 SP. Avevano 5 indici secondari creati insieme a loro (`IX_Importi_IdSede`, `IX_ImportiRighe_IdImporto`, `IX_OfferteContratti_IdSede`, `UX_OfferteContrattiImporti_IdImporto`, `IX_FattureDocumenti_IdFattura`). Gli indici stanno nella sezione 6 di `tools/offerte_contratti_struttura.sql` (rieseguibile) e nello script di produzione `tools/deploy_produzione_2026-10-12_offerte_contratti.sql`, che alla data non era ancora stato eseguito.

Verifica in sviluppo con dati inseriti in una transazione poi annullata: 96.000 registrazioni in 4 registri (24.000 dell'azienda di prova, circa 2.000 al mese), 6.600 importi (600 dell'azienda), 1.650 contratti, 20.000 documenti già fatturati in 500 fatture, Id sparsi come quelli reali. Letture logiche da `SET STATISTICS IO`.

| # | Tabella/gruppo | Stato | Note |
|---|---|---|---|
| 27 | `tblFattureDocumenti` | ✅ Completato | **`IX_FattureDocumenti_IdImporto`, `IX_FattureDocumenti_IdOffertaContratto`, `IX_FattureDocumenti_IdClienteFornitore` creati** (filtrati `IS NOT NULL`): tre chiavi esterne senza indice. La cancellazione della bozza di un importo (`uspImporti_del`), di un contratto (`uspOfferteContratti_del`) o di un cliente leggeva tutta la tabella, che cresce di una riga per ogni documento fatturato, e poteva restare in attesa di una generazione in corso (`UPDLOCK, HOLDLOCK` sulle righe dei documenti). Misura: 2 letture invece di 232 con 20.000 righe. `IX_FattureDocumenti_IdFattura` copre generazione, conversione delle pre-fatture e "Togli la fattura". |
| 28 | `tblOfferteContratti`, `tblOfferteContrattiImporti` | ✅ Completato | **`IX_OfferteContratti_IdClienteFornitore` creato** (`INCLUDE (Lock)`): controllo di `uspClientiFornitori_del` e chiave esterna sul cliente, prima una scansione di `IX_OfferteContratti_IdSede` (tutte le aziende). Misura: 2 letture invece di 15-25. `IX_OfferteContratti_IdSede` copre elenco, esportazione e controllo di cancellazione dell'azienda; l'unico su `IdImporto` copre il legame con l'importo in entrambe le direzioni insieme alla PK. |
| 29 | `tblImportiRighe`, `tblImportiRigheDettagli` | ✅ Completato | **`IX_ImportiRighe_IdImporto` esteso** con `INCLUDE (Pos, IdTipo, Importo, MinimoFatturabile, Lock)`: `ufnImportiRifiuti_get_ApplicazioneRighe` legge le righe dell'importo applicato per ogni documento, prima con un lookup per riga. Misura: 15.940 letture invece di 47.540 nella verifica di un mese. `tblImportiRigheDettagli`: nessun indice su `IdAliquotaIva`/`IdConto`, usati solo dai controlli di cancellazione di aliquote e conti (161 letture, rari), come per `tblFattureRigheImporti` al punto 25. |
| 30 | `tblImporti`, `tblImportiRifiuti` (+ `Magazzino`, `Servizi`, decodifiche) | ✅ Completato | Nessuna azione sugli indici. `IX_Importi_IdSede` copre elenchi, contratti scaduti e controlli. Controllo di cancellazione di una sede sulle 5 variabili di `tblImportiRifiuti`: 151 letture, raro, nessun indice. Elenchi di importi e contratti: circa 6.000 e 1.000 letture per pagina con 600 importi e 150 contratti (calcolano tutte le righe dell'azienda prima di paginare, a questi volumi non pesa). |
| 31 | Confronto tra importi e registrazioni (`tblImportiRifiuti` riaperta) | ✅ Completato | **Colonna `tblImportiRifiuti.IdSede` e `IX_ImportiRifiuti_IdSede` creati** (`INCLUDE` delle 7 variabili), con le funzioni del confronto riscritte: vedi sotto. Il 2026-10-14 la copia è stata misurata da sola (senza: circa 2 volte più lento) ed è diventata `NOT NULL`, anche su `tblImportiMagazzino`. |

**Confronto tra importi e registrazioni (2026-10-13)**. La verifica della procedura automatica su un mese (3.780 documenti candidati) impiegava da 77 a 116 secondi e 2,6 milioni di letture, e gli indici dei punti 27-30 non la cambiavano. `ufnImportiRifiuti_get_Applicazione` cercava l'importo con una `OUTER APPLY ... TOP (1)` per documento: `tblImportiRifiuti` non aveva la colonna dell'azienda, quindi a ogni esecuzione veniva letta per intero (gli importi di tutte le aziende: 1,8 milioni di letture), e il confronto era eseguito tre volte per documento (importo applicato, importo scartato, e di nuovo dentro `ufnImportiRifiuti_get_ApplicazioneRighe`).

Cosa è cambiato:
- `tblImportiRifiuti.IdSede`: copia dell'azienda dell'importo (`tblImporti.IdSede`), scritta da `uspImportiRifiuti_ins` e mai più modificata. Con `IX_ImportiRifiuti_IdSede` il confronto legge solo gli importi dell'azienda.
- `ufnImportiRifiuti_get_Coincidenti`: l'unico punto con la regola di coincidenza delle variabili e la classe dell'importo (candidato, scartato per contratto non valido alla data, mai candidato). Senza `TOP` né sottoquery; l'etichetta la verifica chi chiama. `FORCESEEK` sul contratto: senza, il piano leggeva tutti i contratti per ogni documento (6 milioni di righe).
- `ufnImportiRifiuti_get_Applicazione_List`: una riga per registrazione di `@Id` o dell'azienda nel periodo; sceglie candidato e scartato con due funzioni finestra, in un solo passaggio. I documenti si selezionano con due rami `UNION ALL` (per chiave, o per azienda e periodo): un unico `WHERE` con `OR` leggeva tutte le registrazioni anche per una sola. `ufnImportiRifiuti_get_Applicazione(@Id)` resta, come involucro.
- `ufnImportiRifiuti_get_RigheImporto(@Id, @IdImporto, @IdClienteFornitore)`: le righe dell'importo già determinato, senza rifare il confronto; la usano `ufnFattureDocumenti_get_Rifiuti` e `uspFatture_ins_Genera`. `ufnImportiRifiuti_get_ApplicazioneRighe(@Id)` resta, come involucro.

Misure (stessi dati dei punti 27-30, più importi con etichetta, trasportatore, destinatario, priorità mancante, offerte, contratti cancellati o senza data di fine, pre-fatture, documenti non fatturabili o con il cliente indicato): verifica di novembre 3 secondi invece di 116 (circa 1 milione di letture, di cui 53.000 su `tblImportiRifiuti` invece di 1,8 milioni); 15-31 ottobre con le pre-fatture 2,3 secondi invece di 53; novembre di un solo cliente 8 secondi invece di 67. Singolo documento invariato (circa 300 letture). Risultati identici alla versione precedente, confrontati con `EXCEPT` nei due sensi su 5 prove: 3.780, 1.373 e 146 documenti della generazione, 480 documenti uno per uno e le loro 949 righe.

Restano per documento la lettura degli importi dell'azienda (14 pagine con 676 importi) e due accessi per ogni importo che coincide (`tblImporti`, `tblOfferteContrattiImporti`). Stessa colonna e stesso schema da ripetere per `tblImportiMagazzino` e `tblImportiServizi` quando avranno il confronto con i documenti.

**La copia di `IdSede` serve davvero? (2026-10-14)**. Il guadagno qui sopra veniva da due modifiche fatte insieme, la copia e la riscrittura a insiemi, quindi la copia da sola non era dimostrata (l'azienda si ricava sempre da `tblImporti.IdSede`). Misurata sugli stessi dati, in una transazione annullata, la variante senza copia: `ufnImportiRifiuti_get_Coincidenti` che filtra su `i.IdSede` (`IX_Importi_IdSede`, che include priorità e stato) e senza `IX_ImportiRifiuti_IdSede`. Due esecuzioni per prova, valori stabili; risultati identici (`EXCEPT` nei due sensi).

| Prova | Letture con la copia | Letture senza | Tempo con la copia | Tempo senza |
|---|---:|---:|---:|---:|
| Verifica di novembre (3.780 documenti) | 1.007.000 | 1.370.000 | 9,4 s | 19,9 s |
| Novembre di un solo cliente (146) | 824.000 | 1.187.000 | 8,5 s | 18,6 s |
| 15-31 ottobre con le pre-fatture (1.373) | 534.000 | 740.000 | 5,5 s | 11,9 s |
| 480 documenti uno per uno | 89.000 | 124.000 | 0,6 s | 0,6 s |
| Un documento dalla scheda | 137 | 248 | 18 ms | 20 ms |

Senza la copia il filtro sull'azienda costa poco su `tblImporti`, ma le variabili si cercano poi in `tblImportiRifiuti` una volta per importo e per documento: 635.000 letture su `tblImportiRifiuti` invece di 72.000 nella verifica di novembre. Con la copia filtro e variabili stanno nello stesso indice. **Decisione: la copia resta e diventa `NOT NULL`**, su `tblImportiRifiuti` e `tblImportiMagazzino` (`offerte_contratti_struttura.sql`, `offerte_contratti_magazzino_struttura.sql` e i due script di produzione del 12 e del 13/10): il confronto filtra con `= @IdAzienda`, e una copia mancante farebbe sparire l'importo senza errori. Lo stesso, `NOT NULL` compreso, vale per `tblImportiServizi`. `tblImportiMagazzino` non è stata misurata (mancano dati di prova dei DDT): lo schema è lo stesso.

**Voce aperta, da osservare: tempi della verifica di novembre**. Il 13/10 era di 4 secondi, il 14/10 di 9-10 secondi con le stesse letture, tabella per tabella (stesso piano nella forma, seriale), e con una sola esecuzione da 3,4 secondi che non si è ripetuta. Escluso il ramo dei DDT di `ufnFattureGenera_get_Documenti`: la versione del 13/10 della funzione, installata accanto, impiega lo stesso tempo. Escluse anche la modifica di `ufnImportiRifiuti_get_RigheImporto` (data del formulario mancante, solo un testo diverso nella sostituzione) e la frammentazione di `IX_ImportiRifiuti_IdSede` (ricostruito: tempi invariati). La prova di controllo (480 documenti uno per uno) costa come il 13/10. Il costo è quasi tutto CPU con le stesse letture: per capirlo vanno confrontati i piani effettivi di un'esecuzione veloce e di una lenta.

**Voce aperta, da osservare**: i candidati alla fatturazione si cercano per intervallo di date su `IX_RifiutiRegistrazioni_Data_Lock`, che contiene le registrazioni di tutte le aziende (96.727 letture su `tblRifiutiRegistrazioni` nella prova), oppure dal registro attraverso tutti i suoi movimenti: né la registrazione porta il registro né il movimento porta la data. È lo stesso schema degli elenchi e dei report dei rifiuti, già accettato al punto 2; va rivisto se la generazione o i report diventassero lenti con più aziende.

Legenda: 🔲 Non iniziato · 🔄 In corso · ✅ Completato (con eventuale nota su modifiche applicate/rimandate).
