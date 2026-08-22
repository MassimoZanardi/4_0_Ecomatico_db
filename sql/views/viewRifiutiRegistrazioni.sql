

CREATE VIEW [dbo].[viewRifiutiRegistrazioni]
AS
SELECT
	r.Id,
	r.IdMovimento,
	m.IdRegistro,
	IdFormulario = f.Id,
	m.IdOperazione,
	m.IdEer,
	m.IdStatoFisico,
	m.IdAttivita,
	m.IdSedeProduttoreDetentore,
	m.IdSedeTrasportatore1,
	m.IdSedeDestinatario,
	m.IdSedeIntermediario1,
	UtenteNote = m.Note,
	r.Operazione,
	r.[Data],
	r.Numero,
	m.Quantita,
	r.QuantitaVerificata,
	m.IdUnitaMisura,
	r.Note,
	r.Etichette,
	IsFormulario = CAST(IIF(op.Id IS NOT NULL, 1, 0) AS BIT),
	FormularioNumero = m.FormularioNumero,
	FormularioDataEmissione = f.DataEmissione,
	r.Lock
FROM
	dbo.tblRifiutiRegistrazioni r
	INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
	INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
	LEFT JOIN dbo.tblRifiutiOperazioniFormulario op ON o.Id = op.Id
	LEFT JOIN dbo.tblRifiutiFormulari f ON r.IdMovimento = f.IdMovimento
