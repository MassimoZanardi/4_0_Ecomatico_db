CREATE   PROCEDURE [dbo].[uspRifiutiAutorizzazioni_ins_Targa]
    @Id         CHAR(16) = NULL,
    @Numero     VARCHAR(20) = NULL,
    @Rimorchio  BIT          = 0,
    @Eer        VARCHAR(8000),
    @IdSessione CHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON
    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @Id         = NULLIF(LTRIM(RTRIM(@Id)),         '');
        SET @Numero     = dbo.ufnStringhe_get_SenzaSpazi(@Numero,    0, 1);
        SET @Eer        = NULLIF(LTRIM(RTRIM(@Eer)),        '');
        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

        IF @Id IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Id non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @Numero IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @Numero non può essere vuoto';
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

        -- Titolarità sull'autorizzazione padre: senza questo controllo, chiunque avesse
        -- permesso RAT sul modulo (anche di un'altra azienda) poteva aggiungere targhe a
        -- un'autorizzazione non propria conoscendone l'Id.
        IF NOT EXISTS (
            SELECT 1
            FROM   dbo.tblRifiutiAutorizzazioni a
                   INNER JOIN dbo.tblSedi       s ON a.IdSede           = s.Id
                   INNER JOIN dbo.tblSessioni   e ON s.IdAziendaInterna = e.IdAzienda
            WHERE  a.Id = @Id AND e.Id = @IdSessione AND a.Lock <= 2
        )
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Un''autorizzazione condivisa da altre aziende non può essere modificata';
            GOTO BRANCH_END;
        END

        IF EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioniTarghe WHERE Id = @Id AND Targa = @Numero)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La targa è già presente';
            GOTO BRANCH_END;
        END

        IF 500 <= (SELECT COUNT(*) FROM dbo.tblRifiutiAutorizzazioniTarghe WHERE Id = @Id)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'È stato raggiunto il numero massimo di targhe inseribili';
            GOTO BRANCH_END;
        END

        -- @Eer: lista di codici EER abilitati per questa targa (separati da ';').
        -- Gli EER dell'autorizzazione NON presenti in @Eer vengono inseriti come esclusi.
        BEGIN TRANSACTION;

            INSERT INTO dbo.tblRifiutiAutorizzazioniTargheEerEsclusi (Id, Targa, IdEer)
            SELECT
                @Id,
                @Numero,
                a.IdEer
            FROM
                dbo.tblRifiutiAutorizzazioniEer a
            WHERE
                a.Id = @Id
                AND a.IdEer NOT IN (
                    SELECT e.Id
                    FROM   STRING_SPLIT(@Eer, ';') s
                           INNER JOIN dbo.tblRifiutiEer e ON s.value = e.Id
                    WHERE  s.value <> ''
                );

            INSERT INTO dbo.tblRifiutiAutorizzazioniTarghe (Id, Targa, Rimorchio)
            VALUES (@Id, @Numero, @Rimorchio);

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
        THROW 50001, @returnMessage, 1
    END

END;
