CREATE   PROCEDURE [dbo].[uspCalendari_ins]
    @IdModulo   CHAR(3) = NULL,
    @IdSessione CHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnId      CHAR(16)      = NULL;
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
        SET @IdModulo   = NULLIF(LTRIM(RTRIM(@IdModulo)),   '');

        IF @IdSessione IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @IdModulo IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdModulo non può essere vuoto';
            GOTO BRANCH_END;
        END

        -- Controllo permesso sulla funzione (CLD = Gestione Calendari)
        DECLARE @permesso TINYINT;
        EXEC dbo.uspSessione_get_FunzionePermesso
            @Id         = @IdSessione,
            @IdFunzione = 'CLD',
            @Permesso   = @permesso OUTPUT;

        IF 2 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        -- Controllo permesso sul modulo
        IF dbo.ufnModuli_get_IsAttivoBySessione(@IdModulo, @IdSessione) = 0
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        -- Legge la sede dalla sessione corrente
        DECLARE @idSede CHAR(16);
        SELECT @idSede = IdSede FROM dbo.tblSessioni WHERE Id = @IdSessione;

        IF @idSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Selezionare la sede';
            GOTO BRANCH_END;
        END

        -- Verifica limite massimo di calendari per sede e modulo
        IF 50 <= (
            SELECT COUNT(*)
            FROM   dbo.tblCalendari
            WHERE  IdSede   = @idSede
              AND  IdModulo = @IdModulo
              AND  Lock     = 0
        )
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'È stato raggiunto il limite massimo di calendari inseribili';
            GOTO BRANCH_END;
        END

        -- Genera il nuovo Id FUORI dalla transazione
        EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

        BEGIN TRANSACTION;
            -- Crea il calendario in bozza (Lock = 2) associato alla sede e al modulo
            INSERT INTO dbo.tblCalendari (Id, IdSede, IdModulo, Lock)
            VALUES (@returnId, @idSede, UPPER(@IdModulo), 2);
        COMMIT TRANSACTION;

        SELECT @returnId AS Id;

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
