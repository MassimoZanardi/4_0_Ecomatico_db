CREATE   PROCEDURE [dbo].[uspRifiutiAutorizzazioni_del]
    @Id         CHAR(16) = NULL,
    @IdSessione CHAR(16) = NULL,
    @Reset      BIT      = 0
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON
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
            @IdFunzione = 'RAT',
            @Permesso   = @permesso OUTPUT;

        IF 2 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        DECLARE @lock INT = (SELECT Lock FROM dbo.tblRifiutiAutorizzazioni WHERE Id = @Id);

        IF @lock IS NULL
        BEGIN
            -- Idempotenza: autorizzazione mai esistita o già cancellata (es. doppio invio della
            -- richiesta di annullamento lato UI) — trattata come cancellazione già avvenuta con
            -- successo, non come errore.
            SET @returnValue = 0;
        END

        -- ── CASO 1: autorizzazione attiva (Lock = 0) → soft delete ──────────
        ELSE IF @lock = 0
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM   dbo.tblRifiutiAutorizzazioni a
                       INNER JOIN dbo.tblSedi      s ON a.IdSede            = s.Id
                       INNER JOIN dbo.tblSessioni  e ON s.IdAziendaInterna  = e.IdAzienda
                WHERE  a.Id = @Id AND e.Id = @IdSessione
            )
            BEGIN
                SET @returnValue = -1; SET @returnMessage = 'Un''autorizzazione condivisa da altre aziende non può essere cancellata';
                GOTO BRANCH_END;
            END

            IF EXISTS (
                SELECT 1
                FROM   dbo.viewRifiutiMovimentiAutorizzazioni
                WHERE  (RegistrazioneLock < 2 OR FormularioLock < 2)
                  AND  (   IdAutorizzazioneProduttoreDetentore1 = @Id
                        OR IdAutorizzazioneDestinatario         = @Id
                        OR IdAutorizzazioneTrasportatore1       = @Id
                        OR IdAutorizzazioneIntermediario1       = @Id)
            )
            BEGIN
                SET @returnValue = -1; SET @returnMessage = 'Un''autorizzazione che ha registrazioni o formulari associati non può essere cancellata';
                GOTO BRANCH_END;
            END

            BEGIN TRANSACTION;
                UPDATE dbo.tblRifiutiAutorizzazioni SET Lock = 4 WHERE Id = @Id AND Lock = 0;

                IF @@ROWCOUNT = 0
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @returnValue = -1; SET @returnMessage = 'Autorizzazione non trovata o già eliminata';
                    GOTO BRANCH_END;
                END

                IF @Reset = 1
                    DELETE dbo.tblIdCancellati WHERE IdSessione = @IdSessione;
                ELSE
                    DELETE dbo.tblIdCancellati WHERE Id = @Id;

                INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
                VALUES (@Id, @IdSessione, GETDATE());
            COMMIT TRANSACTION;

            EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
        END

        -- ── CASO 2: autorizzazione in bozza (Lock = 2) → hard delete ─────────
        ELSE IF @lock = 2
        BEGIN
            BEGIN TRANSACTION;
                DELETE dbo.tblRifiutiAutorizzazioniAttivita         WHERE Id = @Id;
                DELETE dbo.tblRifiutiAutorizzazioniTarghe            WHERE Id = @Id;
                DELETE dbo.tblRifiutiAutorizzazioniTargheEerEsclusi  WHERE Id = @Id;
                DELETE dbo.tblRifiutiAutorizzazioniConducenti        WHERE Id = @Id;
                DELETE dbo.tblRifiutiAutorizzazioni                  WHERE Id = @Id;
                DELETE dbo.tblIdCancellati                           WHERE Id = @Id;
                DELETE dbo.tblIdLog                                  WHERE Id = @Id;
                DELETE dbo.tblId                                     WHERE Id = @Id;
            COMMIT TRANSACTION;
        END

        -- ── CASO 3: Lock in stato non gestito ────────────────────────────────
        ELSE
        BEGIN
            SET @returnValue   = -1;
            SET @returnMessage = 'L''autorizzazione è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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


