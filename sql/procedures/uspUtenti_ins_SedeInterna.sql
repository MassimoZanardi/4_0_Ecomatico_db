CREATE   PROCEDURE [dbo].[uspUtenti_ins_SedeInterna]
    @Id         CHAR(16) = NULL,
    @IdSede     CHAR(16) = NULL,
    @IdSessione CHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;
        -- Validazione parametri
        SET @Id         = NULLIF(LTRIM(RTRIM(@Id)), '');
        SET @IdSede     = NULLIF(LTRIM(RTRIM(@IdSede)), '');
        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
        IF @Id IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Id non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @IdSessione IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
            GOTO BRANCH_END;
        END
        -- Controllo permesso sulla funzione (UTE = Gestione Utenti)
        DECLARE @permesso TINYINT;
        EXEC dbo.uspSessione_get_FunzionePermesso
            @Id         = @IdSessione,
            @IdFunzione = 'UTE',
            @Permesso   = @permesso OUTPUT;
        IF 2 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        DECLARE @idDominioSessione CHAR(16);
        SELECT @idDominioSessione = a.IdDominio
        FROM   dbo.tblSessioni s INNER JOIN dbo.tblUtenti a ON a.Id = s.IdUtente
        WHERE  s.Id = @IdSessione;

        -- Titolarità: Admin dello stesso Dominio dell'utente target, oppure Admin di un Dominio Master.
        IF NOT EXISTS (SELECT 1 FROM dbo.tblUtenti WHERE Id = @Id AND IdDominio = @idDominioSessione)
        AND NOT EXISTS (SELECT 1 FROM dbo.tblDomini WHERE Id = @idDominioSessione AND [Master] = 1)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        -- Titolarità sede: la sede interna deve appartenere allo stesso Dominio dell'utente target
        IF NOT EXISTS (
            SELECT 1
            FROM   dbo.tblSedi s
                   INNER JOIN dbo.tblSediInterne si ON s.IdAziendaInterna = si.Id
            WHERE  s.Id = @IdSede AND si.IdDominio = @idDominioSessione
        )
        AND NOT EXISTS (SELECT 1 FROM dbo.tblDomini WHERE Id = @idDominioSessione AND [Master] = 1)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        BEGIN TRANSACTION;
            -- DELETE + INSERT come upsert: garantisce idempotenza
            -- se la sede è già associata all'utente non genera errori di duplicato
            DELETE dbo.tblUtentiSediInterne
            WHERE  Id = @Id AND IdSede = @IdSede;
            INSERT INTO dbo.tblUtentiSediInterne (Id, IdSede)
            VALUES (@Id, @IdSede);
        COMMIT TRANSACTION;
        -- Log FUORI dalla transazione
        EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';
        SELECT @returnValue AS ReturnValue;
    END TRY
    BEGIN CATCH
        THROW;  -- XACT_ABORT ON garantisce il rollback automatico
    END CATCH
    BRANCH_END:
    SET NOCOUNT, XACT_ABORT OFF;
    IF @returnValue < 0
    BEGIN
        SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
        THROW 50001, @returnMessage, 1;
    END
END;
