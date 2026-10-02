SET NOCOUNT ON;

-- EoW > Registrazioni (/eow/registrazioni): elenco delle registrazioni M con le allocazioni sui lotti.
-- Stessa funzione EOW delle altre pagine del modulo (nessuna nuova riga in tblFunzioni/tblModuliFunzioni).
-- Posizione richiesta dall'utente: sotto Lotti.
-- Prima: Lotti(0), Magazzini(1), Allocazioni(2), Giacenze(3)
-- Dopo:  Lotti(0), Registrazioni(1), Magazzini(2), Allocazioni(3), Giacenze(4)

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'EWR')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('EWR', 'EOW', 'Registrazioni', NULL, NULL);

UPDATE dbo.tblMenu
SET Pos = CASE Id WHEN 'AH2' THEN 2 WHEN 'AH3' THEN 3 WHEN 'AH4' THEN 4 END
WHERE Id IN ('AH2', 'AH3', 'AH4');

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AH5')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AH5', 'AH0', NULL, 'EWR', 1);
