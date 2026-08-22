


-- select * from viewOsepe

CREATE VIEW [dbo].[viewOsepe]
AS

SELECT 
	n.Id,
	n.Tipo,
	IdAziendaInterna = COALESCE(s.IdAziendaInterna, p.IdSede, o.IdSede),
	Nome = COALESCE(s.NomeCompleto + ' ' + s.IndirizzoCompleto, p.Cognome + ' ' + p.Nome, p.Nome, o.Nome),
	Lock = COALESCE(s.Lock, p.Lock, o.Lock)
FROM
	tblOsepe n LEFT OUTER JOIN
	tblSedi s ON n.Id = s.Id LEFT OUTER JOIN
	tblPersone p ON n.Id = p.Id  LEFT OUTER JOIN
	tblOggetti o ON n.Id = o.Id
