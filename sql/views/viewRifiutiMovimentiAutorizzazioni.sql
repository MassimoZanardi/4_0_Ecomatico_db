CREATE VIEW [dbo].[viewRifiutiMovimentiAutorizzazioni]
AS
SELECT
	m.Id,
	IdRegistrazione = r.Id,
	RegistrazioneLock = r.Lock,
	IdFormulario = f.Id,
	FormularioLock = f.Lock,
	IdAutorizzazioneProduttoreDetentore1 = mp1.IdAutorizzazione,
	IdAutorizzazioneDestinatario = md.IdAutorizzazione,
	IdAutorizzazioneTrasportatore1 = mt1.IdAutorizzazione,
	IdAutorizzazioneIntermediario1 = mi1.IdAutorizzazione
FROM
	dbo.tblRifiutiMovimenti m
	LEFT JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
	LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
	LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp1 ON m.Id = mp1.Id AND mp1.Pos = 0
	LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
	LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0
	LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi1 ON m.Id = mi1.Id AND mi1.Pos = 0
