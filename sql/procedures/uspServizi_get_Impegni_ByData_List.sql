SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_Impegni_ByData_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdOsepe CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@IdIntervallo CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOsepe = NULLIF(LTRIM(RTRIM(@IdOsepe)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @PageNumber = IIF(ISNULL(@PageNumber, 0) < 1, 1, @PageNumber);
		SET @RowsPerPage = IIF(ISNULL(@RowsPerPage, 0) < 1, 50, @RowsPerPage);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdOsepe IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdOsepe non può essere vuoto';
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
		IF @IdIntervallo NOT IN ('1H', 'IG', '1D')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non è valido';
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

		-- La risorsa deve essere tra le righe di Servizi > Impegni (stesso filtro di
		-- uspServizi_get_Impegni_List): persona o oggetto impiegabile dell'azienda del calendario
		-- del contesto, o condiviso tramite le Aree
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSessioni e
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
				CROSS APPLY dbo.ufnOsepe_get_ByUtente_List(e.IdUtente) u
			WHERE
				e.Id = @IdSessione
				AND u.Id = @IdOsepe
				AND
					(
						(
						u.IdDominio = e.IdDominio
						AND u.Condivisa = 1
						)
					OR u.IdSede = s.IdAziendaInterna
					)
				AND u.Tipo IN ('P', 'O')
				AND u.Disabilitata = 0
				AND u.ImpiegabileServizi = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		/*
		*   Cella di Servizi > Impegni
		*   1H = ora della vista Giorno (hh:00-hh:59), senza i servizi "In giornata"
		*   IG = colonna "In giornata" della vista Giorno
		*   1D = giorno delle viste Settimana e Mese, tutti i servizi del giorno
		*/
		DECLARE @inizio SMALLDATETIME = IIF(@IdIntervallo = '1H', @DallaData, CAST(CAST(@DallaData AS DATE) AS SMALLDATETIME));
		DECLARE @fine SMALLDATETIME = IIF(@IdIntervallo = '1H',
			DATEADD(MINUTE, 59, @inizio),
			DATEADD(MINUTE, 59, DATEADD(HOUR, 23, @inizio)));

		-- Solo i calendari delle sedi accessibili all'utente in cui la risorsa e' impiegata:
		-- i servizi degli altri calendari compaiono nella cella come "Occupato" ma non si elencano
		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT DISTINCT e.IdCalendario
		FROM
			dbo.tblServiziOsepe o
			INNER JOIN dbo.tblServizi s ON o.Id = s.Id
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE
			o.IdOsepe = @IdOsepe
			AND e.IdTipo = 'V'
			AND e.Lock = 0;

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('V');

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		;WITH tbl AS (
			SELECT
				s.Id,
				StatoValore = CASE
					WHEN e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE() THEN 1
					WHEN e.IdStato = 'A' THEN 2
					ELSE 0
				END,
				StatoDescrizione = e.Stato + IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), ' - Scaduto', ''),
				IdSerie = ISNULL(s2.Id, s.Id),
				Descrizione = e.AvvisoTesto,
				s.IdEvento,
				e.[Data],
				e.Ricorre,
				e.Eccezione
			FROM
				dbo.tblServizi s
				INNER JOIN dbo.ufnEventi_get_List(@inizio, @fine, @IdCalendario, @IdTipo) e ON s.IdEvento = e.Id
				INNER JOIN dbo.tblServiziOsepe o ON s.Id = o.Id
				LEFT JOIN dbo.tblServizi s2 ON e.IdEccezione = s2.IdEvento
			WHERE
				o.IdOsepe = @IdOsepe
				AND e.IdStato <> 'A'
				AND
					(
					@IdIntervallo = '1D'
					OR
						(
						@IdIntervallo = '1H'
						AND ISNULL(e.InGiornata, 0) = 0
						)
					OR
						(
						@IdIntervallo = 'IG'
						AND ISNULL(e.InGiornata, 0) = 1
						)
					)
		)
		SELECT
			tbl.Id,
			tbl.StatoValore,
			tbl.StatoDescrizione,
			tbl.IdSerie,
			tbl.Descrizione,
			tbl.IdEvento,
			tbl.[Data],
			tbl.Ricorre,
			tbl.Eccezione,
			RowsCount = COUNT(*) OVER ()
		FROM tbl
		ORDER BY tbl.[Data], tbl.Id
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
GO
