SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Offerte e contratti, fase magazzino: importi dei DDT e causali fatturabili.
-- L'importo di magazzino è un LISTINO: vale per una tratta e un destinatario (o per tutti) e ha una riga per ogni
-- articolo o materiale, con il suo prezzo. L'articolo non è una variabile dell'importo: sta sulla riga, come
-- nella 3.1.
--   1. tblMagazziniCausali.IsFatturabile: causali i cui DDT entrano nella fatturazione. Solo Vendita (V).
--   2. tblImportiMagazzino: variabili sede di partenza (IdSedePartenza, la sede interna del DDT), destinatario
--      (soggetto e sede: la sede si confronta con la destinazione finale della merce) ed etichetta; via il
--      mittente; IdSede, copia dell'azienda dell'importo, per il confronto con i documenti (come
--      tblImportiRifiuti.IdSede). Le colonne IdArticolo e IdMateriale, esistite solo in sviluppo, vengono tolte.
--   3. tblImportiRigheMagazzino: articolo oppure materiale EoW a cui si applica il prezzo di una riga a quantità
--      (tipo MA). Chiave esterna sulla riga ON DELETE CASCADE: cancellata la riga, sparisce da sola.
--   4. Indici.
-- Rieseguibile. Da eseguire dopo offerte_contratti_struttura.sql e magazzino_etichette_struttura.sql.

BEGIN TRANSACTION;

-- 1. Causali fatturabili
IF COL_LENGTH('dbo.tblMagazziniCausali', 'IsFatturabile') IS NULL
	ALTER TABLE dbo.tblMagazziniCausali ADD IsFatturabile BIT NULL;

-- 2. Variabili degli importi di magazzino
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiMagazzino_IdSede')
	DROP INDEX IX_ImportiMagazzino_IdSede ON dbo.tblImportiMagazzino;

IF OBJECT_ID('dbo.FK_tblImportiMagazzino_tblSedi_IdMittenteParent', 'F') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP CONSTRAINT FK_tblImportiMagazzino_tblSedi_IdMittenteParent;

IF OBJECT_ID('dbo.FK_tblImportiMagazzino_tblSedi_IdMittente', 'F') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP CONSTRAINT FK_tblImportiMagazzino_tblSedi_IdMittente;

IF OBJECT_ID('dbo.FK_tblImportiMagazzino_tblMagazziniArticoli', 'F') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP CONSTRAINT FK_tblImportiMagazzino_tblMagazziniArticoli;

IF OBJECT_ID('dbo.FK_tblImportiMagazzino_tblRifiutiMateriali', 'F') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP CONSTRAINT FK_tblImportiMagazzino_tblRifiutiMateriali;

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdMittenteParent') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP COLUMN IdMittenteParent;

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdMittente') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP COLUMN IdMittente;

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdArticolo') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP COLUMN IdArticolo;

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdMateriale') IS NOT NULL
	ALTER TABLE dbo.tblImportiMagazzino DROP COLUMN IdMateriale;

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdSedePartenza') IS NULL
BEGIN
	ALTER TABLE dbo.tblImportiMagazzino ADD IdSedePartenza CHAR(16) COLLATE Latin1_General_CI_AS NULL;

	ALTER TABLE dbo.tblImportiMagazzino WITH CHECK ADD CONSTRAINT FK_tblImportiMagazzino_tblSedi_IdSedePartenza
		FOREIGN KEY (IdSedePartenza) REFERENCES dbo.tblSedi (Id);
END

IF COL_LENGTH('dbo.tblImportiMagazzino', 'IdSede') IS NULL
	ALTER TABLE dbo.tblImportiMagazzino ADD IdSede CHAR(16) COLLATE Latin1_General_CI_AS NULL;

-- 3. Articolo o materiale delle righe a quantità
IF OBJECT_ID('dbo.tblImportiRigheMagazzino', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblImportiRigheMagazzino (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdArticolo CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		IdMateriale CHAR(2) COLLATE Latin1_General_CI_AS NULL,
		CONSTRAINT PK_tblImportiRigheMagazzino PRIMARY KEY CLUSTERED (Id ASC)
	);

	ALTER TABLE dbo.tblImportiRigheMagazzino WITH CHECK ADD CONSTRAINT FK_tblImportiRigheMagazzino_tblImportiRighe
		FOREIGN KEY (Id) REFERENCES dbo.tblImportiRighe (Id) ON DELETE CASCADE;
	ALTER TABLE dbo.tblImportiRigheMagazzino WITH CHECK ADD CONSTRAINT FK_tblImportiRigheMagazzino_tblMagazziniArticoli
		FOREIGN KEY (IdArticolo) REFERENCES dbo.tblMagazziniArticoli (Id);
	ALTER TABLE dbo.tblImportiRigheMagazzino WITH CHECK ADD CONSTRAINT FK_tblImportiRigheMagazzino_tblRifiutiMateriali
		FOREIGN KEY (IdMateriale) REFERENCES dbo.tblRifiutiMateriali (Id);
END

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

-- 4. Indici
-- Importi di magazzino dell'azienda con le loro variabili: il confronto con ogni DDT legge solo questi
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiMagazzino_IdSede')
	CREATE NONCLUSTERED INDEX IX_ImportiMagazzino_IdSede ON dbo.tblImportiMagazzino (IdSede)
		INCLUDE (IdSedePartenza, IdDestinatarioParent, IdDestinatario, IdEtichetta);

-- Righe di importo di un articolo: controllo di cancellazione dell'articolo e chiave esterna
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiRigheMagazzino_IdArticolo')
	CREATE NONCLUSTERED INDEX IX_ImportiRigheMagazzino_IdArticolo ON dbo.tblImportiRigheMagazzino (IdArticolo)
		WHERE IdArticolo IS NOT NULL;

COMMIT TRANSACTION;
GO

SELECT Id, Nome, IsFatturabile FROM dbo.tblMagazziniCausali ORDER BY Nome;
GO
