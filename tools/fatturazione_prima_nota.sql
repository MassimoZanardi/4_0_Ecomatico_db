-- Fatturazione > Prima nota: pagina e voce di menu (funzione FTT, la stessa di fatture e scadenziario).
-- Non servono tabelle nuove: i movimenti sono i pagamenti registrati dallo scadenziario (tblPagamenti).
-- Script idempotente: rieseguibile senza effetti su un DB che ha già la registrazione.
SET NOCOUNT ON;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTN')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTN', 'FTT', 'Prima nota', 'prima-nota', NULL);

-- Menu Fatturazione: Fatture clienti, Fatture fornitori, Scadenziario clienti, Scadenziario fornitori,
-- Prima nota, Conti, Banche e casse, Aliquote IVA, Dati fiscali
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ9')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ9', 'AJ0', NULL, 'FTN', 4);

UPDATE dbo.tblMenu SET Pos = 4 WHERE Id = 'AJ9' AND Pos <> 4;
UPDATE dbo.tblMenu SET Pos = 5 WHERE Id = 'AJ5' AND Pos <> 5;
UPDATE dbo.tblMenu SET Pos = 6 WHERE Id = 'AJ1' AND Pos <> 6;
UPDATE dbo.tblMenu SET Pos = 7 WHERE Id = 'AJ2' AND Pos <> 7;
UPDATE dbo.tblMenu SET Pos = 8 WHERE Id = 'AJ8' AND Pos <> 8;
GO
