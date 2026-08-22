CREATE   PROCEDURE [dbo].[uspUtenti_get_TokenReset]
    @Token NVARCHAR(32) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        -- Validazione parametro
        SET @Token = NULLIF(LTRIM(RTRIM(@Token)), '');
        IF @Token IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Token non può essere vuoto';
            GOTO BRANCH_END;
        END

        DECLARE @StatoAttivo NVARCHAR(10) = 'AT'; -- AT = Attivo (tblUtentiStati)

        SELECT
            Id,
            Email
        FROM   dbo.tblUtenti
        WHERE  TokenReset      = @Token COLLATE Latin1_General_CI_AS
          AND  TokenResetScade > GETDATE()
          AND  IdStato         = @StatoAttivo
          AND  Lock            = 0      -- esclude utenti bloccati
          AND (Scadenza IS NULL OR Scadenza >= CAST(GETDATE() AS DATE));

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
