CREATE   PROCEDURE [dbo].[uspDomini_del_Modulo]
    @Id         CHAR(16) = NULL,
    @IdModulo   CHAR(3) = NULL,
    @IdSessione CHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        -- Validazione parametri
        SET @Id         = NULLIF(LTRIM(RTRIM(@Id)),         '');
        SET @IdModulo   = NULLIF(LTRIM(RTRIM(@IdModulo)),   '');
        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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
        IF @IdSessione IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
            GOTO BRANCH_END;
        END

        -- Controllo permesso: solo Admin di dominio Master
        IF NOT EXISTS (
            SELECT 1
            FROM   dbo.tblSessioni e
                   INNER JOIN dbo.tblUtenti ut ON e.IdUtente   = ut.Id
                   INNER JOIN dbo.tblDomini d  ON ut.IdDominio = d.Id
            WHERE  e.Id       = @IdSessione
              AND  d.[Master] = 1
        )
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        -- I moduli di sistema BAS e IMP sono sempre presenti e non rimovibili
        IF @IdModulo IN ('BAS', 'IMP')
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il modulo di sistema non può essere rimosso';
            GOTO BRANCH_END;
        END

        -- Blocca la rimozione se un altro modulo ancora attivo sul dominio lo richiede
        IF EXISTS (
            SELECT 1
            FROM   dbo.tblModuliRelazioni r
                   INNER JOIN dbo.tblDominiModuli dm ON dm.IdModulo = r.IdParent
            WHERE  r.Id  = @IdModulo
              AND  dm.Id = @Id
        )
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il modulo è richiesto da un altro modulo ancora attivo sul dominio';
            GOTO BRANCH_END;
        END

        BEGIN TRANSACTION;
            DELETE dbo.tblDominiModuli
            WHERE  Id       = @Id
              AND  IdModulo = @IdModulo;

            -- @@ROWCOUNT mancante in origine: senza questo controllo la SP "riesce"
            -- silenziosamente anche se la combinazione Id/IdModulo non esiste.
            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @returnValue = -1; SET @returnMessage = 'Modulo non trovato o già rimosso dal dominio';
                GOTO BRANCH_END;
            END
        COMMIT TRANSACTION;

        -- Log FUORI dalla transazione
        EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

        SELECT @returnValue AS ReturnValue;

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
