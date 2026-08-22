CREATE PROCEDURE [dbo].[uspServizi_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Etichetta VARCHAR(50) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @Etichetta = dbo.ufnStringhe_get_SenzaSpazi(@Etichetta, 0, 1);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

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
		IF @IdIntervallo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non può essere vuoto';
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

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT IdCalendario
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdCalendario IS NOT NULL;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('V');

		SET @DallaData = DATEADD(DAY, DATEDIFF(DAY, 0, @DallaData), 0);

		DECLARE @AllaData SMALLDATETIME = CASE
			WHEN @IdIntervallo = '1D' THEN DATEADD(MINUTE, 59, DATEADD(HOUR, 23, DATEADD(DAY, 1, @DallaData)))
			WHEN @IdIntervallo = '1W' THEN DATEADD(MINUTE, 59, DATEADD(HOUR, 23, DATEADD(WEEK, 1, @DallaData)))
			WHEN @IdIntervallo = '2W' THEN DATEADD(MINUTE, 59, DATEADD(HOUR, 23, DATEADD(WEEK, 2, @DallaData)))
			WHEN @IdIntervallo = '1M' THEN DATEADD(MINUTE, 59, DATEADD(HOUR, 23, DATEADD(MONTH, 1, @DallaData)))
			WHEN @IdIntervallo = '2M' THEN DATEADD(MINUTE, 59, DATEADD(HOUR, 23, DATEADD(MONTH, 2, @DallaData)))
			WHEN @IdIntervallo = '6M' THEN DATEADD(MINUTE, 59, DATEADD(HOUR, 23, DATEADD(MONTH, 6, @DallaData)))
			WHEN @IdIntervallo = '1Y' THEN DATEADD(MINUTE, 59, DATEADD(HOUR, 23, DATEADD(YEAR, 1, @DallaData)))
			ELSE DATEADD(MINUTE, 59, DATEADD(HOUR, 23, @DallaData))
		END;

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		DECLARE @stmt NVARCHAR(MAX);
		DECLARE @params NVARCHAR(4000) = N'
            @RowsPerPage  INT,
            @Offset       INT,
            @IdSessione   CHAR(16),
            @IdIntervallo CHAR(2),
            @DallaData    SMALLDATETIME,
            @AllaData     SMALLDATETIME,
            @Stato        CHAR(1),
            @Etichetta    VARCHAR(50),
            @Search       VARCHAR(50),
            @IdCalendario tvpId_char_16 READONLY,
            @IdTipo       tvpId_char_1  READONLY';

		SET @stmt = N'
        WITH tbl AS (
            SELECT
                s.Id,
                StatoValore = CASE
                    WHEN e.IdStato IN (''D'', ''I'') AND e.[Data] < GETDATE() THEN 1
                    WHEN e.IdStato = ''A''                                      THEN 2
                    ELSE 0
                END,
                StatoDescrizione = e.Stato + IIF(e.IdStato IN (''D'', ''I'') AND e.[Data] < GETDATE(), '' - Scaduto'', ''''),
                IdSerie          = ISNULL(s2.Id, s.Id),
                Tipo             = t.Nome,
                s.Descrizione,
                Richiedente      = r.NomeCompleto + '' - '' + r.IndirizzoCompleto,
                s.IdEvento,
                e.[Data],
                e.Ricorre,
                e.Eccezione,
                Etichette        = dbo.ufnEventi_get_Etichette(s.IdEvento)
            FROM
                dbo.tblServizi s
                INNER JOIN dbo.tblSedi r ON s.IdRichiedente = r.Id
                INNER JOIN dbo.tblTipi t ON s.IdTipo        = t.Id
                INNER JOIN dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e
                    ON s.IdEvento = e.Id
                LEFT  JOIN dbo.tblServizi s2 ON e.IdEccezione = s2.IdEvento
            WHERE 1 = 1';

		IF @Search IS NOT NULL
			SET @stmt = @stmt + N'
                AND s.Descrizione LIKE ''%'' + @Search + ''%''';

		IF @Etichetta IS NOT NULL
			SET @stmt = @stmt + N'
                AND s.IdEvento IN (
                    SELECT t.Id FROM dbo.tblEventiEtichette t
                    INNER JOIN dbo.tblEtichette e ON t.IdEtichetta = e.Id
                    WHERE e.Nome LIKE ''%'' + @Etichetta + ''%'')';

		IF @Stato <> 'T'
		BEGIN
			IF @Stato = 'S'
				SET @stmt = @stmt + N'
                    AND (e.IdStato IN (''D'', ''I'') AND e.[Data] < GETDATE())';
			ELSE
				SET @stmt = @stmt + N'
                    AND e.IdStato = @Stato';
		END

		SET @stmt = @stmt + N'
        )
        SELECT
            tbl.Id, tbl.StatoValore, tbl.StatoDescrizione,
            tbl.IdSerie, tbl.Tipo, tbl.Descrizione, tbl.Richiedente,
            tbl.IdEvento, tbl.[Data], tbl.Ricorre, tbl.Eccezione, tbl.Etichette,
            RowsCount = COUNT(*) OVER ()
        FROM tbl
        ORDER BY tbl.[Data]
        OFFSET @Offset ROWS
        FETCH NEXT @RowsPerPage ROWS ONLY;';

		EXEC sp_executesql
			@stmt,
			@params,
			@RowsPerPage = @RowsPerPage,
			@Offset = @Offset,
			@IdSessione = @IdSessione,
			@IdIntervallo = @IdIntervallo,
			@DallaData = @DallaData,
			@AllaData = @AllaData,
			@Stato = @Stato,
			@Etichetta = @Etichetta,
			@Search = @Search,
			@IdCalendario = @IdCalendario,
			@IdTipo = @IdTipo;

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
