CREATE   PROCEDURE [dbo].[uspEtichette_upd]
    @Id              CHAR(16) = NULL,
    @IdSessione      CHAR(16) = NULL,
    @IdSede          CHAR(16) = NULL,
    @IdModulo        CHAR(3) = NULL,
    @IdColore        CHAR(1) = NULL,
    @Visualizzazione CHAR(1) = NULL,
    @Nome            VARCHAR(50)  = NULL,
    @Descrizione     VARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @returnValue   INT           = 0;
    DECLARE @returnMessage NVARCHAR(200) = NULL;
    DECLARE @permesso      TINYINT;

    BEGIN TRY

        SET @Id              = NULLIF(LTRIM(RTRIM(@Id)),              '');
        SET @IdSessione      = NULLIF(LTRIM(RTRIM(@IdSessione)),      '');
        SET @IdSede          = NULLIF(LTRIM(RTRIM(@IdSede)),          '');
        SET @IdModulo        = NULLIF(LTRIM(RTRIM(@IdModulo)),        '');
        SET @IdColore        = NULLIF(LTRIM(RTRIM(@IdColore)),        '');
        SET @Visualizzazione = NULLIF(LTRIM(RTRIM(@Visualizzazione)), '');

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
        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @IdModulo IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdModulo non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @IdColore IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdColore non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @Visualizzazione IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Visualizzazione non può essere vuoto';
            GOTO BRANCH_END;
        END

        EXEC dbo.uspSessione_get_FunzionePermesso
            @Id         = @IdSessione,
            @IdFunzione = 'ETC',
            @Permesso   = @permesso OUTPUT;

        IF 2 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        -- Controllo permesso sul modulo: allineato a get/get_List/ins, prima assente qui
        IF dbo.ufnModuli_get_IsAttivoBySessione(@IdModulo, @IdSessione) = 0
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        -- Verifica che l'etichetta esista, appartenga davvero a @IdSede/@IdModulo
        -- (evita che parametri disallineati aggirino il controllo di unicità
        -- e la scelta della cache JSON da rigenerare più sotto)
        -- e che la sede sia accessibile dalla sessione corrente
        IF NOT EXISTS (
            SELECT 1
            FROM   dbo.tblEtichette e
                   INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON e.IdSede = i.Id
            WHERE  e.Id       = @Id
              AND  e.IdSede   = @IdSede
              AND  e.IdModulo = @IdModulo
              AND  e.Lock    <= 2
        )
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Etichetta non trovata';
            GOTO BRANCH_END;
        END

        SET @Nome        = dbo.ufnStringhe_get_SenzaSpazi(@Nome,        0, 1);
        SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);

        IF @Nome IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.tblEtichette
            WHERE  Id      <> @Id
              AND  IdSede   = @IdSede
              AND  IdModulo = @IdModulo
              AND  Lock     = 0
              AND  Nome     = @Nome
        )
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Un''altra etichetta con lo stesso nome è già presente';
            GOTO BRANCH_END;
        END

        BEGIN TRANSACTION;

            UPDATE dbo.tblEtichette
            SET    Lock            = 0,
                   IdColore        = @IdColore,
                   Visualizzazione = @Visualizzazione,
                   Nome            = ISNULL(@Nome,        Nome),
                   Descrizione     = ISNULL(@Descrizione, Descrizione)
            WHERE  Id        = @Id
              AND  IdSede    = @IdSede
              AND  IdModulo  = @IdModulo
              AND  Lock     <= 2;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @returnValue = -1; SET @returnMessage = 'Etichetta non trovata o già eliminata';
                GOTO BRANCH_END;
            END

            IF @IdModulo IN ('SRV', 'SCD')
            BEGIN
                UPDATE e
                SET    Etichette = (
                    SELECT   et.Nome,
                             Colore       = IIF(et.Visualizzazione = 'C', c.Hex, c.Css),
                             et.Descrizione,
                             et.Visualizzazione
                    FROM     dbo.tblEventiEtichette    x
                             INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id
                             INNER JOIN dbo.tblColori    c  ON et.IdColore   = c.Id
                    WHERE    x.Id    = e.Id
                      AND    et.Lock = 0
                    ORDER BY et.Nome
                    FOR JSON PATH
                )
                FROM   dbo.tblEventi           e
                       INNER JOIN dbo.tblEventiEtichette t ON e.Id = t.Id
                WHERE  t.IdEtichetta = @Id;
            END
            ELSE IF @IdModulo = 'RIF'
            BEGIN
                UPDATE e
                SET    Etichette = (
                    SELECT   et.Nome,
                             Colore       = IIF(et.Visualizzazione = 'C', c.Hex, c.Css),
                             et.Descrizione,
                             et.Visualizzazione
                    FROM     dbo.tblRifiutiRegistrazioniEtichette x
                             INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id
                             INNER JOIN dbo.tblColori    c  ON et.IdColore   = c.Id
                    WHERE    x.Id    = e.Id
                      AND    et.Lock = 0
                    ORDER BY et.Nome
                    FOR JSON PATH
                )
                FROM   dbo.tblRifiutiRegistrazioni e
                       INNER JOIN dbo.tblRifiutiRegistrazioniEtichette t ON e.Id = t.Id
                WHERE  t.IdEtichetta = @Id;

                UPDATE e
                SET    Etichette = (
                    SELECT   et.Nome,
                             Colore       = IIF(et.Visualizzazione = 'C', c.Hex, c.Css),
                             et.Descrizione,
                             et.Visualizzazione
                    FROM     dbo.tblRifiutiFormulariEtichette x
                             INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id
                             INNER JOIN dbo.tblColori    c  ON et.IdColore   = c.Id
                    WHERE    x.Id    = e.Id
                      AND    et.Lock = 0
                    ORDER BY et.Nome
                    FOR JSON PATH
                )
                FROM   dbo.tblRifiutiFormulari e
                       INNER JOIN dbo.tblRifiutiFormulariEtichette t ON e.Id = t.Id
                WHERE  t.IdEtichetta = @Id;

                UPDATE e
                SET    Etichette = (
                    SELECT   et.Nome,
                             Colore       = IIF(et.Visualizzazione = 'C', c.Hex, c.Css),
                             et.Descrizione,
                             et.Visualizzazione
                    FROM     dbo.tblRifiutiModelliEtichette x
                             INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id
                             INNER JOIN dbo.tblColori    c  ON et.IdColore   = c.Id
                    WHERE    x.Id    = e.Id
                      AND    et.Lock = 0
                    ORDER BY et.Nome
                    FOR JSON PATH
                )
                FROM   dbo.tblRifiutiModelli e
                       INNER JOIN dbo.tblRifiutiModelliEtichette t ON e.Id = t.Id
                WHERE  t.IdEtichetta = @Id;
            END

        COMMIT TRANSACTION;

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
        THROW 50001, @returnMessage, 1;
    END

END;
