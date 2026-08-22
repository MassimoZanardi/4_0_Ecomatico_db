CREATE PROCEDURE [dbo].[uspServiziAssegnati_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
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
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

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

		DECLARE @permessoSrv TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		DECLARE @permessoSra TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		IF 1 > @permessoSrv AND 1 > @permessoSra
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @IdUtente CHAR(16);
		DECLARE @idCal CHAR(16);

		SELECT @IdUtente = IdUtente, @idCal = IdCalendario
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id) SELECT @idCal
		WHERE @idCal IS NOT NULL;

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
            @Search       VARCHAR(50),
            @IdUtente     CHAR(16),
            @IdCalendario tvpId_char_16 READONLY';

		SET @stmt = N'
        WITH tbl AS (
            SELECT
                s.Id,
                s.IdEvento,
                e.[Data],
                StatoValore = CASE
                    WHEN e.IdStato IN (''D'', ''I'') AND e.[Data] < GETDATE() THEN 1
                    WHEN e.IdStato = ''A''                                      THEN 2
                    ELSE 0
                END,
                StatoDescrizione = e.Stato + IIF(e.IdStato IN (''D'', ''I'') AND e.[Data] < GETDATE(), '' - Scaduto'', ''''),
                Tipo             = t.Nome,
                s.Descrizione,
                Richiedente      = r.NomeCompleto + '' - '' + r.IndirizzoCompleto,
                Etichette        = dbo.ufnEventi_get_Etichette(s.IdEvento)
            FROM
                dbo.ufnEventi_get_Assegnati_List(@DallaData, @AllaData, @IdUtente, @IdCalendario) e
                INNER JOIN dbo.tblServizi s ON e.Id          = s.IdEvento
                INNER JOIN dbo.tblSedi    r ON s.IdRichiedente = r.Id
                INNER JOIN dbo.tblTipi    t ON s.IdTipo       = t.Id
            WHERE 1 = 1';

		IF @Search IS NOT NULL
			SET @stmt = @stmt + N'
                AND s.Descrizione LIKE ''%'' + @Search + ''%''';

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
            tbl.Id, tbl.IdEvento, tbl.[Data],
            tbl.StatoValore, tbl.StatoDescrizione,
            tbl.Tipo, tbl.Descrizione, tbl.Richiedente, tbl.Etichette,
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
			@Search = @Search,
			@IdUtente = @IdUtente,
			@IdCalendario = @IdCalendario;

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
