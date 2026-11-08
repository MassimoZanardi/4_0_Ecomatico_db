-- Migrazione dati dalle versioni precedenti di Ecomatico (3.1, 2.0) verso la 4.0: infrastruttura comune.
-- 1) tblMigrazioni: una riga per esecuzione del tool (versione di origine, parametri, simulazione, esito);
-- 2) tblMigrazioniId: corrispondenza Id di origine -> Id 4.0, per tabella e dominio di destinazione. E' la chiave
--    dell'idempotenza: un record di origine gia' mappato non viene mai reinserito. Creato = 1 se il record 4.0 e' stato
--    inserito dal tool, 0 se e' stato abbinato a uno gia' esistente (es. azienda interna con lo stesso CF/PIVA): solo i
--    primi si possono eliminare annullando una migrazione;
-- 3) tblMigrazioniLog: log dettagliato di ogni esecuzione (fase, livello I/W/E, tabella, Id di origine, righe);
-- 4) tblMigrazioniCodici: conversione dei codici delle tabelle di lookup per versione (NULL = codice non migrabile).
--    Le causali della 3.1 restano in tblRifiutiCausaliOperazioni31.
-- Le configurazioni per versione (sinonimi verso il DB di origine e codici) sono in tools/migrazioneNN_configurazione.sql.
-- Script idempotente: rieseguibile senza effetti su un DB gia' aggiornato.
SET NOCOUNT ON;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID('dbo.tblMigrazioni', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblMigrazioni (
		Id INT IDENTITY(1, 1) NOT NULL,
		Versione CHAR(2) COLLATE Latin1_General_CI_AS NOT NULL,
		IdDominioDa VARCHAR(50) COLLATE Latin1_General_CI_AS NOT NULL,
		IdSedeInternaDa VARCHAR(50) COLLATE Latin1_General_CI_AS NULL,
		IdDominioA CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		Simulazione BIT NOT NULL,
		DataInizio DATETIME2(0) NOT NULL,
		DataFine DATETIME2(0) NULL,
		Esito CHAR(1) COLLATE Latin1_General_CI_AS NULL, -- S = completata, A = annullata (simulazione), E = errore
		Messaggio NVARCHAR(2000) COLLATE Latin1_General_CI_AS NULL,
		CONSTRAINT PK_tblMigrazioni PRIMARY KEY CLUSTERED (Id ASC)
	);

	ALTER TABLE dbo.tblMigrazioni WITH CHECK ADD CONSTRAINT FK_tblMigrazioni_tblDomini
		FOREIGN KEY (IdDominioA) REFERENCES dbo.tblDomini (Id);
END
GO
IF OBJECT_ID('dbo.tblMigrazioniId', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblMigrazioniId (
		Versione CHAR(2) COLLATE Latin1_General_CI_AS NOT NULL,
		IdDominioA CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		Tabella VARCHAR(50) COLLATE Latin1_General_CI_AS NOT NULL,
		IdOrigine VARCHAR(50) COLLATE Latin1_General_CI_AS NOT NULL,
		IdDestinazione CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		Creato BIT NOT NULL,
		IdMigrazione INT NOT NULL,
		CONSTRAINT PK_tblMigrazioniId PRIMARY KEY CLUSTERED (Versione ASC, IdDominioA ASC, Tabella ASC, IdOrigine ASC)
	);

	ALTER TABLE dbo.tblMigrazioniId WITH CHECK ADD CONSTRAINT FK_tblMigrazioniId_tblMigrazioni
		FOREIGN KEY (IdMigrazione) REFERENCES dbo.tblMigrazioni (Id);

	CREATE NONCLUSTERED INDEX IX_MigrazioniId_IdDestinazione ON dbo.tblMigrazioniId (IdDestinazione ASC);
	CREATE NONCLUSTERED INDEX IX_MigrazioniId_IdMigrazione ON dbo.tblMigrazioniId (IdMigrazione ASC);
END
GO
IF OBJECT_ID('dbo.tblMigrazioniLog', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblMigrazioniLog (
		Id INT IDENTITY(1, 1) NOT NULL,
		IdMigrazione INT NOT NULL,
		[Data] DATETIME2(3) NOT NULL,
		Fase VARCHAR(50) COLLATE Latin1_General_CI_AS NOT NULL,
		Livello CHAR(1) COLLATE Latin1_General_CI_AS NOT NULL, -- I = informazione, W = avviso (record scartato o dato perso), E = errore
		Tabella VARCHAR(50) COLLATE Latin1_General_CI_AS NULL,
		IdOrigine VARCHAR(50) COLLATE Latin1_General_CI_AS NULL,
		Righe INT NULL,
		Messaggio NVARCHAR(1000) COLLATE Latin1_General_CI_AS NULL,
		CONSTRAINT PK_tblMigrazioniLog PRIMARY KEY CLUSTERED (Id ASC)
	);

	ALTER TABLE dbo.tblMigrazioniLog WITH CHECK ADD CONSTRAINT FK_tblMigrazioniLog_tblMigrazioni
		FOREIGN KEY (IdMigrazione) REFERENCES dbo.tblMigrazioni (Id);

	CREATE NONCLUSTERED INDEX IX_MigrazioniLog_IdMigrazione_Livello ON dbo.tblMigrazioniLog (IdMigrazione ASC, Livello ASC);
END
GO
IF OBJECT_ID('dbo.tblMigrazioniCodici', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblMigrazioniCodici (
		Versione CHAR(2) COLLATE Latin1_General_CI_AS NOT NULL,
		Tabella VARCHAR(50) COLLATE Latin1_General_CI_AS NOT NULL,
		CodiceOrigine VARCHAR(20) COLLATE Latin1_General_CI_AS NOT NULL,
		CodiceDestinazione VARCHAR(20) COLLATE Latin1_General_CI_AS NULL,
		CONSTRAINT PK_tblMigrazioniCodici PRIMARY KEY CLUSTERED (Versione ASC, Tabella ASC, CodiceOrigine ASC)
	);
END
GO
