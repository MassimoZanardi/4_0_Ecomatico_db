CREATE   PROCEDURE [dbo].[uspScadenze_del]
    @Id                    CHAR(16) = NULL,
    @IdSessione            CHAR(16) = NULL,
    @Reset                 BIT      = 0,
    @IdEvento              CHAR(16) = NULL,
    @Data                  SMALLDATETIME = NULL,
    @OccorrenzaESuccessive BIT      = 0
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @Id         = NULLIF(LTRIM(RTRIM(@Id)),         '');
        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

        IF @Id IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Id non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @IdSessione IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
            GOTO BRANCH_END;
        END

        DECLARE @permesso TINYINT;
        EXEC dbo.uspSessione_get_FunzionePermesso
            @Id         = @IdSessione,
            @IdFunzione = 'SCD',
            @Permesso   = @permesso OUTPUT;

        IF 2 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        -- Idempotenza: verifica prima di tutto se la scadenza esiste, indipendentemente dalla
        -- titolarità sottostante — mai esistita o già cancellata (es. doppio invio della
        -- richiesta di annullamento lato UI) viene trattata come cancellazione già avvenuta con
        -- successo, non come errore.
        IF NOT EXISTS (SELECT 1 FROM dbo.tblScadenze WHERE Id = @Id)
        BEGIN
            SET @returnValue = 0;
        END
        ELSE
        BEGIN

        IF NOT EXISTS (
            SELECT 1
            FROM   dbo.tblScadenze  s
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

        DECLARE @lock INT;
        SELECT @lock = e.Lock
        FROM   dbo.tblScadenze s
               INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
        WHERE  s.Id = @Id;

        IF @lock = 0
        BEGIN
            BEGIN TRANSACTION;

                IF @Reset = 1
                    DELETE dbo.tblIdCancellati WHERE IdSessione = @IdSessione;
                ELSE
                    DELETE dbo.tblIdCancellati WHERE Id = @Id;

                IF @IdEvento IS NOT NULL
                BEGIN
                    IF @OccorrenzaESuccessive = 0
                    BEGIN
                        INSERT INTO dbo.tblRicorrenzeEccezioni (Id, [Data], Lock)
                        VALUES (@IdEvento, @Data, 0);

                        INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data], DataEccezione)
                        VALUES (@IdEvento, @IdSessione, GETDATE(), @Data);
                    END
                    ELSE
                    BEGIN
                        DECLARE @dataFineParent SMALLDATETIME =
                            DATEADD(MINUTE, 59, DATEADD(HOUR, 23,
                                DATEADD(DAY, DATEDIFF(DAY, 0, @Data), -1)));

                        UPDATE dbo.tblRicorrenze
                        SET    DataFine    = @dataFineParent,
                               Ripetizioni = 0
                        WHERE  Id = @IdEvento;

                        DELETE dbo.tblRicorrenzeEccezioni
                        WHERE  Id     = @IdEvento
                          AND  [Data] > @dataFineParent;
                    END
                END
                ELSE
                BEGIN
                    UPDATE e
                    SET    Lock = 4
                    FROM   dbo.tblScadenze s
                           INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
                    WHERE  s.Id = @Id AND e.Lock = 0;

                    UPDATE e
                    SET    Lock = 4
                    FROM   dbo.tblScadenze               s
                           INNER JOIN dbo.tblRicorrenzeEccezioni e ON s.IdEvento = e.Id
                    WHERE  s.Id = @Id AND e.Lock = 0;

                    INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
                    VALUES (@Id, @IdSessione, GETDATE());
                END

            COMMIT TRANSACTION;

            EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
        END
        ELSE IF @lock = 2
        BEGIN
            SELECT @IdEvento = IdEvento FROM dbo.tblScadenze WHERE Id = @Id;

            BEGIN TRANSACTION;
                DELETE dbo.tblEventiProprieta      WHERE Id        = @IdEvento;
                DELETE dbo.tblRicorrenzeEccezioni  WHERE IdEvento  = @IdEvento;
                DELETE dbo.tblEventiEtichette      WHERE Id        = @IdEvento;
                DELETE dbo.tblRicorrenze           WHERE Id        = @IdEvento;
                DELETE dbo.tblScadenzeOsepe        WHERE Id        = @Id;
                DELETE dbo.tblScadenze             WHERE Id        = @Id;
                DELETE dbo.tblServiziOsepe         WHERE Id IN (
                    SELECT Id FROM dbo.tblServizi WHERE IdEvento = @IdEvento);
                DELETE dbo.tblServizi              WHERE IdEvento  = @IdEvento;
                DELETE dbo.tblEventi               WHERE Id        = @IdEvento;
                DELETE dbo.tblIdCancellati         WHERE Id IN (@Id, @IdEvento);
                DELETE dbo.tblIdLog                WHERE Id IN (@Id, @IdEvento);
                DELETE dbo.tblId                   WHERE Id IN (@Id, @IdEvento);
            COMMIT TRANSACTION;
        END
        ELSE
        BEGIN
            SET @returnValue   = -1;
            SET @returnMessage = 'La scadenza è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
            GOTO BRANCH_END;
        END

        END

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
        THROW 50001, @returnMessage, 1;
    END

END;


