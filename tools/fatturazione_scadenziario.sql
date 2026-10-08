-- Fatturazione > Scadenziario clienti e fornitori: pagine e voci di menu (funzione FTT, la stessa delle
-- fatture). Le tabelle dei pagamenti (tblPagamenti, tblFattureRatePagamenti) sono già create da
-- fatturazione_fatture.sql.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già la registrazione.
SET NOCOUNT ON;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTS')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTS', 'FTT', 'Scadenziario clienti', 'scadenziario-clienti', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTP')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTP', 'FTT', 'Scadenziario fornitori', 'scadenziario-fornitori', NULL);

-- Menu Fatturazione: Fatture clienti, Fatture fornitori, Scadenziario clienti, Scadenziario fornitori, Conti,
-- Banche e casse, Aliquote IVA
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ6')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ6', 'AJ0', NULL, 'FTS', 2);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ7')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ7', 'AJ0', NULL, 'FTP', 3);

UPDATE dbo.tblMenu SET Pos = 4 WHERE Id = 'AJ5' AND Pos <> 4;
UPDATE dbo.tblMenu SET Pos = 5 WHERE Id = 'AJ1' AND Pos <> 5;
UPDATE dbo.tblMenu SET Pos = 6 WHERE Id = 'AJ2' AND Pos <> 6;
GO
