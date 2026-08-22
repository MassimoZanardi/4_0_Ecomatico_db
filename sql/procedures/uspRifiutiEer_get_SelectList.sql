CREATE   PROCEDURE [dbo].[uspRifiutiEer_get_SelectList]
    @IdSelected CHAR(6)     = NULL,
    @Search     VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
        SET @Search     = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

        ;WITH cte AS (
            -- Opzione vuota sempre in cima
            SELECT
                Id       = CAST(REPLICATE('0', 6) AS CHAR(6)),
                [Text]   = CAST('(Selezionare)' AS VARCHAR(200)),
                Selected = CAST(IIF(@IdSelected IS NULL, 1, 0) AS BIT),
                Pos      = 0

            UNION ALL  -- EER selezionato: sempre presente, indipendentemente da @Search

            SELECT
                Id,
                [Text]   = Nome + IIF(Pericoloso = 1, '*', '') + ' - ' + Descrizione,
                Selected = CAST(1 AS BIT),
                Pos      = 1
            FROM dbo.tblRifiutiEer
            WHERE Id = @IdSelected

            UNION ALL  -- altri risultati filtrabili

            SELECT
                Id,
                [Text]   = Nome + IIF(Pericoloso = 1, '*', '') + ' - ' + Descrizione,
                Selected = CAST(0 AS BIT),
                Pos      = 2
            FROM dbo.tblRifiutiEer
            WHERE (@IdSelected IS NULL OR Id <> @IdSelected)
              AND (@Search IS NULL OR (Nome + IIF(Pericoloso = 1, '*', '') + ' - ' + Descrizione) LIKE '%' + @Search + '%')
        )
        SELECT TOP 20 Id, [Text], Selected
        FROM   cte
        ORDER BY Pos, [Text]
        OPTION (RECOMPILE);

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF;
    IF @returnValue < 0
    BEGIN
        SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
        THROW 50001, @returnMessage, 1
    END

END;
