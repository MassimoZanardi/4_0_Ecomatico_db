CREATE PROCEDURE [dbo].[uspScadenze_get_CalendarioGiorno_List]
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

		DECLARE @AllaData SMALLDATETIME = DATEADD(MINUTE, 59, DATEADD(HOUR, 23, @DallaData));

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
				DataMezza = DATEADD(MINUTE, 30, DATEADD(HOUR, value, @DallaData)),
				Ora = FORMAT(DATEADD(HOUR, value, @DallaData), 'HH:mm')
			FROM GENERATE_SERIES(0, 23, 1)
		),
		cteDati AS (
			SELECT c.[Data], c.Ora, s.Id, t.IdEvento, t.Scaduto, t.Eseguito, t.AvvisoTesto
			FROM
				cteCalendario c
				LEFT JOIN #tEventi t ON t.[Data] BETWEEN c.[Data] AND c.DataMezza
				LEFT JOIN dbo.tblScadenze s ON t.IdEvento = s.IdEvento
		)
		SELECT
			t0.Ora,
			Dati = '{"MenuNuovo":"Nuova scadenza","Eventi":' + CAST(t0.Eventi AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t0.[Data], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t0.Scaduti,0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t0.Eseguiti,0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t0.Testo,''), '"', '\"') + '"}'
		FROM (
			SELECT [Data], Ora,
				Eventi = COUNT(Id),
				Scaduti = SUM(ISNULL(Scaduto, 0)),
				Eseguiti = SUM(ISNULL(Eseguito, 0)),
				Testo = MAX(AvvisoTesto)
			FROM cteDati
			GROUP BY [Data], Ora
		) t0
		ORDER BY t0.[Data];

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
