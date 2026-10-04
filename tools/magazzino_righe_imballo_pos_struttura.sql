/*
Magazzino - righe di movimento: imballo, colli, alla rinfusa, descrizione, posizione

tblMagazziniMovimentiRighe e tblMagazziniMovimentiRigheEoW:
  IdImballo CHAR(2) NULL (FK tblImballi), Colli INT NULL, AllaRinfusa BIT NULL, Pos INT NULL
tblMagazziniMovimentiRighe:
  Descrizione VARCHAR(1000) NULL (riga descrittiva del DDT: senza articolo, lotto, criterio e quantità)

Pos ordina le righe del movimento ed è unica tra le due tabelle (articoli, descrizioni e materiali EoW
si alternano liberamente). Le righe esistenti restano con Pos NULL (ordinate per prime, per Id):
uspMagazziniMovimentiRighe_upd_Pos le rinumera al primo spostamento.

Rieseguibile.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF COL_LENGTH('dbo.tblMagazziniMovimentiRighe', 'IdImballo') IS NULL
	ALTER TABLE dbo.tblMagazziniMovimentiRighe ADD
		IdImballo CHAR(2) NULL,
		Colli INT NULL,
		AllaRinfusa BIT NULL,
		Descrizione VARCHAR(1000) NULL,
		Pos INT NULL;
GO
-- Descrizione nata a 100 caratteri (solo in sviluppo) e poi allargata a 1000
IF COL_LENGTH('dbo.tblMagazziniMovimentiRighe', 'Descrizione') < 1000
	ALTER TABLE dbo.tblMagazziniMovimentiRighe ALTER COLUMN Descrizione VARCHAR(1000) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblMagazziniMovimentiRighe_tblImballi')
BEGIN
	ALTER TABLE dbo.tblMagazziniMovimentiRighe WITH CHECK ADD CONSTRAINT FK_tblMagazziniMovimentiRighe_tblImballi FOREIGN KEY (IdImballo)
	REFERENCES dbo.tblImballi (Id);
	ALTER TABLE dbo.tblMagazziniMovimentiRighe CHECK CONSTRAINT FK_tblMagazziniMovimentiRighe_tblImballi;
END
GO
IF COL_LENGTH('dbo.tblMagazziniMovimentiRigheEoW', 'IdImballo') IS NULL
	ALTER TABLE dbo.tblMagazziniMovimentiRigheEoW ADD
		IdImballo CHAR(2) NULL,
		Colli INT NULL,
		AllaRinfusa BIT NULL,
		Pos INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblMagazziniMovimentiRigheEoW_tblImballi')
BEGIN
	ALTER TABLE dbo.tblMagazziniMovimentiRigheEoW WITH CHECK ADD CONSTRAINT FK_tblMagazziniMovimentiRigheEoW_tblImballi FOREIGN KEY (IdImballo)
	REFERENCES dbo.tblImballi (Id);
	ALTER TABLE dbo.tblMagazziniMovimentiRigheEoW CHECK CONSTRAINT FK_tblMagazziniMovimentiRigheEoW_tblImballi;
END
GO
