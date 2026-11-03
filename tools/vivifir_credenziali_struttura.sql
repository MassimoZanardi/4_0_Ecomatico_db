-- Vi.Vi.FIR (formulario unico degli spurghisti, art. 230, comma 5): configurazione nell'app, come Diwass > Credenziali
-- e Aziende. Da eseguire dopo 1_0_vivifir\tools\vivifir_creazione.sql (le SP dell'app scrivono in
-- [1_0_vivifir]..tblCredenziali) e dopo tools/formulario_unico_struttura.sql (modulo VVF).
-- 1) tblViviFirCredenziali: credenziale applicativa del dominio (nome, scadenza informativa, Id della riga dell'hub);
-- 2) tblViviFirCredenzialiAziende: azienda interna dello spurghista ↔ credenziale (al massimo una per azienda), con
--    l'esito dell'ultima verifica: soggetto Vi.Vi.FIR e codice del blocco del formulario unico (isArt230c5);
-- 3) funzione VVC (Vi.Vi.FIR, riservata agli amministratori) del modulo VVF;
-- 4) area di menu Vivifir (Id = modulo VVF, dopo Diwass) con le voci Credenziali e Aziende.
-- Script idempotente: rieseguibile senza effetti su un DB già aggiornato.
SET NOCOUNT ON;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID('dbo.tblViviFirCredenziali', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblViviFirCredenziali (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdDominio CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdViviFir CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		Nome VARCHAR(50) COLLATE Latin1_General_CI_AS NULL,
		Scadenza DATE NULL,
		Lock TINYINT NULL,
		CONSTRAINT PK_tblViviFirCredenziali PRIMARY KEY CLUSTERED (Id ASC)
	);

	ALTER TABLE dbo.tblViviFirCredenziali WITH CHECK ADD CONSTRAINT FK_tblViviFirCredenziali_tblDomini
		FOREIGN KEY (IdDominio) REFERENCES dbo.tblDomini (Id);

	CREATE NONCLUSTERED INDEX IX_ViviFirCredenziali_IdDominio_Lock ON dbo.tblViviFirCredenziali (IdDominio ASC, Lock ASC);
END
GO
IF OBJECT_ID('dbo.tblViviFirCredenzialiAziende', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblViviFirCredenzialiAziende (
		IdAziendaInterna CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdCredenziale CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdSoggetto INT NULL,
		Soggetto VARCHAR(255) COLLATE Latin1_General_CI_AS NULL,
		Blocco VARCHAR(20) COLLATE Latin1_General_CI_AS NULL,
		DataVerifica DATETIME2(0) NULL,
		CONSTRAINT PK_tblViviFirCredenzialiAziende PRIMARY KEY CLUSTERED (IdAziendaInterna ASC)
	);

	ALTER TABLE dbo.tblViviFirCredenzialiAziende WITH CHECK ADD CONSTRAINT FK_tblViviFirCredenzialiAziende_tblSediInterne
		FOREIGN KEY (IdAziendaInterna) REFERENCES dbo.tblSediInterne (Id);
	ALTER TABLE dbo.tblViviFirCredenzialiAziende WITH CHECK ADD CONSTRAINT FK_tblViviFirCredenzialiAziende_tblViviFirCredenziali
		FOREIGN KEY (IdCredenziale) REFERENCES dbo.tblViviFirCredenziali (Id);

	CREATE NONCLUSTERED INDEX IX_ViviFirCredenzialiAziende_IdCredenziale ON dbo.tblViviFirCredenzialiAziende (IdCredenziale ASC);
END
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'VVC')
	INSERT INTO dbo.tblFunzioni (Id, Nome, [Master], Admin, Attiva) VALUES ('VVC', 'Vi.Vi.FIR', 0, 1, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'VVF' AND IdFunzione = 'VVC')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('VVF', 'VVC');

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagineAree WHERE Id = 'VVF')
	INSERT INTO dbo.tblPagineAree (Id, Nome, Icon) VALUES ('VVF', 'Vivifir', 'fal fa-stamp');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'VVZ')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url) VALUES ('VVZ', 'VVC', 'Credenziali', NULL);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'VVY')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url) VALUES ('VVY', 'VVC', 'Aziende', NULL);

-- Area dopo Diwass (AL0, Pos 10), prima di Impostazioni
UPDATE dbo.tblMenu SET Pos = 12 WHERE Id = 'AZ0' AND Pos <> 12;
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AM0')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AM0', NULL, 'VVF', NULL, 11);
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AM1')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AM1', 'AM0', NULL, 'VVZ', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AM2')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AM2', 'AM0', NULL, 'VVY', 1);
GO
