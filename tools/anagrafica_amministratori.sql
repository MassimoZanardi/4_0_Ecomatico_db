-- Anagrafica estesa > Amministratori: tabelle, funzione ANM, pagina e voce di menu dopo Fornitori.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già tabelle e registrazione.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scheda dell'amministratore: un soggetto (azienda esterna) che amministra altri soggetti, per
-- un'azienda interna. Id proprio (uspId_get); Lock 0 attiva, 2 bozza, 4 cancellata.
IF OBJECT_ID('dbo.tblAmministratori') IS NULL
BEGIN
	CREATE TABLE dbo.tblAmministratori (
		Id CHAR(16) NOT NULL,
		IdAziendaInterna CHAR(16) NULL,
		IdSede CHAR(16) NULL,
		Note VARCHAR(1000) NULL,
		Lock TINYINT NULL,
		CONSTRAINT PK_tblAmministratori PRIMARY KEY CLUSTERED (Id)
	);

	ALTER TABLE dbo.tblAmministratori WITH CHECK ADD CONSTRAINT FK_tblAmministratori_tblSedi_IdAziendaInterna FOREIGN KEY (IdAziendaInterna) REFERENCES dbo.tblSedi (Id);
	ALTER TABLE dbo.tblAmministratori WITH CHECK ADD CONSTRAINT FK_tblAmministratori_tblSedi_IdSede FOREIGN KEY (IdSede) REFERENCES dbo.tblSedi (Id);

	CREATE NONCLUSTERED INDEX IX_tblAmministratori_IdSede ON dbo.tblAmministratori (IdSede);
	-- Una sola scheda attiva per soggetto nella stessa azienda
	CREATE UNIQUE NONCLUSTERED INDEX UX_tblAmministratori_IdAziendaInterna_IdSede ON dbo.tblAmministratori (IdAziendaInterna, IdSede) WHERE Lock = 0;
END
GO
-- Soggetti amministrati di una scheda (Id = scheda, IdSede = soggetto amministrato), con le date
-- dell'incarico. "Un solo amministratore per soggetto" vale tra le schede attive e si controlla
-- nelle SP: una scheda cancellata conserva le sue righe per il ripristino.
IF OBJECT_ID('dbo.tblAmministratoriSedi') IS NULL
BEGIN
	CREATE TABLE dbo.tblAmministratoriSedi (
		Id CHAR(16) NOT NULL,
		IdSede CHAR(16) NOT NULL,
		DataInizio DATE NULL,
		DataFine DATE NULL,
		CONSTRAINT PK_tblAmministratoriSedi PRIMARY KEY CLUSTERED (Id, IdSede)
	);

	ALTER TABLE dbo.tblAmministratoriSedi WITH CHECK ADD CONSTRAINT FK_tblAmministratoriSedi_tblAmministratori FOREIGN KEY (Id) REFERENCES dbo.tblAmministratori (Id);
	ALTER TABLE dbo.tblAmministratoriSedi WITH CHECK ADD CONSTRAINT FK_tblAmministratoriSedi_tblSedi FOREIGN KEY (IdSede) REFERENCES dbo.tblSedi (Id);

	CREATE NONCLUSTERED INDEX IX_tblAmministratoriSedi_IdSede ON dbo.tblAmministratoriSedi (IdSede);
END
GO
-- Funzione ANM nel modulo Anagrafica estesa (ANX), pagina e voce di menu sotto Anagrafica, dopo Fornitori
IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'ANM')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('ANM', 'Anagrafica amministratori', 0, 0, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'ANX' AND IdFunzione = 'ANM')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('ANX', 'ANM');

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'ANM')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('ANM', 'ANM', 'Amministratori', NULL, NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AC6')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AC6', 'AC0', NULL, 'ANM', 5);
GO
