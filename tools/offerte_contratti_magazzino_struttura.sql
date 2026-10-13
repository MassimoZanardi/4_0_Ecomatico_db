SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Offerte e contratti, fase magazzino: importi dei DDT e causali fatturabili.
--   1. tblMagazziniCausali.IsFatturabile: causali i cui DDT entrano nella fatturazione. Solo Vendita (V).
--   2. tblImportiMagazzino: via il mittente dalle variabili (IdMittenteParent, IdMittente); nuove variabili
--      IdArticolo (righe articolo del DDT) e IdMateriale (righe EoW), che si escludono; IdSede, copia
--      dell'azienda dell'importo, per il confronto con i documenti (come tblImportiRifiuti.IdSede).
--   3. Indice per il confronto: gli importi di magazzino dell'azienda con le loro variabili.
-- Variabili che restano: destinatario (soggetto e sede), articolo, materiale, etichetta.
-- Rieseguibile. Da eseguire dopo offerte_contratti_struttura.sql e magazzino_etichette_struttura.sql.

BEGIN TRANSACTION;

-- 1. Causali fatturabili
IF COL_LENGTH('dbo.tblMagazziniCausali', 'IsFatturabile') IS NULL
	ALTER TABLE dbo.tblMagazziniCausali ADD IsFatturabile BIT NULL;

-- 2. Variabili degli importi di magazzino
IF OBJECT_ID('dbo.FK_tblImportiMagazzino_tblSedi_IdMittenteParent', 'F') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP CONSTRAINT FK_tblImportiMagazzino_tblSedi_IdMittenteParent;

IF OBJECT_ID('dbo.FK_tblImportiMagazzino_tblSedi_IdMittente', 'F') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP CONSTRAINT FK_tblImportiMagazzino_tblSedi_IdMittente;

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdMittenteParent') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP COLUMN IdMittenteParent;

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdMittente') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP COLUMN IdMittente;

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdArticolo') IS NULL
BEGIN
	ALTER TABLE dbo.tblImportiMagazzino ADD IdArticolo CHAR(16) COLLATE Latin1_General_CI_AS NULL;

	ALTER TABLE dbo.tblImportiMagazzino WITH CHECK ADD CONSTRAINT FK_tblImportiMagazzino_tblMagazziniArticoli
		FOREIGN KEY (IdArticolo) REFERENCES dbo.tblMagazziniArticoli (Id);
END

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdMateriale') IS NULL
BEGIN
	ALTER TABLE dbo.tblImportiMagazzino ADD IdMateriale CHAR(2) COLLATE Latin1_General_CI_AS NULL;

	ALTER TABLE dbo.tblImportiMagazzino WITH CHECK ADD CONSTRAINT FK_tblImportiMagazzino_tblRifiutiMateriali
		FOREIGN KEY (IdMateriale) REFERENCES dbo.tblRifiutiMateriali (Id);
END

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdSede') IS NULL
	ALTER TABLE dbo.tblImportiMagazzino ADD IdSede CHAR(16) COLLATE Latin1_General_CI_AS NULL;

COMMIT TRANSACTION;
GO

BEGIN TRANSACTION;

-- 1. Solo Vendita
UPDATE dbo.tblMagazziniCausali
SET IsFatturabile = IIF(Id = 'V', 1, 0)
WHERE IsFatturabile IS NULL;

-- 2. Importi esistenti: l'azienda dell'importo
UPDATE m
SET IdSede = i.IdSede
FROM
	dbo.tblImportiMagazzino m
	INNER JOIN dbo.tblImporti i ON m.Id = i.Id
WHERE m.IdSede IS NULL;

-- 3. Importi di magazzino dell'azienda con le loro variabili: il confronto con ogni riga di DDT legge solo questi
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiMagazzino_IdSede')
	CREATE NONCLUSTERED INDEX IX_ImportiMagazzino_IdSede ON dbo.tblImportiMagazzino (IdSede)
		INCLUDE (IdDestinatarioParent, IdDestinatario, IdArticolo, IdMateriale, IdEtichetta);

COMMIT TRANSACTION;
GO

SELECT Id, Nome, IsFatturabile FROM dbo.tblMagazziniCausali ORDER BY Nome;
GO
