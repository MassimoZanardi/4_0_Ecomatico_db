

CREATE VIEW [dbo].[viewUtenti]
AS
SELECT
    u.Id,
    u.IdDominio,
    u.IdStato,
    u.IdRuolo,
    u.Email,
    up.[Password],
    up.[Data]                        AS PasswordData,
    ISNULL(up.Temporanea, 0)         AS PasswordTemporanea,
    u.Scadenza,
    u.[Master],
    s.Nome                           AS Stato,
    d.Nome                           AS Dominio,
    d.[Master]                       AS DominioMaster,
    d.IdStato                        AS DominioIdStato,
    d.Scadenza                       AS DominioScadenza,
    d.Codice                         AS DominioCodice,
    ur.Nome                          AS Ruolo,
    u.PasswordPrecedenti,
    u.PasswordScadenzaGiorni,
    u.PasswordLunghezzaMinima,
    u.[Lock]                         
FROM
    dbo.tblUtenti u
    LEFT JOIN dbo.tblDomini       d  ON u.IdDominio = d.Id
    LEFT JOIN dbo.tblUtentiStati  s  ON u.IdStato   = s.Id
    LEFT JOIN dbo.tblUtentiRuoli  ur ON u.IdRuolo   = ur.Id
    OUTER APPLY (
        SELECT TOP 1
            [Password],
            [Data],
            Temporanea
        FROM dbo.tblUtentiPassword p
        WHERE p.Id = u.Id
        ORDER BY p.[Data] DESC
    ) up;
