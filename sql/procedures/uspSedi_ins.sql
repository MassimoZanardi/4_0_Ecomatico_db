CREATE   PROCEDURE [dbo].[uspSedi_ins]
    @IdSessione     CHAR(16) = NULL,
    @IdTipo         CHAR(1)  = NULL,
    @InternaEsterna CHAR(1)  = NULL,
    @IdParent       CHAR(16) = NULL,
    @Contesto       INT      = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY

        DECLARE @returnId      CHAR(16)      = NULL;
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;
        DECLARE @idDominio     CHAR(16);
        DECLARE @idAzienda     CHAR(16);

        SET @IdSessione     = NULLIF(LTRIM(RTRIM(@IdSessione)),     '');
        SET @IdTipo         = NULLIF(LTRIM(RTRIM(@IdTipo)),         '');
        SET @InternaEsterna = NULLIF(LTRIM(RTRIM(@InternaEsterna)), '');
        SET @IdParent       = NULLIF(LTRIM(RTRIM(@IdParent)),       '');

        IF @IdSessione IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF @Contesto = 3
        BEGIN
            SELECT
                @idAzienda      = s.IdAziendaInterna,
                @IdTipo         = 'L',
                @InternaEsterna = 'E'
            FROM
                dbo.tblSessioni       e
                INNER JOIN dbo.tblRifiutiRegistri r ON e.IdRegistro = r.Id
                INNER JOIN dbo.tblSedi            s ON r.IdSede     = s.Id
            WHERE  e.Id = @IdSessione;
        END
        ELSE
        BEGIN
            SELECT
                @idDominio = IdDominio,
                @idAzienda = IdAzienda
            FROM   dbo.tblSessioni
            WHERE  Id = @IdSessione;
        END

        DECLARE @idFunzione CHAR(3) = IIF(@InternaEsterna = 'I', 'AZI', 'ANS');
        DECLARE @permesso   TINYINT;

        EXEC dbo.uspSessione_get_FunzionePermesso
            @Id         = @IdSessione,
            @IdFunzione = @idFunzione,
            @Permesso   = @permesso OUTPUT;

        IF 2 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        IF @InternaEsterna = 'I' AND (@idDominio IS NULL OR @idDominio = REPLICATE('0', 16))
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Selezionare il dominio';
            GOTO BRANCH_END;
        END

        IF @InternaEsterna = 'E' AND (@idAzienda IS NULL OR @idAzienda = REPLICATE('0', 16))
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Selezionare l''azienda';
            GOTO BRANCH_END;
        END

        IF @IdTipo = 'A' AND EXISTS (
            SELECT 1 FROM dbo.tblSedi
            WHERE  IdParent = @IdParent AND IdTipo = 'A' AND Lock = 0
        )
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La sede amministrativa è già stata inserita';
            GOTO BRANCH_END;
        END

        IF @InternaEsterna = 'I' AND @IdParent IS NOT NULL
        BEGIN
            -- Titolarità: @IdParent deve appartenere al Dominio del chiamante, salvo Admin di un Dominio Master
            -- (bypass cross-dominio intenzionale, confermato dall'utente).
            IF NOT EXISTS (
                SELECT 1 FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
                WHERE  i.Id = @IdParent
            )
            AND NOT EXISTS (
                SELECT 1
                FROM   dbo.tblSessioni e
                       INNER JOIN dbo.tblUtenti ut ON e.IdUtente   = ut.Id
                       INNER JOIN dbo.tblDomini d  ON ut.IdDominio = d.Id
                WHERE  e.Id       = @IdSessione
                  AND  ut.IdRuolo = 'AD'
                  AND  ut.Lock    = 0
                  AND  d.[Master] = 1
            )
            BEGIN
                SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
                GOTO BRANCH_END;
            END
        END

        IF @InternaEsterna = 'I' AND @IdParent IS NULL
        AND (SELECT AziendeMax FROM dbo.tblDomini WHERE Id = @idDominio)
            <=
            (SELECT COUNT(*)
             FROM   dbo.tblSedi       s
                    INNER JOIN dbo.tblSediInterne i ON s.Id = i.Id
             WHERE  s.InternaEsterna = 'I'
               AND  i.IdDominio      = @idDominio
               AND  s.IdParent       IS NULL
               AND  s.Lock           = 0)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'È stato raggiunto il numero massimo di aziende inseribili';
            GOTO BRANCH_END;
        END

        IF @InternaEsterna = 'I' AND @IdParent IS NOT NULL
        AND (SELECT SediMax FROM dbo.tblDomini WHERE Id = @idDominio)
            <=
            (SELECT COUNT(*)
             FROM   dbo.tblSedi       s
                    INNER JOIN dbo.tblSediInterne i ON s.Id = i.Id
             WHERE  s.InternaEsterna = 'I'
               AND  i.IdDominio      = @idDominio
               AND  s.IdParent       IS NOT NULL
               AND  s.Lock           = 0)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'È stato raggiunto il numero massimo di sedi inseribili';
            GOTO BRANCH_END;
        END

        IF @InternaEsterna = 'E' AND @IdParent IS NOT NULL
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM dbo.tblSedi     s
                              INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
                WHERE  s.Id = @IdParent AND e.Id = @IdSessione
            )
            BEGIN
                SET @returnValue = -1; SET @returnMessage = 'Il soggetto condiviso da altre aziende non può essere modificato';
                GOTO BRANCH_END;
            END
        END

        EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

        BEGIN TRANSACTION;

            INSERT INTO dbo.tblOsepe (Id, Tipo)
            VALUES (@returnId, 'S');

            INSERT INTO dbo.tblSedi (Id, IdParent, InternaEsterna, IdTipo, Disabilitata, Lock)
            VALUES (@returnId, @IdParent, @InternaEsterna, @IdTipo, 0, 2);

            IF @InternaEsterna = 'I' AND @IdParent IS NULL
                INSERT INTO dbo.tblSediInterne (Id, IdDominio)
                VALUES (@returnId, @idDominio);

            ELSE IF @InternaEsterna = 'E' AND @IdParent IS NULL
                INSERT INTO dbo.tblSediEsterne (Id, IdSedeInterna)
                VALUES (@returnId, @idAzienda);

            IF @Contesto IS NOT NULL AND @Contesto > 0
                UPDATE dbo.tblSessioni
                SET    IdAzienda = @idAzienda
                WHERE  Id        = @IdSessione;

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
