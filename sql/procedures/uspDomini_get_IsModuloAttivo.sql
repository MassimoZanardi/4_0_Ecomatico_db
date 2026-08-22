CREATE   PROCEDURE [dbo].[uspDomini_get_IsModuloAttivo]
    @Id       CHAR(16) = NULL,
    @IdModulo CHAR(3) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        -- Validazione parametri
        SET @Id       = NULLIF(LTRIM(RTRIM(@Id)), '');
        SET @IdModulo = NULLIF(LTRIM(RTRIM(@IdModulo)), '');

        IF @Id IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Id non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @IdModulo IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdModulo non può essere vuoto';
            GOTO BRANCH_END;
        END

        -- Restituisce 1 se il modulo è abilitato sul dominio, 0 altrimenti
        SELECT rtn = CAST(
            CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM   dbo.tblDominiModuli
                    WHERE  Id       = @Id
                      AND  IdModulo = @IdModulo
                ) THEN 1
                ELSE 0
            END
        AS BIT);

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
