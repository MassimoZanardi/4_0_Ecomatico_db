-- Fatturazione > Fatture clienti e fornitori: tabelle (fatture, righe, importi, conti, rate, pagamenti),
-- tipi di documento, funzione FTT, pagine e voci di menu.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già tabelle e registrazione.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Tipi di documento: tblFattureTipi passa dal codice interno (F, N, P) al codice della fattura
-- elettronica (TD01...), che prima stava in tblFattureTipiDocumenti. Nessuna tabella le usava ancora.
IF OBJECT_ID('dbo.tblFattureTipiDocumenti') IS NOT NULL
	DROP TABLE dbo.tblFattureTipiDocumenti;

IF OBJECT_ID('dbo.tblFattureTipi') IS NOT NULL AND COL_LENGTH('dbo.tblFattureTipi', 'Id') = 1
	DROP TABLE dbo.tblFattureTipi;
GO
IF OBJECT_ID('dbo.tblFattureTipi') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureTipi (
		Id CHAR(4) NOT NULL,
		Nome VARCHAR(50) NULL,
		CONSTRAINT PK_tblFattureTipi PRIMARY KEY CLUSTERED (Id)
	);
END
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD00') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD00', 'Pre-fattura');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD01') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD01', 'Fattura');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD02') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD02', 'Fattura acconto/anticipo');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD04') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD04', 'Nota accredito');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD17') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD17', 'Autofattura per acquisto di servizi');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD18') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD18', 'Autofattura per acquisto beni');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD19') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD19', 'Autofattura per acquisto beni art. 17');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'TD24') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('TD24', 'Fattura differita');
GO
-- Conti dell'azienda interna (IdSede = azienda), per classificare gli importi delle righe
IF OBJECT_ID('dbo.tblFattureConti') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureConti (
		Id CHAR(16) NOT NULL,
		IdSede CHAR(16) NULL,
		Nome VARCHAR(50) NULL,
		Codice VARCHAR(10) NULL,
		Lock TINYINT NULL,
		CONSTRAINT PK_tblFattureConti PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblFattureConti WITH CHECK ADD CONSTRAINT FK_tblFattureConti_tblSedi FOREIGN KEY (IdSede) REFERENCES dbo.tblSedi (Id);
END
GO
-- Fattura: IdSede = azienda interna che la emette (Tipo C, cliente) o la riceve (Tipo F, fornitore);
-- IdClienteFornitore = scheda del cliente o del fornitore. Lock 0 attiva, 2 bozza, 4 cancellata.
-- IdFatturaRiferimento = fattura stornata da una nota di credito; Causale = causale del documento.
IF OBJECT_ID('dbo.tblFatture') IS NULL
BEGIN
	CREATE TABLE dbo.tblFatture (
		Id CHAR(16) NOT NULL,
		IdSede CHAR(16) NULL,
		IdClienteFornitore CHAR(16) NULL,
		IdTipo CHAR(4) NULL,
		IdStato CHAR(1) NULL,
		IdModalita CHAR(4) NULL,
		IdRata CHAR(3) NULL,
		IdRataInizio CHAR(2) NULL,
		IdValuta CHAR(3) NULL,
		IdBancaCassa CHAR(16) NULL,
		IdFatturaRiferimento CHAR(16) NULL,
		Tipo CHAR(1) NULL,
		Numero INT NULL,
		Sezionale CHAR(1) NULL,
		NumeroFornitore VARCHAR(30) NULL,
		DataRegistrazione DATE NULL,
		DataEmissione DATE NULL,
		Causale VARCHAR(200) NULL,
		Iban VARCHAR(34) NULL,
		RataGiorniInizio INT NULL,
		Ordine VARCHAR(30) NULL,
		DataOrdine DATE NULL,
		SplitPayment BIT NULL,
		Bollo DECIMAL(9, 2) NULL,
		CodiceCig VARCHAR(10) NULL,
		CodiceCup VARCHAR(15) NULL,
		SolaLettura BIT NULL,
		Lock TINYINT NULL,
		CONSTRAINT PK_tblFatture PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblSedi FOREIGN KEY (IdSede) REFERENCES dbo.tblSedi (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblClientiFornitori FOREIGN KEY (IdClienteFornitore) REFERENCES dbo.tblClientiFornitori (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblFattureTipi FOREIGN KEY (IdTipo) REFERENCES dbo.tblFattureTipi (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblFattureStati FOREIGN KEY (IdStato) REFERENCES dbo.tblFattureStati (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblPagamentiModalita FOREIGN KEY (IdModalita) REFERENCES dbo.tblPagamentiModalita (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblPagamentiRate FOREIGN KEY (IdRata) REFERENCES dbo.tblPagamentiRate (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblPagamentiRateInizi FOREIGN KEY (IdRataInizio) REFERENCES dbo.tblPagamentiRateInizi (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblPagamentiValute FOREIGN KEY (IdValuta) REFERENCES dbo.tblPagamentiValute (Id);
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblBancheCasse FOREIGN KEY (IdBancaCassa) REFERENCES dbo.tblBancheCasse (Id);
END
GO
-- Il tipo di documento può essere rimasto senza FK se tblFattureTipi è stata ricreata più sopra
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblFatture_tblFattureTipi')
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblFattureTipi FOREIGN KEY (IdTipo) REFERENCES dbo.tblFattureTipi (Id);
GO
-- Riga della fattura: descrizione e posizione. Una riga senza importi è di sola descrizione.
-- Righe e rate non hanno un Lock proprio: seguono la fattura
IF OBJECT_ID('dbo.tblFattureRighe') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureRighe (
		Id CHAR(16) NOT NULL,
		IdFattura CHAR(16) NULL,
		Descrizione VARCHAR(1000) NULL,
		Pos INT NULL,
		CONSTRAINT PK_tblFattureRighe PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblFattureRighe WITH CHECK ADD CONSTRAINT FK_tblFattureRighe_tblFatture FOREIGN KEY (IdFattura) REFERENCES dbo.tblFatture (Id);
END
GO
-- Importi della riga (Id = riga): Importo è il prezzo unitario, il totale della riga è Quantita x Importo
IF OBJECT_ID('dbo.tblFattureRigheImporti') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureRigheImporti (
		Id CHAR(16) NOT NULL,
		IdAliquotaIva CHAR(16) NULL,
		IdConto CHAR(16) NULL,
		IdUnitaMisura CHAR(2) NULL,
		Quantita DECIMAL(18, 4) NULL,
		Importo DECIMAL(18, 4) NULL,
		RitenutaAcconto INT NULL,
		CONSTRAINT PK_tblFattureRigheImporti PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblFattureRigheImporti WITH CHECK ADD CONSTRAINT FK_tblFattureRigheImporti_tblFattureRighe FOREIGN KEY (Id) REFERENCES dbo.tblFattureRighe (Id);
	ALTER TABLE dbo.tblFattureRigheImporti WITH CHECK ADD CONSTRAINT FK_tblFattureRigheImporti_tblAliquoteIva FOREIGN KEY (IdAliquotaIva) REFERENCES dbo.tblAliquoteIva (Id);
	ALTER TABLE dbo.tblFattureRigheImporti WITH CHECK ADD CONSTRAINT FK_tblFattureRigheImporti_tblFattureConti FOREIGN KEY (IdConto) REFERENCES dbo.tblFattureConti (Id);
	ALTER TABLE dbo.tblFattureRigheImporti WITH CHECK ADD CONSTRAINT FK_tblFattureRigheImporti_tblUnitaMisura FOREIGN KEY (IdUnitaMisura) REFERENCES dbo.tblUnitaMisura (Id);
END
GO
-- Pagamento dell'azienda interna IdSede: Tipo E entrata (incasso da un cliente), U uscita (pagamento a
-- un fornitore). Può saldare una o più rate: quanto va a ciascuna è in tblFattureRatePagamenti.Importo
IF OBJECT_ID('dbo.tblPagamenti') IS NULL
BEGIN
	CREATE TABLE dbo.tblPagamenti (
		Id CHAR(16) NOT NULL,
		IdSede CHAR(16) NULL,
		IdBancaCassa CHAR(16) NULL,
		IdModalita CHAR(4) NULL,
		Tipo CHAR(1) NULL,
		Causale VARCHAR(100) NULL,
		DataRegistrazione DATE NULL,
		DataContabile DATE NULL,
		Importo DECIMAL(18, 2) NULL,
		Lock TINYINT NULL,
		CONSTRAINT PK_tblPagamenti PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblPagamenti WITH CHECK ADD CONSTRAINT FK_tblPagamenti_tblBancheCasse FOREIGN KEY (IdBancaCassa) REFERENCES dbo.tblBancheCasse (Id);
	ALTER TABLE dbo.tblPagamenti WITH CHECK ADD CONSTRAINT FK_tblPagamenti_tblPagamentiModalita FOREIGN KEY (IdModalita) REFERENCES dbo.tblPagamentiModalita (Id);
END
GO
-- Rata (scadenza) della fattura
IF OBJECT_ID('dbo.tblFattureRate') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureRate (
		Id CHAR(16) NOT NULL,
		IdFattura CHAR(16) NULL,
		Importo DECIMAL(18, 2) NULL,
		Abbuono DECIMAL(18, 2) NULL,
		DataScadenza DATE NULL,
		Note VARCHAR(200) NULL,
		CONSTRAINT PK_tblFattureRate PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblFattureRate WITH CHECK ADD CONSTRAINT FK_tblFattureRate_tblFatture FOREIGN KEY (IdFattura) REFERENCES dbo.tblFatture (Id);
END
GO
IF OBJECT_ID('dbo.tblFattureRatePagamenti') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureRatePagamenti (
		IdRata CHAR(16) NOT NULL,
		IdPagamento CHAR(16) NOT NULL,
		Importo DECIMAL(18, 2) NULL,
		CONSTRAINT PK_tblFattureRatePagamenti PRIMARY KEY CLUSTERED (IdRata, IdPagamento)
	);

	ALTER TABLE dbo.tblFattureRatePagamenti WITH CHECK ADD CONSTRAINT FK_tblFattureRatePagamenti_tblFattureRate FOREIGN KEY (IdRata) REFERENCES dbo.tblFattureRate (Id);
	ALTER TABLE dbo.tblFattureRatePagamenti WITH CHECK ADD CONSTRAINT FK_tblFattureRatePagamenti_tblPagamenti FOREIGN KEY (IdPagamento) REFERENCES dbo.tblPagamenti (Id);
END
GO
-- Allineamento delle tabelle create con una versione precedente di questo script (sviluppo): colonne
-- aggiunte, importi a DECIMAL(18, 2), Lock tolto da righe e rate
IF COL_LENGTH('dbo.tblFatture', 'IdFatturaRiferimento') IS NULL
	ALTER TABLE dbo.tblFatture ADD IdFatturaRiferimento CHAR(16) NULL;
IF COL_LENGTH('dbo.tblFatture', 'Causale') IS NULL
	ALTER TABLE dbo.tblFatture ADD Causale VARCHAR(200) NULL;
IF COL_LENGTH('dbo.tblFatture', 'Note') IS NOT NULL
	ALTER TABLE dbo.tblFatture DROP COLUMN Note;
IF COL_LENGTH('dbo.tblFattureRighe', 'Lock') IS NOT NULL
	ALTER TABLE dbo.tblFattureRighe DROP COLUMN Lock;
IF COL_LENGTH('dbo.tblFattureRate', 'Lock') IS NOT NULL
	ALTER TABLE dbo.tblFattureRate DROP COLUMN Lock;
IF COL_LENGTH('dbo.tblFattureRate', 'Note') > 200
	ALTER TABLE dbo.tblFattureRate ALTER COLUMN Note VARCHAR(200) NULL;
IF COL_LENGTH('dbo.tblPagamenti', 'IdSede') IS NULL
	ALTER TABLE dbo.tblPagamenti ADD IdSede CHAR(16) NULL;
IF COL_LENGTH('dbo.tblPagamenti', 'Tipo') IS NULL
	ALTER TABLE dbo.tblPagamenti ADD Tipo CHAR(1) NULL;
IF COL_LENGTH('dbo.tblFattureRatePagamenti', 'Importo') IS NULL
	ALTER TABLE dbo.tblFattureRatePagamenti ADD Importo DECIMAL(18, 2) NULL;
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblFattureRate') AND name IN ('Importo', 'Abbuono') AND precision <> 18)
BEGIN
	ALTER TABLE dbo.tblFattureRate ALTER COLUMN Importo DECIMAL(18, 2) NULL;
	ALTER TABLE dbo.tblFattureRate ALTER COLUMN Abbuono DECIMAL(18, 2) NULL;
END
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblPagamenti') AND name = 'Importo' AND precision <> 18)
	ALTER TABLE dbo.tblPagamenti ALTER COLUMN Importo DECIMAL(18, 2) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblFatture_tblFatture')
	ALTER TABLE dbo.tblFatture WITH CHECK ADD CONSTRAINT FK_tblFatture_tblFatture FOREIGN KEY (IdFatturaRiferimento) REFERENCES dbo.tblFatture (Id);

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblPagamenti_tblSedi')
	ALTER TABLE dbo.tblPagamenti WITH CHECK ADD CONSTRAINT FK_tblPagamenti_tblSedi FOREIGN KEY (IdSede) REFERENCES dbo.tblSedi (Id);
GO
-- Indici di ricerca: elenco delle fatture per azienda, tipo e data; fatture di un cliente o fornitore;
-- righe e rate di una fattura
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblFatture_IdSede_Tipo_DataEmissione' AND object_id = OBJECT_ID('dbo.tblFatture'))
	CREATE NONCLUSTERED INDEX IX_tblFatture_IdSede_Tipo_DataEmissione ON dbo.tblFatture (IdSede, Tipo, DataEmissione);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblFatture_IdClienteFornitore' AND object_id = OBJECT_ID('dbo.tblFatture'))
	CREATE NONCLUSTERED INDEX IX_tblFatture_IdClienteFornitore ON dbo.tblFatture (IdClienteFornitore);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblFattureRighe_IdFattura' AND object_id = OBJECT_ID('dbo.tblFattureRighe'))
	CREATE NONCLUSTERED INDEX IX_tblFattureRighe_IdFattura ON dbo.tblFattureRighe (IdFattura);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblFattureRate_IdFattura' AND object_id = OBJECT_ID('dbo.tblFattureRate'))
	CREATE NONCLUSTERED INDEX IX_tblFattureRate_IdFattura ON dbo.tblFattureRate (IdFattura);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblFattureConti_IdSede' AND object_id = OBJECT_ID('dbo.tblFattureConti'))
	CREATE NONCLUSTERED INDEX IX_tblFattureConti_IdSede ON dbo.tblFattureConti (IdSede);
GO
-- Funzione FTT "Fatture" nel modulo Fatturazione (FAT): un solo permesso per fatture clienti e fornitori.
-- I conti sono configurazione (funzione FTC, come banche e casse e aliquote IVA)
IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'FTT')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('FTT', 'Fatture', 0, 0, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'FAT' AND IdFunzione = 'FTT')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('FAT', 'FTT');

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTE')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTE', 'FTT', 'Fatture clienti', 'fatture-clienti', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTF')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTF', 'FTT', 'Fatture fornitori', 'fatture-fornitori', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTK')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTK', 'FTC', 'Conti', 'conti', NULL);

-- Menu Fatturazione: Fatture clienti, Fatture fornitori, Conti, Banche e casse, Aliquote IVA
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ3')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ3', 'AJ0', NULL, 'FTE', 0);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ4')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ4', 'AJ0', NULL, 'FTF', 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ5')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ5', 'AJ0', NULL, 'FTK', 2);

UPDATE dbo.tblMenu SET Pos = 3 WHERE Id = 'AJ1' AND Pos <> 3;
UPDATE dbo.tblMenu SET Pos = 4 WHERE Id = 'AJ2' AND Pos <> 4;
GO
