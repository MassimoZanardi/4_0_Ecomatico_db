CREATE   VIEW [dbo].[viewDomini]
WITH SCHEMABINDING
AS
SELECT
    d.Id,
    d.IdStato,
    d.Registrazione,
    d.Scadenza,
    d.ScadenzaAuto,
    d.Nome,
    d.Riferimento,
    d.[Master],
    d.UtentiMax,
    d.AziendeMax,
    d.SediMax,
    d.ServiziMax,
    d.RegistriMax,
    d.Codice,
    d.Logo,
    d.[Url],
    IsStart             = CAST(IIF(d.Logo IS NULL, 0, 1) AS BIT),
    UtenteMaster        = um.Email,
    UltimoAccessoData   = ua.[Data],
    UltimoAccessoUtente = ua.Email,
    d.Lock
FROM
    dbo.tblDomini d
    -- Email dell'utente Master del dominio
    OUTER APPLY (
        SELECT TOP 1 u.Email
        FROM   dbo.tblUtenti u
        WHERE  u.IdDominio = d.Id
          AND  u.[Master]  = 1
    ) um
    -- Ultimo accesso di un utente non-Master del dominio
    -- JOIN su tblDomini rimossa: o.Id = d.Id quindi o.[Master] = d.[Master]
    OUTER APPLY (
        SELECT TOP 1 e.[Data], u.Email
        FROM   dbo.tblUtentiLogin e
               INNER JOIN dbo.tblUtenti u ON e.Id = u.Id
        WHERE  u.IdDominio = d.Id
          AND  u.[Master]  = 0
          AND  d.[Master]  = 0
        ORDER BY e.[Data] DESC
    ) ua;
