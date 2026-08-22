-- Step 2: ora l'ALTER e' sbloccato
CREATE   FUNCTION [dbo].[ufnFunzioni_get_PermessoByUtente]
(
    @IdFunzione CHAR(3),
    @IdUtente   CHAR(16)
)
RETURNS TINYINT
WITH SCHEMABINDING
AS
BEGIN
    IF @IdFunzione IS NULL OR @IdUtente IS NULL
        RETURN 0;

    RETURN
    (
        SELECT TOP (1)
            Permesso
        FROM
        (
            -- Utenti non amministratori
            SELECT Permesso = uf.IdPermesso
            FROM dbo.tblUtenti AS u
            INNER JOIN dbo.tblUtentiFunzioni AS uf
                ON u.Id = uf.Id
            INNER JOIN dbo.tblFunzioni AS f
                ON uf.IdFunzione = f.Id
            WHERE u.Id = @IdUtente
              AND u.IdRuolo <> 'AD'
              AND uf.IdFunzione = @IdFunzione
              AND f.Attiva = 1

            UNION ALL

            -- Amministratori
            SELECT Permesso = CONVERT(TINYINT, 2)
            FROM dbo.tblUtenti AS u
            INNER JOIN dbo.tblDominiModuli AS dm
                ON u.IdDominio = dm.Id
            INNER JOIN dbo.tblModuliFunzioni AS mf
                ON dm.IdModulo = mf.Id
            INNER JOIN dbo.tblFunzioni AS f
                ON mf.IdFunzione = f.Id
            WHERE u.Id = @IdUtente
              AND u.IdRuolo = 'AD'
              AND f.Id = @IdFunzione
              AND f.[Master] = 0
              AND f.Attiva = 1

            UNION ALL

            -- Amministratori Master
            SELECT Permesso = CONVERT(TINYINT, 2)
            FROM dbo.tblUtenti AS u
            INNER JOIN dbo.tblDomini AS d
                ON u.IdDominio = d.Id
            INNER JOIN dbo.tblFunzioni AS f
                ON f.Id = @IdFunzione
            WHERE u.Id = @IdUtente
              AND u.IdRuolo = 'AD'
              AND d.[Master] = 1
              AND f.Attiva = 1

            UNION ALL

            SELECT Permesso = CONVERT(TINYINT, 0)
        ) AS t
        ORDER BY Permesso DESC
    );
END;
