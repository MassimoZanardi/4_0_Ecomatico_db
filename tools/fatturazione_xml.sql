-- Fatturazione > Fatture clienti > Genera file XML (fattura elettronica): colonne che tracciano la generazione.
-- tblFatture.DataXml = quando è stato generato l'ultimo file della fattura; ProgressivoXml = progressivo del
-- file (5 caratteri, quello del nome del file e del blocco DatiTrasmissione).
-- tblFattureDatiFiscali.ProgressivoInvio = ultimo progressivo assegnato per l'azienda.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già le colonne.
SET NOCOUNT ON;
GO
IF COL_LENGTH('dbo.tblFatture', 'DataXml') IS NULL
	ALTER TABLE dbo.tblFatture ADD DataXml SMALLDATETIME NULL;
IF COL_LENGTH('dbo.tblFatture', 'ProgressivoXml') IS NULL
	ALTER TABLE dbo.tblFatture ADD ProgressivoXml VARCHAR(5) NULL;
IF COL_LENGTH('dbo.tblFattureDatiFiscali', 'ProgressivoInvio') IS NULL
	ALTER TABLE dbo.tblFattureDatiFiscali ADD ProgressivoInvio INT NULL;
GO
