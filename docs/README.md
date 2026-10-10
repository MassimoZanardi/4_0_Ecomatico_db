# Documentazione

La documentazione di progetto (regole di business e piani di test) è nel repo dell'app, su GitHub:
`C:\MyDoc\App\4_0_Ecomatico\docs` (indice in `docs/README.md`).

- Registrazioni e rettifiche RENTRI: `docs/regole/registrazioni-rettifiche.md`

## Ricostruire il database da zero

Il repo contiene lo schema completo di `4_0_ecomatico`, senza dati: tipi tabella (`sql/types`), tabelle con
chiavi, indici e chiavi esterne (`sql/tables`), funzioni, viste e stored procedure.

- **Ricostruire**: `tools\ricostruisci_database.ps1 -Server SERVER\ISTANZA -Database nome_nuovo` crea un database
  nuovo e vuoto ed esegue tutti i file. Non tocca mai un database esistente. Le viste e le SP che leggono
  `1_0_rentri` richiedono quel database sullo stesso server.
- **Verificare**: `tools\confronta_schema.sql` confronta il database ricostruito con uno esistente (colonne,
  indici, chiavi esterne, tipi, testo di SP, funzioni e viste) e deve dare 0 righe.
- **Tenere aggiornato il repo**: dopo ogni modifica alla struttura (colonna, indice, chiave esterna, tabella
  nuova o tolta) eseguire `tools\genera_tabelle.ps1`, che riscrive dal database i file di `sql/tables` e
  `sql/types`, e fare il commit insieme alla modifica. SP, funzioni e viste si scrivono nei loro file.
- I dati delle tabelle di configurazione (menu, pagine, funzioni, moduli, causali, EER) non sono nel repo: un
  database ricostruito ha la struttura ma non è utilizzabile dall'applicazione finché non vengono caricati.
