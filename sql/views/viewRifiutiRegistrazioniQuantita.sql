

CREATE   VIEW [dbo].[viewRifiutiRegistrazioniQuantita]
AS

SELECT
    r.Id,
    r.IdMovimento,
    r.Operazione,
    m.Quantita,
    r.QuantitaVerificata,
    QuantitaAssociata = ISNULL(a.Quantita, 0),
    QuantitaResidua   = m.Quantita - ISNULL(a.Quantita, 0),
    r.Lock
FROM
    dbo.tblRifiutiRegistrazioni r
    INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
    LEFT JOIN (
        -- Somma delle quantità associate (figlie) per ogni registrazione padre
        SELECT
            l.Id,
            Quantita = SUM(l.Quantita)
        FROM
            dbo.tblRifiutiRegistrazioniRelazioni l
            INNER JOIN dbo.tblRifiutiRegistrazioni p  ON l.IdParent = p.Id
            INNER JOIN dbo.tblRifiutiMovimenti     mp ON p.IdMovimento = mp.Id
        WHERE
            p.Lock      < 2
            AND mp.Quantita > 0
        GROUP BY
            l.Id
    ) a ON r.Id = a.Id;
