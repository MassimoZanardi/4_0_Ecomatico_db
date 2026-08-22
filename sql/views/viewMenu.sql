

-- select * from viewMenu order by Id, Pos

CREATE OR ALTER VIEW [dbo].[viewMenu]
AS
SELECT
	m.Id,
	m.IdParent,
	m.IdArea,
	m.IdPagina,
	p.IdFunzione,
	Area = a.Nome,
	Pagina = p.Nome,
	Funzione = f.Nome,
	m.Pos
FROM
	tblMenu m LEFT OUTER JOIN
	tblPagineAree a ON m.IdArea = a.Id LEFT OUTER JOIN
	tblPagine p ON m.IdPagina = p.Id LEFT OUTER JOIN
	tblFunzioni f ON p.IdFunzione = f.Id

