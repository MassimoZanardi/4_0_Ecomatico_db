CREATE OR ALTER PROCEDURE [dbo].[uspAvvisi_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdUtente CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametri
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Finestra temporale: ultimi 30 giorni → prossime 4 settimane
		DECLARE @DallaData SMALLDATETIME = DATEADD(DAY, -30, GETDATE());
		DECLARE @AllaData SMALLDATETIME = DATEADD(DAY, 28, GETDATE());

		-- Pre-calcolo offset: sp_executesql non accetta aritmetica in OFFSET
		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		-- Calendari accessibili dall'utente sui moduli abilitati
		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT c.Id
		FROM dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) s
		INNER JOIN dbo.tblCalendari c ON s.Id = c.IdSede
		WHERE
			c.Lock = 0
			AND c.IdModulo IN (
			  SELECT dm.IdModulo
			  FROM dbo.tblUtenti u
			  INNER JOIN dbo.tblDominiModuli dm ON u.IdDominio = dm.Id
			  WHERE u.Id = @IdUtente
				AND u.IdRuolo = 'AD'

			  UNION ALL -- AD e US mutualmente esclusivi

			  SELECT mf.Id
			  FROM dbo.tblUtenti u
			  INNER JOIN dbo.tblUtentiFunzioni uf ON u.Id = uf.Id
			  INNER JOIN dbo.tblModuliFunzioni mf ON uf.IdFunzione = mf.IdFunzione
			  WHERE u.Id = @IdUtente
				AND u.IdRuolo = 'US'
		  );

		-- Tipi di eventi accessibili dall'utente
		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id)
		SELECT t.IdTipo
		FROM dbo.tblUtenti u
		INNER JOIN dbo.tblDominiModuli d ON u.IdDominio = d.Id
		INNER JOIN dbo.tblModuliFunzioni mf ON d.IdModulo = mf.Id
		INNER JOIN dbo.tblFunzioniEventiTipi t ON mf.IdFunzione = t.Id
		WHERE
			u.Id = @IdUtente
			AND u.IdRuolo = 'AD'
		UNION ALL -- AD e US mutualmente esclusivi

		SELECT t.IdTipo
		FROM dbo.tblUtenti u
		INNER JOIN dbo.tblUtentiFunzioni uf ON u.Id = uf.Id
		INNER JOIN dbo.tblFunzioniEventiTipi t ON uf.IdFunzione = t.Id
		WHERE
			u.Id = @IdUtente
			AND u.IdRuolo = 'US';

		DECLARE @stmt NVARCHAR(MAX);
		DECLARE @params NVARCHAR(4000) = N'
            @RowsPerPage  INT,
            @Offset       INT,
            @IdUtente     CHAR(16),
            @Search       VARCHAR(50),
            @DallaData    SMALLDATETIME,
            @AllaData     SMALLDATETIME,
            @IdCalendario tvpId_char_16 READONLY,
            @IdTipo       tvpId_char_1  READONLY';

		SET @stmt = N'
        WITH tbl AS (
            SELECT
                Id = CASE e.IdTipo
                    WHEN ''S'' THEN s.Id
                    WHEN ''V'' THEN v.Id
                END,
                IdEvento         = e.Id,
                StatoValore      = IIF(e.[Data] < GETDATE(), 1, 0),
                StatoDescrizione = e.Stato + IIF(e.[Data] < GETDATE(), '' - Scaduto'', ''''),
                e.IdTipo,
                Tipo = CASE e.IdTipo
                    WHEN ''S'' THEN ''Scadenza''
                    WHEN ''V'' THEN ''Servizio''
                END,
                Testo            = e.AvvisoTesto,
                e.[Data],
                UrlDestinazione  = IIF(e.Assegnato = 1, ''/servizi/assegnati/'',
                    CASE e.IdTipo
                        WHEN ''S'' THEN ''/scadenze/scadenze/''
                        WHEN ''V'' THEN ''/servizi/servizi/''
                        ELSE ''''
                    END)
            FROM
                dbo.ufnEventi_get_All_List(@DallaData, @AllaData, @IdUtente, @IdCalendario, @IdTipo) e
                LEFT JOIN dbo.tblScadenze s WITH (NOLOCK) ON e.Id = s.IdEvento
                LEFT JOIN dbo.tblServizi  v WITH (NOLOCK) ON e.Id = v.IdEvento
            WHERE
                e.IdStato    = ''D''
                AND e.Avviso     = 1
                AND e.AvvisoData < GETDATE()';

		-- @Search come parametro, NON concatenato → nessun SQL Injection
		IF @Search IS NOT NULL
			SET @stmt = @stmt + N'
                AND e.AvvisoTesto LIKE ''%'' + @Search + ''%''';

		SET @stmt = @stmt + N'
        ),
        tblCount AS (SELECT COUNT(*) AS RowsCount FROM tbl)
        SELECT
            tbl.Id, tbl.IdEvento, tbl.StatoValore, tbl.StatoDescrizione,
            tbl.IdTipo, tbl.Tipo, tbl.Testo, tbl.[Data], tbl.UrlDestinazione,
            tblCount.RowsCount
        FROM tbl
        CROSS JOIN tblCount
        ORDER BY tbl.[Data]
        OFFSET @Offset ROWS
        FETCH NEXT @RowsPerPage ROWS ONLY;';

		EXEC sp_executesql
			@stmt,
			@params,
			@RowsPerPage = @RowsPerPage,
			@Offset = @Offset,
			@IdUtente = @IdUtente,
			@Search = @Search,
			@DallaData = @DallaData,
			@AllaData = @AllaData,
			@IdCalendario = @IdCalendario,
			@IdTipo = @IdTipo;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
