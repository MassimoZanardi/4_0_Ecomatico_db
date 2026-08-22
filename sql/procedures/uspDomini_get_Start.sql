CREATE   PROCEDURE [dbo].[uspDomini_get_Start]
    @Codice CHAR(5) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        -- Validazione parametro
        SET @Codice = NULLIF(LTRIM(RTRIM(@Codice)), '');
        IF @Codice IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Codice non può essere vuoto';
            GOTO BRANCH_END;
        END

        -- Restituisce i dati di avvio del dominio identificato dal codice
        -- TOP 1: Codice non è PK, potrebbero esistere più righe
        SELECT TOP 1
            Riferimento,
            [Url],
            Logo,
            Codice,
            IsStart = CAST(IIF(Logo IS NULL, 0, 1) AS BIT)
        FROM
            dbo.tblDomini
        WHERE
            Codice = @Codice
            AND Lock = 0;   -- solo domini attivi

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
