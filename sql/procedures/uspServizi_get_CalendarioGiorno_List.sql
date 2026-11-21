CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_CalendarioGiorno_List]
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
			@IdFunzione = 'SRV',
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
		INSERT INTO @IdTipo (Id) VALUES ('V');

		SELECT
			e.Id AS IdEvento,
			e.[Data],
			Scaduto = IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0),
			Eseguito = IIF(e.IdStato = 'E', 1, 0),
			Annullato = IIF(e.IdStato = 'A', 1, 0),
			-- Il servizio sta nella cella dell'ora di inizio anche con la durata: il testo ne mostra l'orario
			AvvisoTesto = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata) + ' - ' + ISNULL(e.AvvisoTesto, '')
		INTO #tEventi
		FROM
			dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e
			LEFT JOIN dbo.tblServizi s ON e.Id = s.IdEvento;

		CREATE INDEX IX_tEventi_Data ON #tEventi ([Data]);

		;WITH cteCalendario AS (
			SELECT
				[Data] = DATEADD(HOUR, value, @DallaData),
				-- Fine della cella: hh:59 (con SMALLDATETIME equivale a < hh+1:00), cosi' anche
				-- i servizi con i minuti fra 31 e 59 cadono nella cella della loro ora
				DataFine = DATEADD(MINUTE, 59, DATEADD(HOUR, value, @DallaData)),
				Ora = FORMAT(DATEADD(HOUR, value, @DallaData), 'HH:mm')
			FROM GENERATE_SERIES(0, 23, 1)
		),
		cteDati AS (
			SELECT c.[Data], c.Ora, s.Id, t.IdEvento, t.Scaduto, t.Eseguito, t.Annullato, t.AvvisoTesto
			FROM
				cteCalendario c
				LEFT JOIN #tEventi t ON t.[Data] BETWEEN c.[Data] AND c.DataFine
				LEFT JOIN dbo.tblServizi s ON t.IdEvento = s.IdEvento
		)
		SELECT
			t0.Ora,
			Dati = '{"MenuNuovo":"Nuovo servizio","Eventi":' + CAST(t0.Eventi AS VARCHAR(10)) + ',"Data":"' + ISNULL(FORMAT(t0.[Data], 'yyyy-MM-ddTHH:mm:ssZ'), '') + '","Scaduti":' + CAST(ISNULL(t0.Scaduti,0) AS VARCHAR(10)) + ',"Eseguiti":' + CAST(ISNULL(t0.Eseguiti,0) AS VARCHAR(10)) + ',"Annullati":' + CAST(ISNULL(t0.Annullati,0) AS VARCHAR(10)) + ',"Testo":"' + REPLACE(ISNULL(t0.Testo,''), '"', '\"') + '"}'
		FROM (
			SELECT [Data], Ora,
				Eventi = COUNT(Id),
				Scaduti = SUM(ISNULL(Scaduto, 0)),
				Eseguiti = SUM(ISNULL(Eseguito, 0)),
				Annullati = SUM(ISNULL(Annullato, 0)),
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
