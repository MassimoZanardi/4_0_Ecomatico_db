CREATE   PROCEDURE [dbo].[uspServizi_get_CalendarioMese_List]
    @IdSessione CHAR(16) = NULL,
    @DallaData  SMALLDATETIME = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SET DATEFORMAT YMD;
    SET DATEFIRST 1;

    BEGIN TRY

        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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

        DECLARE @AllaData SMALLDATETIME = DATEADD(MINUTE, -30, DATEADD(DAY, 42, @DallaData));

        DECLARE @IdCalendario tvpId_char_16;
        INSERT INTO @IdCalendario (Id)
        SELECT IdCalendario FROM dbo.tblSessioni
        WHERE  Id = @IdSessione AND IdCalendario IS NOT NULL;

        DECLARE @IdTipo tvpId_char_1;
        INSERT INTO @IdTipo (Id) VALUES ('V');

        SELECT
            e.Id        AS IdEvento,
            e.[Data],
            Scaduto     = IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0),
            Eseguito    = IIF(e.IdStato = 'E', 1, 0),
            AvvisoTesto = FORMAT(e.[Data], 'HH:mm') + ' - ' + e.AvvisoTesto
        INTO #tEventi
        FROM dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e;

        CREATE INDEX IX_tEventi_Data ON #tEventi ([Data]);

        ;WITH cteCalendario AS (
            SELECT
                Settimana = value / 7,
                [Data]    = DATEADD(DAY, value, @DallaData),
                DataFine  = DATEADD(HOUR, 23, DATEADD(MINUTE, 30, DATEADD(DAY, value, @DallaData))),
                Giorno    = DATEPART(DW, DATEADD(DAY, value, @DallaData))
            FROM GENERATE_SERIES(0, 41, 1)
        ),
        cteDati AS (
            SELECT c.[Data], c.Giorno, c.Settimana, s.Id, t.IdEvento, t.Scaduto, t.Eseguito, t.AvvisoTesto
            FROM
                cteCalendario c
                LEFT JOIN #tEventi t ON t.[Data] BETWEEN c.[Data] AND c.DataFine
                LEFT JOIN dbo.tblServizi s ON t.IdEvento = s.IdEvento
        )
        SELECT
            Riferimento = t0.Settimana,
            Lun = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[1] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[1], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[1],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[1],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[1],''), '"', '\"') + '"}',
            Mar = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[2] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[2], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[2],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[2],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[2],''), '"', '\"') + '"}',
            Mer = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[3] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[3], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[3],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[3],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[3],''), '"', '\"') + '"}',
            Gio = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[4] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[4], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[4],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[4],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[4],''), '"', '\"') + '"}',
            Ven = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[5] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[5], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[5],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[5],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[5],''), '"', '\"') + '"}',
            Sab = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[6] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[6], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[6],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[6],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[6],''), '"', '\"') + '"}',
            Dom = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.[7] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[7], 'yyyy-MM-dd'), '') + '","Scaduti":' + CAST(ISNULL(t2.[7],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[7],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[7],''), '"', '\"') + '"}'
        FROM
            (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7] FROM (SELECT Giorno,Settimana,Id FROM cteDati) t PIVOT (COUNT(Id) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t0
            LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7] FROM (SELECT Giorno,Settimana,[Data] FROM cteDati) t PIVOT (MAX([Data]) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t1 ON t0.Settimana=t1.Settimana
            LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7] FROM (SELECT Giorno,Settimana,Scaduto=ISNULL(Scaduto,0) FROM cteDati) t PIVOT (SUM(Scaduto) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t2 ON t0.Settimana=t2.Settimana
            LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7] FROM (SELECT Giorno,Settimana,Eseguito=ISNULL(Eseguito,0) FROM cteDati) t PIVOT (SUM(Eseguito) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t3 ON t0.Settimana=t3.Settimana
            LEFT JOIN (SELECT Settimana,[1],[2],[3],[4],[5],[6],[7] FROM (SELECT Giorno,Settimana,AvvisoTesto FROM cteDati) t PIVOT (MAX(AvvisoTesto) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t4 ON t0.Settimana=t4.Settimana
        ORDER BY t0.Settimana;

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
