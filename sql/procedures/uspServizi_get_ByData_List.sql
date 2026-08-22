CREATE   PROCEDURE [dbo].[uspServizi_get_ByData_List]
    @PageNumber   INT           = 1,
    @RowsPerPage  INT           = 50,
    @IdSessione   CHAR(16) = NULL,
    @DallaData    SMALLDATETIME = NULL,
    @IdIntervallo CHAR(2) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SET DATEFORMAT YMD;
    SET DATEFIRST 1;

    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSessione   = NULLIF(LTRIM(RTRIM(@IdSessione)),   '');
        SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');

        IF @IdSessione IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @DallaData IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
            GOTO BRANCH_END;
        END
        IF @IdIntervallo IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdIntervallo non può essere vuoto';
            GOTO BRANCH_END;
        END

        DECLARE @permesso TINYINT;
        EXEC dbo.uspSessione_get_FunzionePermesso
            @Id         = @IdSessione,
            @IdFunzione = 'SRV',
            @Permesso   = @permesso OUTPUT;

        IF 1 > @permesso
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Non si dispone dei diritti necessari';
            GOTO BRANCH_END;
        END

        DECLARE @IdCalendario tvpId_char_16;
        INSERT INTO @IdCalendario (Id)
        SELECT IdCalendario FROM dbo.tblSessioni
        WHERE  Id = @IdSessione AND IdCalendario IS NOT NULL;

        DECLARE @IdTipo tvpId_char_1;
        INSERT INTO @IdTipo (Id) VALUES ('V');

        DECLARE @AllaData SMALLDATETIME = CASE
            WHEN @IdIntervallo = '30' THEN DATEADD(MINUTE, 30, @DallaData)
            WHEN @IdIntervallo = '1D' THEN DATEADD(MINUTE, 59, DATEADD(HOUR, 23, @DallaData))
            ELSE @DallaData
        END;

        DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

        ;WITH tbl AS (
            SELECT
                s.Id,
                StatoValore = CASE
                    WHEN e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE() THEN 1
                    WHEN e.IdStato = 'A'                                   THEN 2
                    ELSE 0
                END,
                StatoDescrizione = e.Stato + IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), ' - Scaduto', ''),
                IdSerie          = ISNULL(s2.Id, s.Id),
                Descrizione      = e.AvvisoTesto,
                s.IdEvento,
                e.[Data],
                e.Ricorre,
                e.Eccezione
            FROM
                dbo.tblServizi s
                INNER JOIN dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e
                    ON s.IdEvento = e.Id
                LEFT JOIN dbo.tblServizi s2 ON e.IdEccezione = s2.IdEvento
        )
        SELECT
            tbl.Id, tbl.StatoValore, tbl.StatoDescrizione,
            tbl.IdSerie, tbl.Descrizione, tbl.IdEvento,
            tbl.[Data], tbl.Ricorre, tbl.Eccezione,
            RowsCount = COUNT(*) OVER ()
        FROM   tbl
        ORDER BY tbl.[Data]
        OFFSET @Offset ROWS
        FETCH NEXT @RowsPerPage ROWS ONLY;

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
