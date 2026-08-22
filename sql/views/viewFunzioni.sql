
CREATE VIEW [dbo].[viewFunzioni]
WITH SCHEMABINDING
AS
SELECT
	f.Id,
	IdModulo = m.Id,
	IdPagina = p.Id,
	f.Nome,
	f.Attiva,
	f.[Master],
	ModuloNome = m.Nome,
	ModuloAttivo = m.Attivo,
	PaginaNome = p.Nome,
	PaginaUrl = p.[Url]
FROM
	dbo.tblFunzioni f
	INNER JOIN dbo.tblModuliFunzioni mf ON f.Id = mf.IdFunzione -- ✅ confermato
	INNER JOIN dbo.tblModuli m ON mf.Id = m.Id -- ✅ confermato
	LEFT JOIN dbo.tblPagine p ON f.Id = p.IdFunzione;
