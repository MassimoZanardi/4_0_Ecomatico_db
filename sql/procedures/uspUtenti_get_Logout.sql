CREATE   PROCEDURE [dbo].[uspUtenti_get_Logout]
    @IdSessione CHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        -- Validazione
        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
        IF @IdSessione IS NULL
        BEGIN
            SET @returnValue   = -1;
            SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
            GOTO BRANCH_END;
        END

        -- Soglia per pulizia sessioni scadute (piggyback cleanup)
        DECLARE @data SMALLDATETIME = DATEADD(HOUR, -24, GETDATE());

        BEGIN TRANSACTION;

            -- Pulizia navigazione: sessione corrente + sessioni scadute
            DELETE dbo.tblUrlNavigazione
            WHERE  IdSessione = @IdSessione
               OR  IdSessione IN (
                       SELECT Id FROM dbo.tblSessioni WHERE [Data] < @data
                   );

            -- Pulizia id cancellati della sessione corrente
            DELETE dbo.tblIdCancellati
            WHERE  IdSessione = @IdSessione;

            -- Raccoglie in una volta sola le sessioni da eliminare:
            -- quella corrente + quelle scadute
            SELECT Id
            INTO   #tSessioni
            FROM   dbo.tblSessioni
            WHERE  Id    = @IdSessione
               OR  [Data] < @data;

            DELETE dbo.tblSessioniFunzioniPermessi
            WHERE  Id IN (SELECT Id FROM #tSessioni);

            DELETE dbo.tblSessioni
            WHERE  Id IN (SELECT Id FROM #tSessioni);

        COMMIT TRANSACTION;

        SELECT @returnValue AS ReturnValue;

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
