SET NOCOUNT ON;

-- Magazzino > DDT: nuova voce di menu subito dopo Movimenti (Articoli, Lotti, Movimenti, DDT, Giacenze),
-- sotto la funzione MAG "Gestione". Elenco dei soli movimenti con un DDT emesso, propedeutico alla stampa.
-- tblPagine.Url resta NULL: il link si costruisce dal nome in minuscolo ("/magazzino/ddt").
-- Rieseguibile.

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'MGD')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('MGD', 'MAG', 'DDT', NULL, NULL);

-- Giacenze scende di una posizione per fare spazio a DDT
UPDATE dbo.tblMenu SET Pos = 4 WHERE Id = 'AI4' AND Pos <> 4;

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AI5')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AI5', 'AI0', NULL, 'MGD', 3);

SELECT m.Id, m.Pos, p.Nome, p.IdFunzione
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
WHERE m.IdParent = 'AI0'
ORDER BY m.Pos;
GO
