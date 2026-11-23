SET NOCOUNT ON;

-- Servizi > Assegnati: la voce di menu (tblMenu AE2, pagina SRA) apre la vista Bacheca (S7.6, pagina
-- /servizi/assegnati/bacheca) invece dell'Elenco, che resta raggiungibile dal menu della vista. Prima la pagina SRA
-- non aveva Url (indirizzo dal nome della voce: /servizi/assegnati). L'app usa lo stesso valore in
-- SideBar.PaginaAssegnati: va pubblicata insieme. Rieseguibile.
-- Eseguito su dev il 2026-11-23. NON ancora eseguito in produzione.

UPDATE dbo.tblPagine
SET [Url] = 'assegnati/bacheca'
WHERE
	Id = 'SRA'
	AND IdFunzione = 'SRA'
	AND [Url] IS NULL;

SELECT m.Id, m.IdParent, m.Pos, p.Id AS IdPagina, p.Nome, p.[Url], p.IdFunzione
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
WHERE m.Id = 'AE2';
GO
