-- Fatturazione > Dati fiscali: dati dell'azienda che emette richiesti dal file XML della fattura elettronica
-- (regime fiscale, iscrizione REA, ritenuta d'acconto), con le tabelle dei codici, la pagina e la voce di menu.
-- Sono configurazione del modulo Fatturazione (funzione FTC, come conti, banche e casse e aliquote IVA): con il
-- modulo non attivo la voce non compare.
-- Codici presi dallo schema XSD della fattura elettronica (versione 1.2.2).
-- Script idempotente: rieseguibile senza effetti su un DB che ha già tabelle e registrazione.
SET NOCOUNT ON;
GO
-- Regimi fiscali (RegimeFiscaleType)
IF OBJECT_ID('dbo.tblFattureRegimiFiscali') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureRegimiFiscali (
		Id CHAR(4) NOT NULL,
		Nome VARCHAR(200) NULL,
		CONSTRAINT PK_tblFattureRegimiFiscali PRIMARY KEY CLUSTERED (Id)
	);
END
GO
MERGE dbo.tblFattureRegimiFiscali AS t
USING (VALUES
	('RF01', 'Regime ordinario'),
	('RF02', 'Regime dei contribuenti minimi (art. 1, c. 96-117, L. 244/2007)'),
	('RF04', 'Agricoltura e attività connesse e pesca (artt. 34 e 34-bis, D.P.R. 633/1972)'),
	('RF05', 'Vendita sali e tabacchi (art. 74, c. 1, D.P.R. 633/1972)'),
	('RF06', 'Commercio dei fiammiferi (art. 74, c. 1, D.P.R. 633/1972)'),
	('RF07', 'Editoria (art. 74, c. 1, D.P.R. 633/1972)'),
	('RF08', 'Gestione di servizi di telefonia pubblica (art. 74, c. 1, D.P.R. 633/1972)'),
	('RF09', 'Rivendita di documenti di trasporto pubblico e di sosta (art. 74, c. 1, D.P.R. 633/1972)'),
	('RF10', 'Intrattenimenti, giochi e altre attività di cui alla tariffa allegata al D.P.R. 640/72'),
	('RF11', 'Agenzie di viaggi e turismo (art. 74-ter, D.P.R. 633/1972)'),
	('RF12', 'Agriturismo (art. 5, c. 2, L. 413/1991)'),
	('RF13', 'Vendite a domicilio (art. 25-bis, c. 6, D.P.R. 600/1973)'),
	('RF14', 'Rivendita di beni usati, di oggetti d''arte, d''antiquariato o da collezione (art. 36, D.L. 41/1995)'),
	('RF15', 'Agenzie di vendite all''asta di oggetti d''arte, antiquariato o da collezione (art. 40-bis, D.L. 41/1995)'),
	('RF16', 'IVA per cassa P.A. (art. 6, c. 5, D.P.R. 633/1972)'),
	('RF17', 'IVA per cassa (art. 32-bis, D.L. 83/2012)'),
	('RF18', 'Altro'),
	('RF19', 'Regime forfettario')
) AS s (Id, Nome) ON t.Id = s.Id
WHEN MATCHED AND ISNULL(t.Nome, '') <> s.Nome THEN UPDATE SET Nome = s.Nome
WHEN NOT MATCHED THEN INSERT (Id, Nome) VALUES (s.Id, s.Nome);
GO
-- Tipi di ritenuta (TipoRitenutaType)
IF OBJECT_ID('dbo.tblFattureRitenuteTipi') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureRitenuteTipi (
		Id CHAR(4) NOT NULL,
		Nome VARCHAR(100) NULL,
		CONSTRAINT PK_tblFattureRitenuteTipi PRIMARY KEY CLUSTERED (Id)
	);
END
GO
MERGE dbo.tblFattureRitenuteTipi AS t
USING (VALUES
	('RT01', 'Ritenuta di acconto persone fisiche'),
	('RT02', 'Ritenuta di acconto persone giuridiche'),
	('RT03', 'Contributo INPS'),
	('RT04', 'Contributo ENASARCO'),
	('RT05', 'Contributo ENPAM'),
	('RT06', 'Altro contributo previdenziale')
) AS s (Id, Nome) ON t.Id = s.Id
WHEN MATCHED AND ISNULL(t.Nome, '') <> s.Nome THEN UPDATE SET Nome = s.Nome
WHEN NOT MATCHED THEN INSERT (Id, Nome) VALUES (s.Id, s.Nome);
GO
-- Causali del pagamento della ritenuta (CausalePagamentoType): i codici sono quelli dello schema XSD (senza Z,
-- non più valido dal 2021); le descrizioni sono quelle del modello CU, in forma breve
IF OBJECT_ID('dbo.tblFattureRitenuteCausali') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureRitenuteCausali (
		Id VARCHAR(2) NOT NULL,
		Nome VARCHAR(200) NULL,
		Pos TINYINT NULL,
		CONSTRAINT PK_tblFattureRitenuteCausali PRIMARY KEY CLUSTERED (Id)
	);
END
GO
MERGE dbo.tblFattureRitenuteCausali AS t
USING (VALUES
	('A', 'Lavoro autonomo nell''esercizio abituale di arte o professione', 1),
	('B', 'Utilizzazione economica di opere dell''ingegno e brevetti da parte dell''autore o inventore', 2),
	('C', 'Utili da contratti di associazione in partecipazione e di cointeressenza', 3),
	('D', 'Utili spettanti ai soci promotori e ai soci fondatori delle società di capitali', 4),
	('E', 'Levata di protesti cambiari da parte dei segretari comunali', 5),
	('G', 'Indennità per la cessazione di attività sportiva professionale', 6),
	('H', 'Indennità per la cessazione dei rapporti di agenzia', 7),
	('I', 'Indennità per la cessazione da funzioni notarili', 8),
	('L', 'Opere dell''ingegno e brevetti: redditi percepiti dagli aventi causa a titolo gratuito', 9),
	('L1', 'Opere dell''ingegno e brevetti: redditi percepiti da chi ha acquistato i diritti a titolo oneroso', 10),
	('M', 'Lavoro autonomo non esercitato abitualmente', 11),
	('M1', 'Assunzione di obblighi di fare, di non fare o permettere', 12),
	('M2', 'Lavoro autonomo non abituale con obbligo di iscrizione alla Gestione separata ENPAPI', 13),
	('N', 'Indennità, rimborsi e compensi nell''esercizio di attività sportive dilettantistiche', 14),
	('O', 'Lavoro autonomo non abituale senza obbligo di iscrizione alla gestione separata', 15),
	('O1', 'Obblighi di fare, di non fare o permettere senza obbligo di iscrizione alla gestione separata', 16),
	('P', 'Compensi a non residenti per l''uso di attrezzature industriali, commerciali o scientifiche', 17),
	('Q', 'Provvigioni ad agente o rappresentante di commercio monomandatario', 18),
	('R', 'Provvigioni ad agente o rappresentante di commercio plurimandatario', 19),
	('S', 'Provvigioni a commissionario', 20),
	('T', 'Provvigioni a mediatore', 21),
	('U', 'Provvigioni a procacciatore di affari', 22),
	('V', 'Provvigioni a incaricato per le vendite a domicilio o per la vendita ambulante di giornali', 23),
	('V1', 'Attività commerciali non esercitate abitualmente (provvigioni occasionali)', 24),
	('W', 'Corrispettivi per prestazioni relative a contratti d''appalto (art. 25-ter, D.P.R. 600/1973)', 25),
	('X', 'Canoni corrisposti nel 2004 a società o stabili organizzazioni di altri Stati UE', 26),
	('Y', 'Canoni corrisposti dal 1° gennaio al 26 luglio 2005 a società o stabili organizzazioni di altri Stati UE', 27),
	('ZO', 'Titolo diverso dai precedenti', 28)
) AS s (Id, Nome, Pos) ON t.Id = s.Id
WHEN MATCHED AND (ISNULL(t.Nome, '') <> s.Nome OR ISNULL(t.Pos, 0) <> s.Pos) THEN UPDATE SET Nome = s.Nome, Pos = s.Pos
WHEN NOT MATCHED THEN INSERT (Id, Nome, Pos) VALUES (s.Id, s.Nome, s.Pos);
GO
-- Dati fiscali dell'azienda interna (Id = azienda, una riga per azienda). NumeroRea è quello dell'azienda: non
-- è tblSediDatiEstesi.NumeroRea, che il MUD salva sull'unità locale. SocioUnico: SU socio unico, SM più soci.
-- StatoLiquidazione: LS in liquidazione, LN non in liquidazione.
IF OBJECT_ID('dbo.tblFattureDatiFiscali') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureDatiFiscali (
		Id CHAR(16) NOT NULL,
		IdRegimeFiscale CHAR(4) NULL,
		IdProvinciaRea CHAR(3) NULL,
		IdRitenutaTipo CHAR(4) NULL,
		IdRitenutaCausale VARCHAR(2) NULL,
		NumeroRea VARCHAR(20) NULL,
		CapitaleSociale DECIMAL(18, 2) NULL,
		SocioUnico CHAR(2) NULL,
		StatoLiquidazione CHAR(2) NULL,
		CONSTRAINT PK_tblFattureDatiFiscali PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblFattureDatiFiscali WITH CHECK ADD CONSTRAINT FK_tblFattureDatiFiscali_tblSedi FOREIGN KEY (Id) REFERENCES dbo.tblSedi (Id);
	ALTER TABLE dbo.tblFattureDatiFiscali WITH CHECK ADD CONSTRAINT FK_tblFattureDatiFiscali_tblFattureRegimiFiscali FOREIGN KEY (IdRegimeFiscale) REFERENCES dbo.tblFattureRegimiFiscali (Id);
	ALTER TABLE dbo.tblFattureDatiFiscali WITH CHECK ADD CONSTRAINT FK_tblFattureDatiFiscali_tblProvince FOREIGN KEY (IdProvinciaRea) REFERENCES dbo.tblProvince (Id);
	ALTER TABLE dbo.tblFattureDatiFiscali WITH CHECK ADD CONSTRAINT FK_tblFattureDatiFiscali_tblFattureRitenuteTipi FOREIGN KEY (IdRitenutaTipo) REFERENCES dbo.tblFattureRitenuteTipi (Id);
	ALTER TABLE dbo.tblFattureDatiFiscali WITH CHECK ADD CONSTRAINT FK_tblFattureDatiFiscali_tblFattureRitenuteCausali FOREIGN KEY (IdRitenutaCausale) REFERENCES dbo.tblFattureRitenuteCausali (Id);
END
GO
-- Aliquote IVA: riferimento normativo dell'operazione senza IVA (es. "Art. 10 D.P.R. 633/1972"), riportato nel
-- riepilogo IVA del file accanto alla natura. Le aliquote di sistema non si modificano dall'applicazione: il
-- riferimento dell'aliquota "Esente" si imposta qui
IF COL_LENGTH('dbo.tblAliquoteIva', 'RiferimentoNormativo') IS NULL
	ALTER TABLE dbo.tblAliquoteIva ADD RiferimentoNormativo VARCHAR(100) NULL;
GO
UPDATE dbo.tblAliquoteIva
SET RiferimentoNormativo = 'Operazione esente art. 10 D.P.R. 633/1972'
WHERE
	Id = '54de2336ccc94971'
	AND IdSede IS NULL
	AND RiferimentoNormativo IS NULL;
GO
-- Pagina e voce di menu. Menu Fatturazione: Fatture clienti, Fatture fornitori, Scadenziario clienti,
-- Scadenziario fornitori, Conti, Banche e casse, Aliquote IVA, Dati fiscali (ultima: è configurazione iniziale)
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTD')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTD', 'FTC', 'Dati fiscali', 'dati-fiscali', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ8')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ8', 'AJ0', NULL, 'FTD', 7);

UPDATE dbo.tblMenu SET Pos = 5 WHERE Id = 'AJ1' AND Pos <> 5;
UPDATE dbo.tblMenu SET Pos = 6 WHERE Id = 'AJ2' AND Pos <> 6;
UPDATE dbo.tblMenu SET Pos = 7 WHERE Id = 'AJ8' AND Pos <> 7;
GO
