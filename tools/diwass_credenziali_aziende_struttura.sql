-- DIWASS: la credenziale diventa del dominio e si associa alle aziende interne in Diwass > Aziende, come le credenziali
-- RENTRI si associano alle sedi in Rentri > Sedi. La chiave DIWASS è dell'utente EU Login e vale per tutte le aziende
-- che rappresenta: una credenziale può servire più aziende, ogni azienda ne usa al massimo una.
-- 1) tabella di associazione tblDiwassCredenzialiAziende (una riga per azienda);
-- 2) migrazione delle credenziali attive da tblDiwassCredenziali.IdAziendaInterna;
-- 3) eliminazione di IdAziendaInterna da tblDiwassCredenziali (con indice unico e FK);
-- 4) pagina e voce di menu Diwass > Aziende (funzione DWC, dopo Credenziali);
-- 5) eliminazione di uspDiwassCredenziali_get_AziendeInterne_SelectList (la credenziale non sceglie più l'azienda).
-- Script idempotente: rieseguibile senza effetti su un DB già aggiornato.
SET NOCOUNT ON;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID('dbo.tblDiwassCredenzialiAziende', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblDiwassCredenzialiAziende (
		IdAziendaInterna CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdCredenziale CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		CONSTRAINT PK_tblDiwassCredenzialiAziende PRIMARY KEY CLUSTERED (IdAziendaInterna ASC)
	);

	ALTER TABLE dbo.tblDiwassCredenzialiAziende WITH CHECK ADD CONSTRAINT FK_tblDiwassCredenzialiAziende_tblSediInterne
		FOREIGN KEY (IdAziendaInterna) REFERENCES dbo.tblSediInterne (Id);
	ALTER TABLE dbo.tblDiwassCredenzialiAziende WITH CHECK ADD CONSTRAINT FK_tblDiwassCredenzialiAziende_tblDiwassCredenziali
		FOREIGN KEY (IdCredenziale) REFERENCES dbo.tblDiwassCredenziali (Id);

	CREATE NONCLUSTERED INDEX IX_DiwassCredenzialiAziende_IdCredenziale ON dbo.tblDiwassCredenzialiAziende (IdCredenziale ASC);
END
GO
IF COL_LENGTH('dbo.tblDiwassCredenziali', 'IdAziendaInterna') IS NOT NULL
BEGIN
	-- Le credenziali attive conservano la loro azienda; quelle cancellate (Lock = 4) e le bozze restano senza
	EXEC sp_executesql N'
		INSERT INTO dbo.tblDiwassCredenzialiAziende (IdAziendaInterna, IdCredenziale)
		SELECT c.IdAziendaInterna, c.Id
		FROM dbo.tblDiwassCredenziali c
		WHERE
			c.Lock = 0
			AND c.IdAziendaInterna IS NOT NULL
			AND NOT EXISTS (SELECT 1 FROM dbo.tblDiwassCredenzialiAziende a WHERE a.IdAziendaInterna = c.IdAziendaInterna);';

	IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_DiwassCredenziali_IdAziendaInterna' AND object_id = OBJECT_ID('dbo.tblDiwassCredenziali'))
		DROP INDEX UX_DiwassCredenziali_IdAziendaInterna ON dbo.tblDiwassCredenziali;
	IF OBJECT_ID('dbo.FK_tblDiwassCredenziali_tblSediInterne', 'F') IS NOT NULL
		ALTER TABLE dbo.tblDiwassCredenziali DROP CONSTRAINT FK_tblDiwassCredenziali_tblSediInterne;
	ALTER TABLE dbo.tblDiwassCredenziali DROP COLUMN IdAziendaInterna;
END
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'DWY')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url) VALUES ('DWY', 'DWC', 'Aziende', NULL);
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AL4')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AL4', 'AL0', NULL, 'DWY', 3);
GO
DROP PROCEDURE IF EXISTS dbo.uspDiwassCredenziali_get_AziendeInterne_SelectList;
GO
