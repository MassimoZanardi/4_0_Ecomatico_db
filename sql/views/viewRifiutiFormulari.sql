





-- select * from viewRifiutiFormulari

CREATE VIEW [dbo].[viewRifiutiFormulari]

AS

SELECT
	f.Id,
	f.IdMovimento,
	IdRegistrazione = r.Id,
	m.IdRegistro,
	m.IdOperazione,
	m.IdEer,
	m.IdStatoFisico,
	m.IdAttivita,
	m.IdSedeProduttoreDetentore,
	m.IdSedeTrasportatore1,
	m.IdSedeDestinatario,
	m.IdSedeIntermediario1,
	UtenteNote = m.Note,
	Numero = m.FormularioNumero,
	f.DataEmissione,
	m.IdUnitaMisura,
	f.IdAdr,
	f.IdImballo,
	f.ColliNumero,
	m.Quantita,
	f.Percorso,
	f.Note,
	f.Etichette,
	Operazione = o.Operazione,
	RegistrazioneNumero = r.Numero,
	RegistrazioneData = r.[Data],
	RegistrazioneLock = r.Lock,
	f.Lock
FROM
	tblRifiutiFormulari f INNER JOIN
	tblRifiutiMovimenti m ON f.IdMovimento = m.id INNER JOIN
	tblRifiutiOperazioni o ON m.IdOperazione = o.Id LEFT OUTER JOIN
	tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento

