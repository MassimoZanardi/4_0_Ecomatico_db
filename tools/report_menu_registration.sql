-- Report: pagine e voci di menu di Fatturazione > Report (funzione FTT, la stessa delle fatture) e di
-- Rifiuti > Report (funzione RRG, la stessa delle registrazioni). Nessuna tabella e nessuna funzione nuova.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già la registrazione.
SET NOCOUNT ON;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTR')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTR', 'FTT', 'Report', 'report', NULL);

-- La voce è nata come "Fatturato": si chiama "Report", come quella dei rifiuti
UPDATE dbo.tblPagine SET Nome = 'Report', Url = 'report' WHERE Id = 'FTR' AND (Nome <> 'Report' OR ISNULL(Url, '') <> 'report');

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'RRP')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('RRP', 'RRG', 'Report', 'report', NULL);

-- Menu Fatturazione: Fatture clienti, Fatture fornitori, Scadenziario clienti, Scadenziario fornitori,
-- Prima nota, Conti, Banche e casse, Aliquote IVA, Dati fiscali, Report (ultima voce)
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJA')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJA', 'AJ0', NULL, 'FTR', 9);

UPDATE dbo.tblMenu SET Pos = 8 WHERE Id = 'AJ8' AND Pos <> 8;
UPDATE dbo.tblMenu SET Pos = 9 WHERE Id = 'AJA' AND Pos <> 9;

-- Menu Rifiuti: Report in coda, dopo Dichiarazioni MUD
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AFA')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AFA', 'AF0', NULL, 'RRP', 9);
GO
