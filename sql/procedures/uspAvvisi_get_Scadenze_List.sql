SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspAvvisi_get_Scadenze_List]
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

		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Pagina dedicata: nega esplicitamente l'accesso senza permesso SCD, come le
		-- altre pagine dell'app (Limiti/Autorizzazioni).
		DECLARE @permesso TINYINT = dbo.ufnFunzioni_get_PermessoByUtente('SCD', @IdUtente);
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;
		DECLARE @countData DATETIME = GETDATE();

		-- Finestra temporale: ultimi 30 giorni → prossime 4 settimane (stessa di uspAvvisi_get_Count)
		DECLARE @DallaData SMALLDATETIME = DATEADD(DAY, -30, @countData);
		DECLARE @AllaData SMALLDATETIME = DATEADD(DAY, 28, @countData);

		-- Permesso già verificato sopra: niente branching AD/US, filtro diretto sul modulo.
		DECLARE @IdCalendario tvpId_Char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT c.Id
		FROM dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) s
		INNER JOIN dbo.tblCalendari c ON s.Id = c.IdSede
		WHERE c.Lock = 0 AND c.IdModulo = 'SCD';

		DECLARE @IdTipo tvpId_Char_1;
		INSERT INTO @IdTipo (Id) VALUES ('S');

		;WITH tbl AS (
			SELECT
				Id = s.Id,
				IdEvento = e.Id,
				StatoValore = IIF(e.[Data] < GETDATE(), 1, 0),
				StatoDescrizione = e.Stato + IIF(e.[Data] < GETDATE(), ' - Scaduto', ''),
				Testo = e.AvvisoTesto,
				e.[Data],
				Tipo = t.Nome,
				Sede = sd.Nome,
				Calendario = cal.Nome,
				UrlDestinazione = '/scadenze/scadenze/'
			FROM
				dbo.ufnEventi_get_All_List(@DallaData, @AllaData, @IdUtente, @IdCalendario, @IdTipo) e
				LEFT JOIN dbo.tblScadenze s WITH (NOLOCK) ON e.Id = s.IdEvento
				LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
				INNER JOIN dbo.tblCalendari cal ON e.IdCalendario = cal.Id
				INNER JOIN dbo.tblSedi sd ON cal.IdSede = sd.Id
			WHERE
				e.IdStato = 'D'
				AND e.Avviso = 1
				AND e.AvvisoData < @countData
				AND (@Search IS NULL OR e.AvvisoTesto LIKE '%' + @Search + '%')
		),
		tblCount AS (SELECT COUNT(*) AS RowsCount FROM tbl)
		SELECT
			tbl.Id,
			tbl.IdEvento,
			tbl.StatoValore,
			tbl.StatoDescrizione,
			tbl.Testo,
			tbl.[Data],
			tbl.Tipo,
			tbl.Sede,
			tbl.Calendario,
			tbl.UrlDestinazione,
			tblCount.RowsCount
		FROM tbl
		CROSS JOIN tblCount
		ORDER BY tbl.[Data]
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

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
GO
