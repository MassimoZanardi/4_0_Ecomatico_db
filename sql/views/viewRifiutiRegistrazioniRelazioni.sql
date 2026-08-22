

CREATE OR ALTER VIEW [dbo].[viewRifiutiRegistrazioniRelazioni]

AS

SELECT
	l.Id,
	l.IdParent,
	m.IdOperazione,
	IdOperazioneParent = mp.IdOperazione,
	r.Operazione,
	l.Quantita,
	l.Pos,
	r.[Data],
	DataParent = rp.[Data],
	r.Numero,
	NumeroParent = rp.Numero,
	m.IdEer,
	IdEerParent = mp.IdEer,
	m.IdStatoFisico,
	IdStatoFisicoParent = mp.IdStatoFisico,
	m.IdUnitaMisura,
	IdUnitaMisuraParent = mp.IdUnitaMisura,
	r.Lock
FROM
	dbo.tblRifiutiRegistrazioniRelazioni l
	INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
	INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
	INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
	INNER JOIN dbo.tblRifiutiMovimenti mp ON rp.IdMovimento = mp.Id;
