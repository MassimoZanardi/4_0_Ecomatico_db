CREATE   VIEW [dbo].[viewEventi]
WITH SCHEMABINDING
AS
SELECT
    e.Id,
    e.IdTipo,
    e.IdCalendario,
    c.IdSede,
    s.IdAziendaInterna,
    e.IdStato,
    Stato             = t.Nome,
    e.[Data],
    e.InGiornata,
    Ricorre           = CAST(IIF(r.Id IS NULL, 0, 1) AS BIT),
    e.AvvisoAnticipo,
    Avviso            = CAST(IIF(e.AvvisoAnticipo IS NULL, 0, 1) AS BIT),
    AvvisoTesto       = e.Avviso,
    e.Etichette,
    e.Email,
    r.IdIntervallo,
    r.Frequenza,
    r.DataFine,
    r.Ripetizioni,
    r.Relativo,
    Eccezione         = CAST(IIF(z.IdEvento IS NULL, 0, 1) AS BIT),
    IdEventoEccezione = z.IdEvento,
    IdEccezione       = z.Id,
    e.Lock
FROM
    dbo.tblEventi               e
    INNER JOIN dbo.tblEventiStati        t  ON e.IdStato      = t.Id
    INNER JOIN dbo.tblCalendari          c  ON e.IdCalendario = c.Id
    INNER JOIN dbo.tblSedi               s  ON c.IdSede       = s.Id
    LEFT  JOIN dbo.tblRicorrenze         r  ON e.Id           = r.Id
    LEFT  JOIN dbo.tblRicorrenzeEccezioni z  ON e.Id          = z.IdEvento
                                           AND z.Lock         = 0;
