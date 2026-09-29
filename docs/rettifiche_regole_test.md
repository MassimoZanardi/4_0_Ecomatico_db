# Registrazioni e rettifiche RENTRI - regole e test di coerenza

Aggiornato al 2026-09-29 (repo DB `642cebe` = `deployed-prod`). Ogni regola indica la SP che la applica; le regole
sono state ricontrollate sulle definizioni in `sql/`, allineate al DB live.

Terminologia:
- **Originale**: registrazione gia' inviata al RENTRI che viene rettificata o annullata. Non viene mai modificata.
- **Rettifica**: nuova registrazione collegata all'originale (`tblRentriRegistrazioniRettifiche`, `Id` = originale,
  `IdRettifica` = rettifica). Due sotto-tipi: **correzione** (`Annullata` = 0/NULL) e **annullamento** (`Annullata` = 1).
- **Stato amministrativo**: cio' che e' registrato e trasmesso al RENTRI (registro, stampa, conservazione, payload).
- **Stato operativo**: cio' che usa Ecomatico per giacenze, residui, relazioni carico/scarico, limiti, carichi
  automatici, EoW. Letto da `viewRifiutiRegistrazioniEffettive`.
- **Relazione**: riga di `tblRifiutiRegistrazioniRelazioni` (`Id` = figlio, `IdParent` = padre). Due tipi:
  - **consumo**: padre scarico (S) -> figlio carico (C): lo scarico preleva dal carico;
  - **derivazione**: padre carico (C, es. M/NP generato) -> figlio scarico (S, es. trattamento interno I).

---

## A. Regole

### R1 - Registrazione inviata al RENTRI (`RentriIdentificativo`/`RentriData` valorizzati)
| # | Regola | SP |
|---|---|---|
| R1.1 | Non modificabile | `uspRifiutiRegistrazioni_upd` ("già stata inviata al RENTRI: non può più essere modificata") |
| R1.2 | Non cancellabile (vale anche per una rettifica inviata) | `uspRifiutiRegistrazioni_del` |
| R1.3 | Non rinumerabile: blocca l'intero intervallo | `uspRifiutiRegistrazioni_upd_Numerazione` |
| R1.4 | Non puo' essere padre di nuove associazioni ne' perderne | `uspRifiutiRegistrazioni_ins_Relazione`, `_ins_RelazioniTutte`, `_del_Relazione` |
| R1.5 | Formulario con registrazione associata inviata: non modificabile/cancellabile | `uspRifiutiFormulari_upd`, `_del` |
| R1.6 | L'unico modo di cambiarla e' una rettifica (R2) | - |

### R2 - Creazione di una rettifica (correzione o annullamento)
| # | Regola | SP |
|---|---|---|
| R2.1 | Solo su originale inviato al RENTRI | `uspRifiutiRegistrazioni_ins` |
| R2.2 | Mai rettifica/annullamento di una rettifica | `uspRifiutiRegistrazioni_ins` |
| R2.3 | Una sola rettifica non inviata per originale (anche in bozza Lock 2); correzione e annullamento si escludono | `uspRifiutiRegistrazioni_ins` |
| R2.4 | Originale con annullamento inviato: mai piu' ne' annullabile ne' rettificabile | `uspRifiutiRegistrazioni_ins` |
| R2.5 | Stesso registro dell'originale, nessuna scelta | `uspRifiutiRegistrazioni_ins` |
| R2.6 | Correzione precompilata con i valori **amministrativi** in vigore (ultima correzione confermata, altrimenti originale); i valori **operativi** in vigore vanno nella riga di tracking | `uspRifiutiRegistrazioni_ins` |
| R2.7 | Nessuna relazione copiata; la rettifica non avra' mai relazioni proprie | `uspRifiutiRegistrazioni_ins`, `_ins_Relazione` |
| R2.8 | Menu Index "RENTRI - Rettifica"/"Annullamento" solo su registrazione inviata e non rettifica | `Index.cshtml` (`data-rettifica-eleggibile`) |

### R3 - Correzione
| # | Regola | SP |
|---|---|---|
| R3.1 | Tutti i campi modificabili, anche Eer/stato fisico/UM/quantita' con relazioni attive: mai bloccata dalle relazioni | `uspRifiutiRegistrazioni_upd_Rettifica` |
| R3.2 | L'originale non viene mai modificato | `uspRifiutiRegistrazioni_upd_Rettifica` |
| R3.3 | Al RENTRI vanno sempre i valori della correzione | `viewRentriRegistrazioni` |
| R3.4 | **Operativa** se non ci sono relazioni attive, oppure se (con relazioni) Eer/SF/UM non cambiano e: lato figlio (carico consumato) la quantita' non scende sotto il gia' prelevato; lato padre (scarico con carichi) la quantita' non cambia | `ufnRifiutiRegistrazioni_get_RettificaOperativa` |
| R3.5 | **Tutto o niente**: se non operativa restano TUTTI i valori operativi precedenti (niente applicazione parziale) | idem |
| R3.6 | Relazioni considerate: quantita' > 0, nessuna delle due in bozza, controparte non annullata operativamente | idem |
| R3.7 | Non operativa -> modale "Rettifica RENTRI" di conferma prima del salvataggio (anteprima) | `uspRifiutiRegistrazioni_get_RettificaIsOperativa`, `Edit.cshtml` (`RettificaNonOperativaDiv`) |
| R3.8 | La decisione si ricalcola a ogni salvataggio finche' non e' inviata; dopo l'invio resta fissa | `uspRifiutiRegistrazioni_upd_Rettifica` |
| R3.9 | Durante la conferma le relazioni dell'originale sono bloccate (UPDLOCK/HOLDLOCK) | idem |

### R4 - Annullamento
| # | Regola | SP |
|---|---|---|
| R4.1 | Unico campo modificabile: Note, obbligatoria ("Indicare il motivo dell'annullamento") -> `annotazioni` RENTRI | `uspRifiutiRegistrazioni_upd_Annullamento`, `Annullamento.cshtml` |
| R4.2 | Pagina dedicata `/rifiuti/registrazioni/annullamento/{id}` | `Annullamento.cshtml` |
| R4.3 | L'originale non viene mai modificato; mai bloccato dalle relazioni | `uspRifiutiRegistrazioni_upd_Annullamento` |
| R4.4 | **Operativo** (Quantita operativa = 0) se l'originale NON e' figlio di relazioni attive | `ufnRifiutiRegistrazioni_get_RettificaOperativa` |
| R4.5 | **Non operativo** se l'originale e' figlio: carico consumato da scarichi, oppure scarico da cui derivano carichi (I -> M/NP). Resta annullato al RENTRI, continua a valere in Ecomatico | idem |
| R4.6 | Scarico senza carichi derivati: operativo, i carichi che consumava tornano disponibili | idem |
| R4.7 | Carico M: mai figlio, quindi annullamento sempre operativo | idem + `_ins_Relazione` |
| R4.8 | Non operativo -> modale "Annullamento RENTRI" di conferma | `Annullamento.cshtml` (`AnnullamentoNonOperativoDiv`) |

### R5 - Cancellazione di una rettifica non ancora inviata
| # | Regola | SP |
|---|---|---|
| R5.1 | Sempre irreversibile (hard delete, mai Lock 4/Undo), niente popup "Annulla cancellazione" | `uspRifiutiRegistrazioni_del`, `Index.cshtml` |
| R5.2 | Solo singolarmente, con modale "Cancella rettifica" e checkbox di conferma | `uspRifiutiRegistrazioni_del` (`@IsMultipla`), `Index.cshtml` |
| R5.3 | Nessun ripristino sull'originale: tornano operativi i valori precedenti (ultima altra rettifica confermata o originale; per un annullamento la quantita' piena) | `uspRifiutiRegistrazioni_del` |
| R5.4 | Correzione: bloccata se le relazioni si sono basate sui valori corretti e con i precedenti una giacenza andrebbe sotto zero | idem |
| R5.5 | Annullamento di scarico: bloccata se i suoi carichi sono stati poi scaricati da altre registrazioni | idem |
| R5.6 | Rettifica non operativa: si cancella sempre | idem |
| R5.7 | Bozza (Lock 2) mai confermata: si cancella sempre, non ha mai contato | idem |

### R6 - Valori operativi (`viewRifiutiRegistrazioniEffettive`)
| # | Regola |
|---|---|
| R6.1 | Valori = ultima rettifica confermata (Lock 0, per Data/Numero desc) di qualunque tipo, letti dalla sua riga di tracking; altrimenti quelli dell'originale |
| R6.2 | Le bozze (Lock 2) non contano |
| R6.3 | `IsAnnullata` = 1 solo per annullamento operativo (Annullata = 1 e Quantita = 0) |
| R6.4 | `IsRettifica` = 1 sulla registrazione di rettifica stessa: mai un movimento reale |

### R7 - Chi legge cosa
| Uso | Fonte |
|---|---|
| Giacenze (`uspRifiutiGiacenze_get_List/_get_Carichi_List/_get_Quantita`) | vista, `IsRettifica = 0` |
| Registrazioni da associare, associate, relazioni, `_ins_Relazione(Tutte)` | vista |
| Controllo quantita'/EER in `uspRifiutiRegistrazioni_upd`, `uspRifiutiFormulari_upd`, `ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore` | vista |
| Limiti (`ufnRifiutiLimiti_get_Verifica_List`) | vista, `IsRettifica = 0` |
| Carichi automatici (`uspRifiutiRegistrazioni_ins_CaricoAuto`) | vista |
| EoW: quote, allocazioni, giacenze carichi, elenco registrazioni del lotto | vista |
| Stampa registro, conservazione, payload RENTRI | `tblRifiutiMovimenti` (valori propri di ogni registrazione, originale compreso) |

### R8 - Esclusioni delle registrazioni di rettifica
| # | Regola | SP |
|---|---|---|
| R8.1 | Mai in giacenza, mai tra i candidati da associare | giacenze, `_get_RegistrazioniDaAssociare_List` |
| R8.2 | Mai relazioni proprie ("non può avere relazioni di carico/scarico") | `_ins_Relazione` |
| R8.3 | Mai origine di carichi automatici ("non può generare carichi") | `_ins_CaricoAuto` |
| R8.4 | Mai quote EoW ("non può ricevere quote EoW") | `uspEoWLottiRifiutiRegistrazioni_ins`, `uspEoWAllocazioni_esegui` |
| R8.5 | Mai nei limiti | `ufnRifiutiLimiti_get_Verifica_List` |

### R9 - Registrazione annullata operativamente
| # | Regola | SP |
|---|---|---|
| R9.1 | Le relazioni esistenti restano (stampa/payload) ma non consumano: filtro `vp.Quantita > 0` sul padre | giacenze, limiti, `_upd` |
| R9.2 | Non associabile a nuove registrazioni ("Una registrazione annullata non può essere associata") | `_ins_Relazione` |
| R9.3 | Non origine di carichi automatici ("Una registrazione annullata non può generare carichi"); i carichi derivati annullati non contano nel residuo | `_ins_CaricoAuto` |
| R9.4 | Annullamento non operativo: la registrazione resta pienamente valida anche per nuove associazioni | vista (`IsAnnullata = 0`) |

### R10 - EoW e Magazzino
| # | Regola |
|---|---|
| R10.1 | Il registro prevale: la decisione operativa considera solo le relazioni del registro, mai quote EoW o magazzino |
| R10.2 | Quote EoW di una registrazione M con tetto = quantita' operativa (`_ins/_upd/_esegui`) |
| R10.3 | Controlli EoW/Magazzino sulle registrazioni solo se i moduli sono attivi sul dominio |
| R10.4 | **Aperto (tranche 3 Magazzino)**: una M annullata/ridotta non toglie ancora le quote EoW gia' assegnate ne' protegge il gia' scaricato. Nei test: comportamento atteso "non gestito" |

---

## B. Matrice di test

**Dati di partenza** (stesso registro, stesso EER/stato fisico, UM kg). In dev l'invio si puo' simulare valorizzando
`RentriIdentificativo`/`RentriData`, oppure usare l'invio reale verso la sandbox.

| Reg. | Tipo | Quantita' | Relazioni | Stato |
|---|---|---|---|---|
| C1 | Carico | 100 | consumato da S1 (60) | inviato |
| S1 | Scarico | 60 | preleva 60 da C1 | inviato |
| C2 | Carico | 50 | nessuna | inviato |
| S2 | Scarico I (trattamento interno) | 30 | preleva 30 da C2; da S2 derivano M1 | inviato |
| M1 | Carico M (materiale, carico auto da S2) | 20 | derivato da S2; quote EoW 20 su un lotto | inviato |
| C3 | Carico | 10 | nessuna | NON inviato |
| C4 | Carico | 10 | nessuna | inviato |

Giacenza iniziale attesa: C1 residuo 40, C2 residuo 20, C3 10, C4 10 -> **80 kg** per l'EER (piu' 20 kg materiale M1).

Colonne "Atteso": **Op.** = effetto su giacenze/residui/relazioni/limiti/EoW; **RENTRI** = registro, stampa, payload;
**UI** = modali, messaggi, icone.

### Correzione
| ID | Caso | Azione | Atteso Op. | Atteso RENTRI | Atteso UI | Esito |
|---|---|---|---|---|---|---|
| T01 | Carico consumato, quantita' sopra il prelevato | Correzione C2 50 -> 45 (prelevato 30) | Operativa: residuo C2 15, giacenza 75 | Stampa: C2 50 + rettifica 45 | Nessuna modale; icona matita blu sulla rettifica | |
| T02 | Carico consumato, quantita' sotto il prelevato | Correzione C1 100 -> 50 (prelevato 60) | Non operativa: C1 resta 100, giacenza invariata | Rettifica 50 trasmessa | Modale "Rettifica RENTRI" | |
| T03 | Carico consumato, quantita' in aumento | Correzione C1 100 -> 120 | Operativa: residuo C1 60 | Rettifica 120 | Nessuna modale | |
| T04 | Carico con relazioni, cambio EER | Correzione C1 con EER diverso | Non operativa: tutti i valori restano (anche la quantita' se cambiata insieme) | Rettifica con nuovo EER | Modale | |
| T05 | Carico senza relazioni, cambio EER | Correzione C4 con EER diverso | Operativa: giacenza si sposta sul nuovo EER | Rettifica con nuovo EER | Nessuna modale | |
| T06 | Scarico con carichi, quantita' | Correzione S1 60 -> 50 | Non operativa (lato padre, quantita' distribuita) | Rettifica 50 | Modale | |
| T07 | Seconda correzione | Dopo T03 inviata, nuova correzione di C1 | Precompilata con 120 (amministrativo); operativo di partenza = 120 | - | - | |
| T08 | Seconda correzione dopo una non operativa | Dopo T02 inviata, nuova correzione di C1 | Precompilata con 50 (amministrativo); operativo di partenza = 100 | - | - | |
| T09 | Ricalcolo prima dell'invio | Correzione confermata non inviata, poi modificata da operativa a non operativa e viceversa | La decisione segue l'ultimo salvataggio | - | Modale solo quando non operativa | |
| T10 | Correzione in bozza | Correzione creata e non salvata (Lock 2) | Nessun effetto operativo | - | - | |

### Annullamento
| ID | Caso | Azione | Atteso Op. | Atteso RENTRI | Atteso UI | Esito |
|---|---|---|---|---|---|---|
| T11 | Nota mancante | Salva annullamento senza nota | - | - | "Indicare il motivo dell'annullamento" | |
| T12 | Carico libero | Annullamento C4 | Operativo: esce dalla giacenza e dai candidati | Annullamento trasmesso con annotazioni | Nessuna modale; icona ban rossa | |
| T13 | Carico consumato | Annullamento C1 | Non operativo: C1 resta 100, residuo 40 | Annullamento trasmesso | Modale "Annullamento RENTRI" | |
| T14 | Scarico normale | Annullamento S1 | Operativo: C1 torna residuo 100, giacenza +60; relazione S1->C1 visibile ma non consuma | Stampa invariata per S1 | Nessuna modale | |
| T15 | Scarico I con derivati | Annullamento S2 | Non operativo: S2 continua a valere, M1 invariato | Annullamento trasmesso | Modale | |
| T16 | Carico M | Annullamento M1 | Operativo: M1 esce dalla giacenza materiale; quote EoW NON rimosse (R10.4) | Annullamento trasmesso | Nessuna modale | |
| T17 | Associazione dopo annullamento operativo | Dopo T12/T14, associare la registrazione annullata a un nuovo scarico/carico | - | - | Esclusa dai candidati; forzando: "Una registrazione annullata non può essere associata" | |
| T18 | Associazione dopo annullamento non operativo | Dopo T13, nuovo scarico che preleva dal residuo di C1 | C1 candidato con residuo 40 | - | Ammesso | |
| T19 | Carico auto da scarico annullato | Dopo T14 generare un carico automatico da S1 (serve un modello con carico auto) | - | - | "Una registrazione annullata non può generare carichi" | |

### Cancellazione della rettifica non inviata
| ID | Caso | Azione | Atteso Op. | Atteso UI | Esito |
|---|---|---|---|---|---|
| T20 | Correzione operativa, nessun uso successivo | Cancella la correzione di T01 | C2 torna a 50 | Modale "Cancella rettifica", nessun popup "Annulla cancellazione" | |
| T21 | Correzione usata dalle relazioni | Dopo T03 (C1 120) nuovo scarico che preleva 50 da C1 (totale 110), poi cancella la correzione | Bloccata: con 100 la giacenza andrebbe sotto zero | "La registrazione rettificata è stata associata ad altre con i valori corretti..." | |
| T22 | Annullamento di scarico, carichi riusati | Dopo T14 un nuovo scarico preleva i 100 di C1, poi cancella l'annullamento di S1 | Bloccata | "I carichi dello scarico annullato sono stati scaricati da altre registrazioni..." | |
| T23 | Rettifica non operativa | Cancella la correzione di T02 | Sempre ammessa, nulla cambia | Modale | |
| T24 | Cancellazione multipla | Seleziona una rettifica non inviata insieme ad altre | Bloccata | "...selezionarla da sola per cancellarla" | |

### Blocchi
| ID | Caso | Azione | Atteso | Esito |
|---|---|---|---|---|
| T25 | Rettifica di non inviata | Rettifica su C3 | Voce menu non disponibile / "Solo una registrazione già inviata al RENTRI può essere rettificata" | |
| T26 | Rettifica di rettifica | Rettifica sulla rettifica di T01 (inviata) | "Una registrazione di rettifica non può essere a sua volta rettificata o annullata" | |
| T27 | Due pendenti | Seconda rettifica/annullamento con la prima non inviata (anche in bozza) | "Esiste già una rettifica o un annullamento non ancora inviato al RENTRI..." | |
| T28 | Dopo annullamento inviato | Correzione o annullamento su originale gia' annullato | "La registrazione è già stata annullata e non può essere annullata o rettificata nuovamente" | |
| T29 | Modifica inviata | Salva C1 da Edit | "già stata inviata al RENTRI: non può più essere modificata" | |
| T30 | Cancellazione inviata | Cancella C1 | "già stata inviata al RENTRI: non può più essere cancellata" | |
| T31 | Rinumerazione | Intervallo che include C1 | "L'intervallo contiene registrazioni già inviate al RENTRI..." | |
| T32 | Associazione su inviata | Associare un carico a S1 (padre inviato) | "già stata inviata al RENTRI: non può essere associata..." | |
| T33 | Relazioni sulla rettifica | Forzare associazione con una rettifica | "Una registrazione di rettifica o annullamento non può avere relazioni di carico/scarico" | |
| T34 | Quote EoW sulla rettifica | Quota/allocazione EoW sulla rettifica di M1 | "Una registrazione di rettifica o annullamento non può ricevere quote EoW" | |

### Controlli trasversali (dopo ogni caso)
- Giacenze (Rifiuti/Giacenze) e dettaglio carichi coerenti con la colonna "Atteso Op.".
- La registrazione di rettifica non compare mai in giacenza, nei candidati, nei limiti ne' nelle quote EoW.
- Stampa registro: l'originale mostra sempre i valori inviati; la rettifica mostra i propri.
- Avvisi limiti: conteggiano i valori operativi.
- Quote EoW di M1: mai oltre la quantita' operativa per nuove quote (R10.2); le quote gia' presenti restano (R10.4).
