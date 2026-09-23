/*
	Deploy produzione - 2026-09-23 - Indici per i moduli introdotti dopo l'audit del 2026-08-14

	Contesto: l'audit completo indici (indici-4_0_ecomatico.md) era stato chiuso il 2026-08-14
	quando l'unico ambiente esistente era di sviluppo. Da allora sono stati introdotti in
	produzione 5 moduli nuovi (EoW, Limiti rifiuti, RENTRI Certificati/Credenziali, MUD, Carichi
	automatici da Modello - 25 tabelle nuove, quasi tutte con la sola PK clustered) più nuovi
	campi RENTRI/Avvisi su 4 tabelle hot-path già "chiuse" nell'audit originale. Analisi statica
	del carico di lavoro (stesso metodo del documento originale: lettura dei JOIN/WHERE/ORDER BY
	reali nelle SP, non DMV runtime) per individuare i gap.

	Oggetti inclusi:

	PARTE 1 - tabelle nuove, rischio basso (nessun impatto su scritture esistenti):
	1. tblRifiutiLimiti: IX_RifiutiLimiti_IdSede_Lock (IdSede, Lock) INCLUDE(IdRegistro) -
	   zero indici secondari su una tabella che alimenta ufnRifiutiLimiti_get_Verifica_List,
	   invocata da uspAvvisi_get_Count/_Dashboard_List/_Limiti_List a ogni refresh badge/dashboard.
	2. tblEoWLottiRifiutiRegistrazioni: IX_EoWLottiRifiutiRegistrazioni_IdLotto (IdLotto)
	   INCLUDE(Quantita) - IdLotto e' la 2a colonna della PK (IdRegistrazione, IdLotto), oggi
	   ogni filtro su IdLotto da solo e' uno scan completo (4 SP + subquery SUM correlata in
	   uspEoWAllocazioni_esegui).
	3. tblEoWLottiAllocazioni: IX_EoWLottiAllocazioni_IdAllocazione (IdAllocazione)
	   INCLUDE(IdLotto, Valore) - stesso problema, IdAllocazione e' la 2a colonna della PK
	   (IdLotto, IdAllocazione), hot path in uspEoWAllocazioni_esegui.
	4. tblEoWAllocazioni: IX_EoWAllocazioni_IdSede_Lock (IdSede, Lock) - snodo di scoping del
	   modulo Allocazioni, zero indici secondari.
	5. tblEoWLotti: IX_EoWLotti_IdSede_Lock (IdSede, Lock) INCLUDE(Nome) - titolarita' standard +
	   copre l'ORDER BY Nome di uspEoWLotti_get_List.
	6. tblEoWMagazzini: IX_EoWMagazzini_IdSede_Lock (IdSede, Lock) - stesso pattern titolarita'.
	7. tblRentriCredenziali: IX_RentriCredenziali_IdDominio_Lock (IdDominio, Lock) - filtri
	   ricorrenti IdDominio/Lock, PK solo su Id senza copertura.
	8. tblRentriCertificati: IX_RentriCertificati_IdDominio_Lock (IdDominio, Lock)
	   INCLUDE(DataScadenza) - stesso scoping + copre OUTER APPLY MIN(DataScadenza).
	9. tblRifiutiModelliRegistrazioniAuto: IX_RifiutiModelliRegistrazioniAuto_IdModello
	   (IdModello) INCLUDE(Percentuale) - righe multiple per IdModello (split percentuali),
	   PK Id standalone non copre il filtro per modello.

	PARTE 2 - tabelle esistenti hot-path, toccate da RENTRI/Avvisi (piu' cautela, modifica di
	indici gia' in uso, nessun impatto sulle colonne chiave esistenti):
	10. tblRifiutiMovimenti: IX_RifiutiMovimenti_IdRegistro invariato nella chiave (IdRegistro),
	    INCLUDE esteso con le 6 colonne RentriFormularioStato/DataCopia/DataPresaVisione/
	    DataTrasmissione/DataConservazione/InviiConservazione - il seek resta sempre su
	    IdRegistro, queste colonne sono lette/filtrate come residuo in 5+ SP RENTRI senza mai
	    essere in INCLUDE (Key Lookup per riga). Scartato un indice filtrato standalone su
	    RentriFormularioStato: nessun pattern di scan globale trovato nel codice.
	11. tblRifiutiRegistrazioni: IX_RifiutiRegistrazioni_IdMovimento_Data_Numero_Lock invariato
	    nella chiave e nel filtro (Lock<2), INCLUDE esteso con RentriIdentificativo/RentriData -
	    stesso schema, seek sempre via IdMovimento. ConservazioneSostitutiva escluso: mai un
	    predicato di ricerca, solo lettura/scrittura per PK.
	12. tblRifiutiAutorizzazioni: nuovo indice IX_RifiutiAutorizzazioni_IdSede_DataFine_Lock
	    (IdSede, DataFine) INCLUDE(Numero, IdRuolo) WHERE Nessuna=0 AND Disabilitata=0 AND
	    Lock=0 - pattern nuovo e distinto dalla titolarita' classica (IdSede+IdRuolo, gia'
	    coperta da IX_RifiutiAutorizzazioni_IdSede_IdRuolo_Lock, non toccato): 3 SP Avvisi
	    filtrano IdSede + booleani + range DataFine con ORDER BY DataFine paginato, mai per
	    IdRuolo.
	13. tblCalendari: IX_Calendari_IdSede sostituito da IX_Calendari_IdSede_IdModulo_Lock
	    (IdSede, IdModulo) WHERE Lock<2 - stesso pattern gia' risolto due volte nello stesso DB
	    (IX_Etichette_IdSede_IdModulo_Lock, IX_Tipi_IdSede_IdModulo_Lock); Avvisi aggiunge
	    frequenza (polling) a un gap preesistente. Verificato: nessuna SP referenzia l'indice
	    con hint esplicito WITH (INDEX(...)).

	Nessuna azione (gia' coperto da PK/FK esistente o cardinalita' irrilevante):
	tblRifiutiLimitiEer/Etichette/Operazioni, tblRentriRegistri, tblSediDatiEstesi,
	tblRifiutiMudRegistri, tblRifiutiModelliRegistrazioniAutoEtichette, tblRentriCredenzialiSedi,
	tblEoWAllocazioniTipi, tblRifiutiAttivitaProvenienze, tblRentriAccreditamenti, tblAteco,
	tblRifiutiMud.

	Finding collaterale segnalato ma fuori perimetro di questo script (registrato in
	indici-4_0_ecomatico.md come voce aperta): uspRifiutiAutorizzazioni_get_MatchImportazione
	filtra tblSedi.CodiceFiscale senza indice dedicato - da valutare a parte.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-23_indici_moduli_nuovi.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)

	Nota operativa: SET QUOTED_IDENTIFIER ON e' richiesto esplicitamente perche' gli indici
	dei punti 11/12/13 sono filtrati (WHERE ...) - la sessione sqlcmd di default ha
	QUOTED_IDENTIFIER OFF, altrimenti Msg 1934.

	Idempotente: rieseguibile senza errori (guard IF NOT EXISTS/IF EXISTS su ogni oggetto;
	i CREATE INDEX ... WITH (DROP_EXISTING = ON) dei punti 10/11 sono idempotenti per natura).
*/

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--------------------------------------------------------------------------------
-- PARTE 1 - tabelle nuove, rischio basso
--------------------------------------------------------------------------------

-- 1. tblRifiutiLimiti
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RifiutiLimiti_IdSede_Lock' AND object_id = OBJECT_ID('dbo.tblRifiutiLimiti'))
BEGIN
	CREATE NONCLUSTERED INDEX [IX_RifiutiLimiti_IdSede_Lock] ON [dbo].[tblRifiutiLimiti]
	(
		[IdSede] ASC,
		[Lock] ASC
	)
	INCLUDE([IdRegistro])
	WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
END
GO

-- 2. tblEoWLottiRifiutiRegistrazioni
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_EoWLottiRifiutiRegistrazioni_IdLotto' AND object_id = OBJECT_ID('dbo.tblEoWLottiRifiutiRegistrazioni'))
BEGIN
	CREATE NONCLUSTERED INDEX [IX_EoWLottiRifiutiRegistrazioni_IdLotto] ON [dbo].[tblEoWLottiRifiutiRegistrazioni]
	(
		[IdLotto] ASC
	)
	INCLUDE([Quantita])
	WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
END
GO

-- 3. tblEoWLottiAllocazioni
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_EoWLottiAllocazioni_IdAllocazione' AND object_id = OBJECT_ID('dbo.tblEoWLottiAllocazioni'))
BEGIN
	CREATE NONCLUSTERED INDEX [IX_EoWLottiAllocazioni_IdAllocazione] ON [dbo].[tblEoWLottiAllocazioni]
	(
		[IdAllocazione] ASC
	)
	INCLUDE([IdLotto], [Valore])
	WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
END
GO

-- 4. tblEoWAllocazioni
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_EoWAllocazioni_IdSede_Lock' AND object_id = OBJECT_ID('dbo.tblEoWAllocazioni'))
BEGIN
	CREATE NONCLUSTERED INDEX [IX_EoWAllocazioni_IdSede_Lock] ON [dbo].[tblEoWAllocazioni]
	(
		[IdSede] ASC,
		[Lock] ASC
	)
	WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
END
GO

-- 5. tblEoWLotti
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_EoWLotti_IdSede_Lock' AND object_id = OBJECT_ID('dbo.tblEoWLotti'))
BEGIN
	CREATE NONCLUSTERED INDEX [IX_EoWLotti_IdSede_Lock] ON [dbo].[tblEoWLotti]
	(
		[IdSede] ASC,
		[Lock] ASC
	)
	INCLUDE([Nome])
	WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
END
GO

-- 6. tblEoWMagazzini
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_EoWMagazzini_IdSede_Lock' AND object_id = OBJECT_ID('dbo.tblEoWMagazzini'))
BEGIN
	CREATE NONCLUSTERED INDEX [IX_EoWMagazzini_IdSede_Lock] ON [dbo].[tblEoWMagazzini]
	(
		[IdSede] ASC,
		[Lock] ASC
	)
	WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
END
GO

-- 7. tblRentriCredenziali
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RentriCredenziali_IdDominio_Lock' AND object_id = OBJECT_ID('dbo.tblRentriCredenziali'))
BEGIN
	CREATE NONCLUSTERED INDEX [IX_RentriCredenziali_IdDominio_Lock] ON [dbo].[tblRentriCredenziali]
	(
		[IdDominio] ASC,
		[Lock] ASC
	)
	WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
END
GO

-- 8. tblRentriCertificati
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RentriCertificati_IdDominio_Lock' AND object_id = OBJECT_ID('dbo.tblRentriCertificati'))
BEGIN
	CREATE NONCLUSTERED INDEX [IX_RentriCertificati_IdDominio_Lock] ON [dbo].[tblRentriCertificati]
	(
		[IdDominio] ASC,
		[Lock] ASC
	)
	INCLUDE([DataScadenza])
	WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
END
GO

-- 9. tblRifiutiModelliRegistrazioniAuto
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RifiutiModelliRegistrazioniAuto_IdModello' AND object_id = OBJECT_ID('dbo.tblRifiutiModelliRegistrazioniAuto'))
BEGIN
	CREATE NONCLUSTERED INDEX [IX_RifiutiModelliRegistrazioniAuto_IdModello] ON [dbo].[tblRifiutiModelliRegistrazioniAuto]
	(
		[IdModello] ASC
	)
	INCLUDE([Percentuale])
	WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
END
GO

--------------------------------------------------------------------------------
-- PARTE 2 - tabelle esistenti hot-path, toccate da RENTRI/Avvisi
--------------------------------------------------------------------------------

-- 10. tblRifiutiMovimenti: IX_RifiutiMovimenti_IdRegistro, INCLUDE esteso con le colonne RENTRI
--     (CREATE ... WITH DROP_EXISTING = ON, stesso nome/chiave: idempotente per natura)
CREATE NONCLUSTERED INDEX [IX_RifiutiMovimenti_IdRegistro] ON [dbo].[tblRifiutiMovimenti]
(
	[IdRegistro] ASC
)
INCLUDE(
	[IdOperazione], [IdEer], [IdStatoFisico], [IdUnitaMisura], [Quantita],
	[IdSedeDestinatario], [IdSedeIntermediario1], [FormularioNumero], [IdAttivita],
	[IdSedeProduttoreDetentore], [IdSedeTrasportatore1], [IdProvenienza],
	[RentriFormularioStato], [RentriFormularioDataCopia], [RentriFormularioDataPresaVisione],
	[RentriFormularioDataTrasmissione], [RentriFormularioDataConservazione],
	[RentriFormularioInviiConservazione]
)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = ON, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
GO

-- 11. tblRifiutiRegistrazioni: IX_RifiutiRegistrazioni_IdMovimento_Data_Numero_Lock, INCLUDE esteso
--     (stessa chiave e stesso filtro Lock<2 dell'indice esistente, idempotente per natura)
CREATE NONCLUSTERED INDEX [IX_RifiutiRegistrazioni_IdMovimento_Data_Numero_Lock] ON [dbo].[tblRifiutiRegistrazioni]
(
	[IdMovimento] ASC,
	[Data] ASC,
	[Numero] ASC
)
INCLUDE(
	[QuantitaVerificata], [DataFineTrasporto], [IdTrasportoTransfrontalieroTipo], [Note],
	[Operazione], [Etichette], [RentriIdentificativo], [RentriData]
)
WHERE ([Lock] < (2))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = ON, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
GO

-- 12. tblRifiutiAutorizzazioni: nuovo indice dedicato al pattern del modulo Avvisi
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RifiutiAutorizzazioni_IdSede_DataFine_Lock' AND object_id = OBJECT_ID('dbo.tblRifiutiAutorizzazioni'))
BEGIN
	CREATE NONCLUSTERED INDEX [IX_RifiutiAutorizzazioni_IdSede_DataFine_Lock] ON [dbo].[tblRifiutiAutorizzazioni]
	(
		[IdSede] ASC,
		[DataFine] ASC
	)
	INCLUDE([Numero], [IdRuolo])
	WHERE ([Nessuna] = (0) AND [Disabilitata] = (0) AND [Lock] = (0))
	WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
END
GO

-- 13. tblCalendari: rename IX_Calendari_IdSede -> IX_Calendari_IdSede_IdModulo_Lock (chiave estesa)
--     Rename = nome diverso, non si puo' usare DROP_EXISTING: drop esplicito + create separato.
--     Verificato: nessuna SP referenzia IX_Calendari_IdSede con hint WITH (INDEX(...)).
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Calendari_IdSede' AND object_id = OBJECT_ID('dbo.tblCalendari'))
BEGIN
	DROP INDEX [IX_Calendari_IdSede] ON [dbo].[tblCalendari];
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Calendari_IdSede_IdModulo_Lock' AND object_id = OBJECT_ID('dbo.tblCalendari'))
BEGIN
	CREATE NONCLUSTERED INDEX [IX_Calendari_IdSede_IdModulo_Lock] ON [dbo].[tblCalendari]
	(
		[IdSede] ASC,
		[IdModulo] ASC
	)
	WHERE ([Lock] < (2))
	WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
END
GO
