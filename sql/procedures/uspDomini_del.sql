CREATE   PROCEDURE [dbo].[uspDomini_del]
    @Id         CHAR(16) = NULL,
    @IdSessione CHAR(16) = NULL,
    @Reset      BIT      = 0
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        -- Validazione parametri
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

        -- Controllo permesso: solo Admin di dominio Master può cancellare domini
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

        -- Il dominio Master non può essere cancellato
        IF EXISTS (SELECT 1 FROM dbo.tblDomini WHERE Id = @Id AND [Master] = 1)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il dominio Master non può essere cancellato';
            GOTO BRANCH_END;
        END

        DECLARE @lock INT = (SELECT Lock FROM dbo.tblDomini WHERE Id = @Id);

        IF @lock IS NULL
        BEGIN
            -- Idempotenza: dominio mai esistito o già cancellato (es. doppio invio della
            -- richiesta di annullamento lato UI) — trattato come cancellazione già avvenuta
            -- con successo, non come errore.
            SET @returnValue = 0;
        END

        -- ── CASO 1: dominio attivo (Lock = 0) → soft delete ───
        ELSE IF @lock = 0
        BEGIN
            -- Verifica dipendenze PRIMA della transazione (sono letture)
            IF EXISTS (
                SELECT 1 FROM dbo.tblSediInterne i
                             INNER JOIN dbo.tblSedi s ON i.Id = s.Id
                WHERE  i.IdDominio = @Id AND s.Lock = 0
            )
            BEGIN
                SET @returnValue = -1; SET @returnMessage = 'Un dominio che ha aziende associate non può essere cancellato';
                GOTO BRANCH_END;
            END

            IF EXISTS (SELECT 1 FROM dbo.tblUtenti WHERE IdDominio = @Id AND Lock = 0 AND [Master] = 0)
            BEGIN
                SET @returnValue = -1; SET @returnMessage = 'Un dominio che ha utenti associati non può essere cancellato';
                GOTO BRANCH_END;
            END

            IF EXISTS (SELECT 1 FROM dbo.tblAree WHERE IdDominio = @Id AND Lock = 0)
            BEGIN
                SET @returnValue = -1; SET @returnMessage = 'Un dominio che ha aree associate non può essere cancellato';
                GOTO BRANCH_END;
            END

            BEGIN TRANSACTION;
                UPDATE dbo.tblDomini SET Lock = 4 WHERE Id = @Id AND Lock = 0;

                IF @@ROWCOUNT = 0
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @returnValue = -1; SET @returnMessage = 'Dominio non trovato o già eliminato';
                    GOTO BRANCH_END;
                END

                IF @Reset = 1
                    DELETE dbo.tblIdCancellati WHERE IdSessione = @IdSessione;
                ELSE
                    DELETE dbo.tblIdCancellati WHERE Id = @Id;

                INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
                VALUES (@Id, @IdSessione, GETDATE());
            COMMIT TRANSACTION;

            -- Log FUORI dalla transazione
            EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
        END

        -- ── CASO 2: dominio in bozza (Lock = 2) → hard delete ───
        ELSE IF @lock = 2
        BEGIN
            BEGIN TRANSACTION;
                -- Utenti del dominio
                DELETE dbo.tblIdLog  WHERE Id IN (SELECT Id FROM dbo.tblUtenti WHERE IdDominio = @Id);
                DELETE dbo.tblId     WHERE Id IN (SELECT Id FROM dbo.tblUtenti WHERE IdDominio = @Id);
                DELETE dbo.tblUtenti WHERE IdDominio = @Id;

                -- Indirizzi delle sedi interne
                SELECT IdIndirizzo
                INTO   #tIndirizzi
                FROM   dbo.tblSediIndirizzi
                WHERE  Id IN (SELECT Id FROM dbo.tblSediInterne WHERE IdDominio = @Id);

                DELETE dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM dbo.tblSediInterne WHERE IdDominio = @Id);
                DELETE dbo.tblIndirizzi     WHERE Id IN (SELECT IdIndirizzo FROM #tIndirizzi);
                DELETE dbo.tblIdLog         WHERE Id IN (SELECT IdIndirizzo FROM #tIndirizzi);
                DELETE dbo.tblId            WHERE Id IN (SELECT IdIndirizzo FROM #tIndirizzi);

                -- Sedi interne
                SELECT Id INTO #tSedi FROM dbo.tblSediInterne WHERE IdDominio = @Id;
                DELETE dbo.tblSediInterne WHERE Id IN (SELECT Id FROM #tSedi);
                DELETE dbo.tblSedi        WHERE Id IN (SELECT Id FROM #tSedi);
                DELETE dbo.tblIdLog       WHERE Id IN (SELECT Id FROM #tSedi);
                DELETE dbo.tblId          WHERE Id IN (SELECT Id FROM #tSedi);

                -- Dominio
                DELETE dbo.tblDominiModuli WHERE Id = @Id;
                DELETE dbo.tblDomini       WHERE Id = @Id;
                DELETE dbo.tblIdCancellati WHERE Id = @Id;
                DELETE dbo.tblIdLog        WHERE Id = @Id;
                DELETE dbo.tblId           WHERE Id = @Id;
            COMMIT TRANSACTION;
        END

        -- ── CASO 3: Lock in stato non gestito ────
        ELSE
        BEGIN
            SET @returnValue   = -1;
            SET @returnMessage = 'Il dominio è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
            GOTO BRANCH_END;
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
        THROW 50001, @returnMessage, 1
    END

END;


