


CREATE VIEW [dbo].[viewRifiutiMovimentiIntermediari]
AS

SELECT
	m.Id,
	IdRegistrazione = r.Id,
	RegistrazioneLock = r.Lock,
	IdFormulario = f.Id,
	FormularioLock = f.Lock,
	mi.idAutorizzazione,
	mi.Pos,
	s.NomeCompleto,
	s.IndirizzoCompleto
FROM
	tblRifiutiMovimenti m LEFT OUTER JOIN
	tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento LEFT OUTER JOIN
	tblRifiutiFormulari f ON m.Id = f.IdMovimento LEFT OUTER JOIN
	tblRifiutiMovimentiIntermediari mi ON m.Id = mi.Id LEFT OUTER JOIN
	tblRifiutiAutorizzazioni a ON mi.IdAutorizzazione = a.Id LEFT OUTER JOIN
	tblSedi s ON a.IdSede = s.Id

