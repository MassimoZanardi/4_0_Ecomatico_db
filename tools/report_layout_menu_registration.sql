-- Report layout: pagina e voce di menu di Impostazioni > Report layout (layout di stampa di DDT e fatture per
-- azienda interna, tblSediReport). Funzione AZI (Aziende interne), la stessa della scheda dell'azienda: nessuna
-- funzione nuova. Voce dopo Utenti, Domini in coda.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già la registrazione.
SET NOCOUNT ON;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'RLY')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('RLY', 'AZI', 'Report layout', 'report-layout', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AZ5')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AZ5', 'AZ0', NULL, 'RLY', 3);

-- Menu Impostazioni: Aziende, Aree, Utenti, Report layout, Domini
UPDATE dbo.tblMenu SET Pos = 3 WHERE Id = 'AZ5' AND Pos <> 3;
UPDATE dbo.tblMenu SET Pos = 4 WHERE Id = 'AZ2' AND Pos <> 4;
GO
