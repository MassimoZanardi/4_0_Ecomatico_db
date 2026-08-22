CREATE   PROCEDURE [dbo].[uspComuni_get_SelectList]
    @IdSelected CHAR(6) = NULL,
    @Search     VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        -- Normalizza: NULL → '000000' (nessuna selezione)
        SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), REPLICATE('0', 6));
        SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), '');

        WITH cte AS (
            -- Opzione vuota sempre in cima
            SELECT
                Id       = CAST('000000' AS CHAR(6)),
                [Text]   = CAST('(Selezionare)' AS VARCHAR(100)),
                Selected = CAST(0 AS BIT),
                Pos      = 0

            UNION ALL   -- rami mutualmente esclusivi per Id e Pos

            -- Comune selezionato: appare sempre
            SELECT
                c.Id,
                [Text]   = c.Nome + ' (' + ISNULL(p.Nome, '') + ' - ' + ISNULL(p.Sigla, '') + ')',
                Selected = CAST(1 AS BIT),
                Pos      = 1
            FROM
                dbo.tblComuni   c
                LEFT JOIN dbo.tblProvince p ON c.IdProvincia = p.Id
            WHERE
                c.Id = @IdSelected
                AND c.Id <> REPLICATE('0', 6)   -- esclude il caso nessuna selezione

            UNION ALL

            -- Altri comuni: filtrati per @Search o tutti se NULL
            SELECT
                c.Id,
                [Text]   = c.Nome + ' (' + ISNULL(p.Nome, '') + ' - ' + ISNULL(p.Sigla, '') + ')',
                Selected = CAST(0 AS BIT),
                Pos      = 2
            FROM
                dbo.tblComuni   c
                LEFT JOIN dbo.tblProvince p ON c.IdProvincia = p.Id
            WHERE
                c.Id <> @IdSelected
                AND (@Search IS NULL
                     OR c.Nome LIKE '%' + @Search + '%'
                     OR p.Nome LIKE '%' + @Search + '%')
        )
        SELECT TOP 10
            Id,
            [Text],
            Selected
        FROM   cte
        ORDER BY Pos, [Text]
        OPTION (RECOMPILE);

    END TRY
    BEGIN CATCH
        THROW;  -- propaga l'eccezione originale: C# la logga come SqlException inattesa
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF;
    IF @returnValue < 0
    BEGIN
        SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
        THROW 50001, @returnMessage, 1
    END

END;
