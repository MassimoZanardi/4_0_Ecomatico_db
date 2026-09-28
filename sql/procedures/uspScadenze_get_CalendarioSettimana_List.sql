CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_get_CalendarioSettimana_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DallaData non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @AllaData SMALLDATETIME = DATEADD(DAY, 8, @DallaData);

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('S');

		SELECT
			e.Id AS IdEvento,
			e.[Data],
			Scaduto = IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0),
			Eseguito = IIF(e.IdStato = 'E', 1, 0),
			AvvisoTesto = e.AvvisoTesto
		INTO #tEventi
		FROM dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e;

		CREATE INDEX IX_tEventi_Data ON #tEventi ([Data]);

		;WITH cteCalendario AS (
			SELECT
				[Data] = DATEADD(HOUR, value, @DallaData),
				DataFine = DATEADD(MINUTE, 30, DATEADD(HOUR, value, @DallaData)),
				Giorno = DATEPART(DW, DATEADD(HOUR, value, @DallaData)),
				Ora = FORMAT(DATEADD(HOUR, value, @DallaData), 'HH:mm')
			FROM GENERATE_SERIES(0, 167, 1)
		),
		cteDati AS (
			SELECT c.[Data], c.Giorno, c.Ora, s.Id, t.IdEvento, t.Scaduto, t.Eseguito, t.AvvisoTesto
			FROM
				cteCalendario c
				LEFT JOIN #tEventi t ON t.[Data] BETWEEN c.[Data] AND c.DataFine
				LEFT JOIN dbo.tblScadenze s ON t.IdEvento = s.IdEvento
		)
		SELECT
			Riferimento = t0.Ora,
			Lun = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[1] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[1], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[1],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[1],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[1],''), '"', '\"') + '"}',
			Mar = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[2] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[2], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[2],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[2],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[2],''), '"', '\"') + '"}',
			Mer = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[3] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[3], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[3],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[3],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[3],''), '"', '\"') + '"}',
			Gio = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[4] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[4], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[4],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[4],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[4],''), '"', '\"') + '"}',
			Ven = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[5] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[5], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[5],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[5],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[5],''), '"', '\"') + '"}',
			Sab = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[6] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[6], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[6],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[6],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[6],''), '"', '\"') + '"}',
			Dom = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.[7] AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t1.[7], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t2.[7],0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t3.[7],0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t4.[7],''), '"', '\"') + '"}'
		FROM
			(SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,Id
			FROM cteDati) t PIVOT (COUNT(Id) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t0
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,[Data]
			FROM cteDati) t PIVOT (MAX([Data]) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t1 ON t0.Ora=t1.Ora
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,Scaduto=ISNULL(Scaduto,0)
			FROM cteDati) t PIVOT (SUM(Scaduto) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t2 ON t0.Ora=t2.Ora
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,Eseguito=ISNULL(Eseguito,0)
			FROM cteDati) t PIVOT (SUM(Eseguito) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t3 ON t0.Ora=t3.Ora
			LEFT JOIN (SELECT Ora,[1],[2],[3],[4],[5],[6],[7]
			FROM (SELECT Giorno,Ora,AvvisoTesto
			FROM cteDati) t PIVOT (MAX(AvvisoTesto) FOR Giorno IN ([1],[2],[3],[4],[5],[6],[7])) p) t4 ON t0.Ora=t4.Ora
		ORDER BY t0.Ora;

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
