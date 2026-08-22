
CREATE VIEW [dbo].[viewRifiutiMovimentiTrasportatori]
AS

SELECT
	m.Id,
	IdRegistrazione = r.Id,
	RegistrazioneLock = r.Lock,
	IdFormulario = f.Id,
	FormularioLock = f.Lock,
	mt.IdAutorizzazione,
	IdTipo = mt.IdTipo,
	TargaMotrice = mt.TargaMotrice,
	TargaRimorchio = mt.TargaRimorchio,
	Conducente = mt.Conducente,
	IdentificativoTrenoNave = mt.IdentificativoTrenoNave,
	IdentificativoTrenoCarro = mt.IdentificativoTrenoCarro,
	[Data] = mt.[Data],
	mt.Pos,
	s.NomeCompleto,
	s.IndirizzoCompleto
FROM
	tblRifiutiMovimenti m LEFT OUTER JOIN
	tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento LEFT OUTER JOIN
	tblRifiutiFormulari f ON m.Id = f.IdMovimento LEFT OUTER JOIN
	tblRifiutiMovimentitrasportatori mt ON m.Id = mt.Id LEFT OUTER JOIN
	tblRifiutiAutorizzazioni a ON mt.IdAutorizzazione = a.Id LEFT OUTER JOIN
	tblSedi s ON a.IdSede = s.Id

