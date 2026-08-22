


CREATE VIEW [dbo].[viewRifiutiMovimentiProduttori]
AS

SELECT
	m.Id,
	IdRegistrazione = r.Id,
	RegistrazioneLock = r.Lock,
	IdFormulario = f.Id,
	FormularioLock = f.Lock,
	IdAutorizzazione = mp.IdAutorizzazione,
	IdSede = a.IdSede,
	Quantita = mp.Quantita,
	mp.Pos,
	s.NomeCompleto,
	s.IndirizzoCompleto
FROM
	tblRifiutiMovimenti m LEFT OUTER JOIN
	tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento LEFT OUTER JOIN
	tblRifiutiFormulari f ON m.Id = f.IdMovimento LEFT OUTER JOIN
	tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id LEFT OUTER JOIN
	tblRifiutiAutorizzazioni a ON mp.IdAutorizzazione = a.Id LEFT OUTER JOIN
	tblSedi s ON a.IdSede = s.Id

