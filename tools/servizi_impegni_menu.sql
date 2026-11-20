SET NOCOUNT ON;

-- Servizi > Impegni: voce di menu sotto "Calendario" (funzione SRV, nessuna funzione nuova).
-- Pagina /servizi/impegni/{giorno|settimana|mese}: la voce apre la vista settimanale (Url 'impegni/settimana',
-- come 'calendario/settimana' del Calendario). Rieseguibile.
-- Eseguito su dev il 2026-11-20. NON ancora eseguito in produzione.

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'SRI')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('SRI', 'SRV', 'Impegni', 'impegni/settimana', NULL);

-- Posizione: subito dopo Calendario (AE1, Pos 0); le voci successive scendono di uno
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AE6')
BEGIN
	UPDATE dbo.tblMenu SET Pos = Pos + 1 WHERE IdParent = 'AE0' AND Pos >= 1;
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AE6', 'AE0', NULL, 'SRI', 1);
END

SELECT m.Id, m.Pos, p.Nome, p.Url, p.IdFunzione
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
WHERE m.IdParent = 'AE0'
ORDER BY m.Pos;
GO
