-- Migrazione da Ecomatico 3.1: configurazione. Da eseguire dopo tools/migrazione_struttura.sql.
-- 1) Sinonimi dbo.syn31Xxx verso le tabelle del DB 3.1: le SP della migrazione leggono la 3.1 solo attraverso questi
--    nomi, cosi' un DB di origine con un altro nome si gestisce cambiando @Database qui sotto e rieseguendo lo script
--    (i sinonimi esistenti vengono ricreati). Nomi senza accenti: syn31UnitaMisura -> [tblUnitàMisura];
-- 2) codici delle tabelle di lookup 3.1 -> 4.0 (tblMigrazioniCodici, Versione = '31'). Un codice assente o con
--    CodiceDestinazione NULL non e' migrabile: il record che lo usa viene scartato e segnalato nel log;
-- 3) causali dei movimenti 3.1 -> operazioni 4.0 (tblMigrazioniCausali, Versione = '31'). Scelte concordate: CCM -> F,
--    SRG -> R.
-- Script idempotente: rieseguibile senza effetti su un DB gia' aggiornato.
SET NOCOUNT ON;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
DECLARE @causali TABLE (CausaleOrigine VARCHAR(20) NOT NULL PRIMARY KEY, IdOperazione CHAR(1) NOT NULL);
INSERT INTO @causali (CausaleOrigine, IdOperazione)
VALUES
	('CCM', 'F'),
	('CFL', 'F'),
	('CFM', 'F'),
	('CFP', 'F'),
	('CGI', 'C'),
	('CMC', 'K'),
	('CPL', 'C'),
	('CPT', 'Z'),
	('CRC', 'M'),
	('CSF', 'T'),
	('CSM', 'Q'),
	('CST', 'T'),
	('CSX', 'T'),
	('CTT', 'Z'),
	('SFC', 'R'),
	('SIS', 'N'),
	('SRG', 'R'),
	('STP', 'S'),
	('STT', 'S'),
	('TRD', 'I');

-- Si tolgono le causali non piu' previste e si allinea l'operazione di quelle esistenti
DELETE c
FROM dbo.tblMigrazioniCausali c
WHERE
	c.Versione = '31'
	AND NOT EXISTS (SELECT 1 FROM @causali s WHERE s.CausaleOrigine = c.CausaleOrigine);

UPDATE c
SET c.IdOperazione = s.IdOperazione
FROM
	dbo.tblMigrazioniCausali c
	INNER JOIN @causali s ON c.CausaleOrigine = s.CausaleOrigine
WHERE
	c.Versione = '31'
	AND c.IdOperazione <> s.IdOperazione;

INSERT INTO dbo.tblMigrazioniCausali (Versione, CausaleOrigine, IdOperazione)
SELECT '31', s.CausaleOrigine, s.IdOperazione
FROM @causali s
WHERE NOT EXISTS (SELECT 1
	FROM dbo.tblMigrazioniCausali c
	WHERE
		c.Versione = '31'
		AND c.CausaleOrigine = s.CausaleOrigine);
GO
DECLARE @Database SYSNAME = N'3_1_ecomatico';

DECLARE @sinonimi TABLE (Nome SYSNAME NOT NULL, Tabella SYSNAME NOT NULL);
INSERT INTO @sinonimi (Nome, Tabella)
VALUES
	(N'syn31ID', N'tblID'),
	(N'syn31Domini', N'tblDomini'),
	(N'syn31SediInterne', N'tblSediInterne'),
	(N'syn31Sedi', N'tblSedi'),
	(N'syn31SediEsterne', N'tblSediEsterne'),
	(N'syn31SediIndirizzi', N'tblSediIndirizzi'),
	(N'syn31SediDatiEstesi', N'tblSediDatiEstesi'),
	(N'syn31Indirizzi', N'tblIndirizzi'),
	(N'syn31Comuni', N'tblComuni'),
	(N'syn31MappingComuniSardegna', N'tblMappingComuniSardegna'),
	(N'syn31RifiutiRegistri', N'tblRifiutiRegistri'),
	(N'syn31RifiutiMovimenti', N'tblRifiutiMovimenti'),
	(N'syn31RifiutiMovimentiCausali', N'tblRifiutiMovimentiCausali'),
	(N'syn31RifiutiMovimentiClassiPericolo', N'tblRifiutiMovimentiClassiPericolo'),
	(N'syn31RifiutiMovimentiSedi', N'tblRifiutiMovimentiSedi'),
	(N'syn31RifiutiRegistrazioni', N'tblRifiutiRegistrazioni'),
	(N'syn31RifiutiRegistrazioniRelazioni', N'tblRifiutiRegistrazioniRelazioni'),
	(N'syn31RifiutiRegistrazioniQuantitaDestino', N'tblRifiutiRegistrazioniQuantitàDestino'),
	(N'syn31RifiutiSchede', N'tblRifiutiSchede'),
	(N'syn31RentriRegistrazioniRettifiche', N'tblRentriRegistrazioniRettifiche'),
	(N'syn31RifiutiAutorizzazioni', N'tblRifiutiAutorizzazioni'),
	(N'syn31RifiutiAutorizzazioniCER', N'tblRifiutiAutorizzazioniCER'),
	(N'syn31RifiutiAutorizzazioniConducenti', N'tblRifiutiAutorizzazioniConducenti'),
	(N'syn31RifiutiAutorizzazioniDestinazioni', N'tblRifiutiAutorizzazioniDestinazioni'),
	(N'syn31RifiutiAutorizzazioniTarghe', N'tblRifiutiAutorizzazioniTarghe'),
	(N'syn31RifiutiAutorizzazioniTargheCEREsclusi', N'tblRifiutiAutorizzazioniTargheCEREsclusi'),
	(N'syn31Utenti', N'tblUtenti'),
	(N'syn31UtentiSedi', N'tblUtentiSedi'),
	(N'syn31UtentiPasswordChange', N'tblUtentiPasswordChange'),
	(N'syn31RentriCertificati', N'tblRentriCertificati'),
	(N'syn31RentriCredenziali', N'tblRentriCredenziali'),
	(N'syn31RentriSedi', N'tblRentriSedi'),
	(N'syn31RentriRegistri', N'tblRentriRegistri');

DECLARE @nome SYSNAME;
DECLARE @tabella SYSNAME;
DECLARE @sql NVARCHAR(1000);

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
	SELECT Nome, Tabella
	FROM @sinonimi;

OPEN c;
FETCH c INTO @nome, @tabella;

WHILE @@FETCH_STATUS = 0
BEGIN
	IF OBJECT_ID(N'dbo.' + @nome, 'SN') IS NOT NULL
	BEGIN
		SET @sql = N'DROP SYNONYM dbo.' + QUOTENAME(@nome) + N';';
		EXEC sys.sp_executesql @sql;
	END

	SET @sql = N'CREATE SYNONYM dbo.' + QUOTENAME(@nome) + N' FOR ' + QUOTENAME(@Database) + N'.dbo.' + QUOTENAME(@tabella) + N';';
	EXEC sys.sp_executesql @sql;

	FETCH c INTO @nome, @tabella;
END

CLOSE c;
DEALLOCATE c;
GO
-- Codici 3.1 -> 4.0
DECLARE @codici TABLE (Tabella VARCHAR(50) NOT NULL, CodiceOrigine VARCHAR(20) NOT NULL, CodiceDestinazione VARCHAR(20) NULL);
INSERT INTO @codici (Tabella, CodiceOrigine, CodiceDestinazione)
VALUES
	-- Stati fisici: tblRifiutiStatiFisici.RentriCodice (3.1) = tblRifiutiStatiFisici.Codice (4.0)
	('tblRifiutiStatiFisici', '01', 'P'),
	('tblRifiutiStatiFisici', '02', 'S'),
	('tblRifiutiStatiFisici', '03', 'F'),
	('tblRifiutiStatiFisici', '04', 'L'),
	-- Unita' di misura: stessi Id
	('tblUnitaMisura', 'GG', 'GG'),
	('tblUnitaMisura', 'HR', 'HR'),
	('tblUnitaMisura', 'KG', 'KG'),
	('tblUnitaMisura', 'LT', 'LT'),
	('tblUnitaMisura', 'MC', 'MC'),
	('tblUnitaMisura', 'MQ', 'MQ'),
	('tblUnitaMisura', 'NR', 'NR'),
	('tblUnitaMisura', 'TN', 'TN'),
	-- Destinazioni (3.1) -> attivita' di recupero/smaltimento (4.0): Dnn -> nn, Rnn -> 50 + nn
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D01', '01'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D02', '02'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D03', '03'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D04', '04'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D05', '05'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D06', '06'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D07', '07'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D08', '08'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D09', '09'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D10', '10'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D11', '11'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D12', '12'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D13', '13'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D14', '14'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'D15', '15'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'R01', '51'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'R02', '52'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'R03', '53'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'R04', '54'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'R05', '55'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'R06', '56'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'R07', '57'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'R08', '58'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'R09', '59'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'R10', '60'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'R11', '61'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'R12', '62'),
	('tblRifiutiAttivitaRecuperoSmaltimento', 'R13', '63'),
	-- Materiali secondari (3.1, 3 caratteri) -> materiali (4.0, 2 caratteri)
	('tblRifiutiMateriali', 'ACM', 'AM'),
	('tblRifiutiMateriali', 'ACV', 'AV'),
	('tblRifiutiMateriali', 'AGR', 'AG'),
	('tblRifiutiMateriali', 'ASS', 'AS'),
	('tblRifiutiMateriali', 'ATM', 'AA'),
	('tblRifiutiMateriali', 'ATR', 'AL'),
	('tblRifiutiMateriali', 'CCT', 'CC'),
	('tblRifiutiMateriali', 'CSS', 'CS'),
	('tblRifiutiMateriali', 'CUO', 'CU'),
	('tblRifiutiMateriali', 'DGS', 'DG'),
	('tblRifiutiMateriali', 'FNG', 'CF'),
	('tblRifiutiMateriali', 'FTZ', 'AF'),
	('tblRifiutiMateriali', 'GCB', 'GC'),
	('tblRifiutiMateriali', 'GMA', 'GM'),
	('tblRifiutiMateriali', 'GMV', 'GV'),
	('tblRifiutiMateriali', 'LSG', 'LS'),
	('tblRifiutiMateriali', 'PLT', 'PL'),
	('tblRifiutiMateriali', 'RAL', 'RA'),
	('tblRifiutiMateriali', 'RCM', 'MC'),
	('tblRifiutiMateriali', 'RFA', 'RF'),
	('tblRifiutiMateriali', 'RRM', 'RR'),
	('tblRifiutiMateriali', 'RVT', 'RV'),
	('tblRifiutiMateriali', 'TSL', 'TE'),
	-- RAEE: tblRaee.Codice (3.1) = tblRifiutiRaee.Codice (4.0)
	('tblRifiutiRaee', '1', 'A'),
	('tblRifiutiRaee', '2', 'B'),
	('tblRifiutiRaee', '3', 'C'),
	('tblRifiutiRaee', '4', 'D'),
	('tblRifiutiRaee', '5', 'E'),
	('tblRifiutiRaee', '6', 'F'),
	('tblRifiutiRaee', '7', 'P'),
	-- Esiti e causali di respingimento (per Codice)
	('tblRifiutiRegistrazioniEsiti', 'A', 'A'),
	('tblRifiutiRegistrazioniEsiti', 'P', 'P'),
	('tblRifiutiRegistrazioniEsiti', 'R', 'R'),
	('tblRifiutiRegistrazioniEsitiCausaliRespingimento', 'NC', 'N'),
	('tblRifiutiRegistrazioniEsitiCausaliRespingimento', 'IR', 'I'),
	('tblRifiutiRegistrazioniEsitiCausaliRespingimento', 'A', 'A'),
	-- Trasporto transfrontaliero: TransfrontalieroTipo (3.1) = Codice (4.0)
	('tblRifiutiTrasportiTransfrontalieriTipi', 'DA', 'D'),
	('tblRifiutiTrasportiTransfrontalieriTipi', 'DM', 'M'),
	-- Tipo di trasporto (gomma, treno, nave)
	('tblRifiutiMovimentiTrasportiTipi', 'G', 'G'),
	('tblRifiutiMovimentiTrasportiTipi', 'T', 'T'),
	('tblRifiutiMovimentiTrasportiTipi', 'N', 'N'),
	-- Tipi di registro: il modello C (associazioni di categoria) non esiste in 4.0
	('tblRifiutiRegistriTipi', 'MDA', 'A'),
	('tblRifiutiRegistriTipi', 'MDB', 'B'),
	('tblRifiutiRegistriTipi', 'MDC', NULL),
	-- Provenienza (speciale/urbano) e attivita' di provenienza: stessi codici
	('tblRifiutiProvenienze', 'S', 'S'),
	('tblRifiutiProvenienze', 'U', 'U'),
	('tblRifiutiAttivitaProvenienze', 'A', 'A'),
	('tblRifiutiAttivitaProvenienze', 'M', 'M'),
	('tblRifiutiAttivitaProvenienze', 'S', 'S'),
	('tblRifiutiAttivitaProvenienze', 'T', 'T'),
	-- Classi di pericolo: stessi Id (HP1 = HP01)
	('tblRifiutiClassiPericolo', '01', '01'),
	('tblRifiutiClassiPericolo', '02', '02'),
	('tblRifiutiClassiPericolo', '03', '03'),
	('tblRifiutiClassiPericolo', '04', '04'),
	('tblRifiutiClassiPericolo', '05', '05'),
	('tblRifiutiClassiPericolo', '06', '06'),
	('tblRifiutiClassiPericolo', '07', '07'),
	('tblRifiutiClassiPericolo', '08', '08'),
	('tblRifiutiClassiPericolo', '09', '09'),
	('tblRifiutiClassiPericolo', '10', '10'),
	('tblRifiutiClassiPericolo', '11', '11'),
	('tblRifiutiClassiPericolo', '12', '12'),
	('tblRifiutiClassiPericolo', '13', '13'),
	('tblRifiutiClassiPericolo', '14', '14'),
	('tblRifiutiClassiPericolo', '15', '15'),
	-- Autorizzazioni: categoria (3.1) -> ruolo (4.0); tipo per Codice (stessi Id A-F); NoAlbo -> tipo di numero
	('tblRifiutiRuoli', 'P', 'P'),
	('tblRifiutiRuoli', 'T', 'T'),
	('tblRifiutiRuoli', 'D', 'D'),
	('tblRifiutiRuoli', 'I', 'I'),
	('tblRifiutiAutorizzazioniTipi', 'A', 'A'),
	('tblRifiutiAutorizzazioniTipi', 'B', 'B'),
	('tblRifiutiAutorizzazioniTipi', 'C', 'C'),
	('tblRifiutiAutorizzazioniTipi', 'D', 'D'),
	('tblRifiutiAutorizzazioniTipi', 'E', 'E'),
	('tblRifiutiAutorizzazioniTipi', 'F', 'F'),
	('tblRifiutiAutorizzazioniNumeriTipi', '0', 'A'),
	('tblRifiutiAutorizzazioniNumeriTipi', '1', 'C'),
	-- Tipi di sede: stessi codici
	('tblSediTipi', 'A', 'A'),
	('tblSediTipi', 'C', 'C'),
	('tblSediTipi', 'G', 'G'),
	('tblSediTipi', 'L', 'L'),
	('tblSediTipi', 'M', 'M'),
	('tblSediTipi', 'P', 'P');

MERGE dbo.tblMigrazioniCodici AS t
USING @codici AS s ON t.Versione = '31' AND t.Tabella = s.Tabella AND t.CodiceOrigine = s.CodiceOrigine
WHEN MATCHED AND ISNULL(t.CodiceDestinazione, '') <> ISNULL(s.CodiceDestinazione, '') THEN
	UPDATE SET CodiceDestinazione = s.CodiceDestinazione
WHEN NOT MATCHED BY TARGET THEN
	INSERT (Versione, Tabella, CodiceOrigine, CodiceDestinazione)
	VALUES ('31', s.Tabella, s.CodiceOrigine, s.CodiceDestinazione);
GO
