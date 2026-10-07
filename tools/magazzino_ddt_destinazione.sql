-- Magazzino > DDT: colonna IdDestinazione (destinazione finale della merce, facoltativa; se
-- manca vale la sede del destinatario). Script idempotente: su un DB che ha già la colonna
-- e la FK non fa nulla.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF COL_LENGTH('dbo.tblMagazziniDdt', 'IdDestinazione') IS NULL
	ALTER TABLE dbo.tblMagazziniDdt ADD IdDestinazione CHAR(16) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblMagazziniDdt_tblSedi_IdDestinazione')
	ALTER TABLE dbo.tblMagazziniDdt WITH CHECK ADD CONSTRAINT FK_tblMagazziniDdt_tblSedi_IdDestinazione FOREIGN KEY (IdDestinazione) REFERENCES dbo.tblSedi (Id);
GO
