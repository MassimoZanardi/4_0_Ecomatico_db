CREATE   PROCEDURE [dbo].[uspServizi_ins_Osepe]
    @Id         CHAR(16)      = NULL,
    @IdOsepe    CHAR(16)      = NULL,
    @Quantita   DECIMAL(18,4) = NULL,
    @IdSessione CHAR(16)      = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        -- Validazione parametri
        SET @Id         = NULLIF(LTRIM(RTRIM(@Id)), '');
        SET @IdOsepe    = NULLIF(LTRIM(RTRIM(@IdOsepe)), '');
        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

        IF @Id IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Id non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @IdOsepe IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdOsepe non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @Quantita IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Quantita non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @IdSessione IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
            GOTO BRANCH_END;
        END

        -- Controllo permesso sulla funzione (SRV = Gestione Servizi)
        DECLARE @permesso TINYINT;
        EXEC dbo.uspSessione_get_FunzionePermesso
            @Id         = @IdSessione,
            @IdFunzione = 'SRV',
            @Permesso   = @permesso OUTPUT;

        IF 2 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (
            SELECT 1
            FROM   dbo.tblServizi   s
                   INNER JOIN dbo.tblEventi    e ON s.IdEvento     = e.Id
                   INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
                   INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
                       ON c.IdSede = i.Id
            WHERE  s.Id = @Id
        )
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        BEGIN TRANSACTION;
            -- Upsert: DELETE + INSERT per evitare duplicati su PK (Id, IdOsepe)
            DELETE dbo.tblServiziOsepe
            WHERE  Id      = @Id
              AND  IdOsepe = @IdOsepe;

            INSERT INTO dbo.tblServiziOsepe (Id, IdOsepe, Quantita)
            VALUES (@Id, @IdOsepe, @Quantita);
        COMMIT TRANSACTION;

        -- Log FUORI dalla transazione: uspId_upd gestisce la propria transazione
        EXEC dbo.uspId_upd
            @Id         = @Id,
            @IdSessione = @IdSessione,
            @Operazione = 'U';

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
