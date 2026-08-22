

CREATE   VIEW [dbo].[viewRifiutiAutorizzazioni]
AS
SELECT
    a.Id,
    a.IdSede,
    s.IdAziendaInterna,
    a.IdRuolo,
	a.IdTipo,
    a.Numero,
    a.Identificativo,
    a.DataInizio,
    a.DataFine,
    a.Note,
    a.Nessuna,
    a.Disabilitata,
    Ruolo                   = r.Nome,
    s.NomeCompleto,
    s.IndirizzoCompleto,
    s.InternaEsterna,
    SedeDisabilitata        = s.Disabilitata,
    IsEerAssociabili        = r.Eer,
    IsTargheAssociabili     = r.Targhe,
    IsConducentiAssociabili = r.Conducenti,
    IsAttivitaAssociabili   = r.Attivita,
    a.Lock
FROM
    dbo.tblRifiutiAutorizzazioni   a
    INNER JOIN dbo.tblSedi         s ON a.IdSede   = s.Id
    INNER JOIN dbo.tblRifiutiRuoli r ON a.IdRuolo  = r.Id
