CREATE   PROCEDURE [dbo].[uspUtenti_get_PasswordPolicy]
    @Id CHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        -- Validazione parametro
        SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
        IF @Id IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Id non può essere vuoto';
            GOTO BRANCH_END;
        END

        SELECT
            u.PasswordScadenzaGiorni  AS ScadenzaGiorni,
            u.PasswordLunghezzaMinima AS LunghezzaMinima,
            -- Storico hash separati da virgola, ordinati dal più recente
            -- C# usa questa stringa per verificare il riutilizzo password
            p.PasswordPrecedenti,
            u.PasswordPrecedenti AS PasswordPrecedentiNumero
        FROM dbo.tblUtenti u
        OUTER APPLY (
            SELECT STRING_AGG([Password], ',')
                   WITHIN GROUP (ORDER BY [Data] DESC) AS PasswordPrecedenti
            FROM   dbo.tblUtentiPassword
            WHERE  Id = @Id
        ) p
        WHERE u.Id = @Id;

    END TRY
    BEGIN CATCH
        THROW;  -- propaga l'eccezione originale: C# la logga come SqlException inattesa
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF;
    IF @returnValue < 0
    BEGIN
        SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
        THROW 50001, @returnMessage, 1;
    END

END;
