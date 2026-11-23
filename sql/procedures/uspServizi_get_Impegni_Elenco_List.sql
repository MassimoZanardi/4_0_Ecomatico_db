SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_Impegni_Elenco_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Etichetta VARCHAR(50) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdOsepe CHAR(16) = NULL,
	@SoloSovrapposti BIT = 0
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
		SET @Stato = ISNULL(NULLIF(LTRIM(RTRIM(@Stato)), ''), 'T');
		SET @IdOsepe = NULLIF(LTRIM(RTRIM(@IdOsepe)), '');
		SET @Etichetta = dbo.ufnStringhe_get_SenzaSpazi(@Etichetta, 0, 1);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @PageNumber = IIF(ISNULL(@PageNumber, 0) < 1, 1, @PageNumber);
		SET @RowsPerPage = IIF(ISNULL(@RowsPerPage, 0) < 1, 50, @RowsPerPage);

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
		IF @IdIntervallo NOT IN ('1D', '1W', '2W', '1M', '2M', '6M', '1Y')
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

		/*
		*   Periodo: dalla data (00:00) per l'intervallo scelto, fine esclusa (1 giorno = il solo giorno della
		*   data, 1 settimana = 7 giorni). Il servizio termina entro la mezzanotte del giorno di inizio
		*   (uspServizi_upd): basta leggere i servizi che iniziano nel periodo
		*/
		DECLARE @inizio SMALLDATETIME = CAST(CAST(@DallaData AS DATE) AS SMALLDATETIME);
		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, -1, CASE @IdIntervallo
			WHEN '1D' THEN DATEADD(DAY, 1, @inizio)
			WHEN '1W' THEN DATEADD(WEEK, 1, @inizio)
			WHEN '2W' THEN DATEADD(WEEK, 2, @inizio)
			WHEN '1M' THEN DATEADD(MONTH, 1, @inizio)
			WHEN '2M' THEN DATEADD(MONTH, 2, @inizio)
			WHEN '6M' THEN DATEADD(MONTH, 6, @inizio)
			ELSE DATEADD(YEAR, 1, @inizio)
		END);

		-- Azienda del calendario del contesto: senza calendario nessuna riga
		DECLARE @idAziendaInterna CHAR(16);
		SELECT @idAziendaInterna = s.IdAziendaInterna
		FROM
			dbo.tblSessioni e
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE e.Id = @IdSessione;

		-- Risorse: le righe di Servizi > Impegni (stesso filtro di uspServizi_get_Impegni_List), eventualmente
		-- la sola risorsa indicata. Una risorsa che non e' tra queste non da' righe
		SELECT
			u.Id,
			u.Tipo,
			Risorsa = MAX(u.[Text])
		INTO #tRisorse
		FROM
			dbo.tblSessioni e
			CROSS APPLY dbo.ufnOsepe_get_ByUtente_List(e.IdUtente) u
		WHERE
			e.Id = @IdSessione
			AND @idAziendaInterna IS NOT NULL
			AND (@IdOsepe IS NULL OR u.Id = @IdOsepe)
			AND
				(
					(
					u.IdDominio = e.IdDominio
					AND u.Condivisa = 1
					)
				OR u.IdSede = @idAziendaInterna
				)
			AND u.Tipo IN ('P', 'O')
			AND u.Disabilitata = 0
			AND u.ImpiegabileServizi = 1
		GROUP BY u.Id, u.Tipo;

		CREATE UNIQUE CLUSTERED INDEX IX_tRisorse_Id ON #tRisorse (Id);

		-- Calendari in cui le risorse sono impiegate, anche di sedi non accessibili all'utente: i loro servizi
		-- compaiono come "Occupato", senza descrizione, tipo ed etichette (come nelle celle degli Impegni)
		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id)
		SELECT DISTINCT e.IdCalendario
		FROM
			#tRisorse r
			INNER JOIN dbo.tblServiziOsepe o ON r.Id = o.IdOsepe
			INNER JOIN dbo.tblServizi s ON o.Id = s.Id
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
		WHERE
			e.IdTipo = 'V'
			AND e.Lock = 0
			AND e.IdCalendario IS NOT NULL;

		-- Calendari con il dettaglio visibile: quelli delle sedi interne accessibili all'utente
		SELECT DISTINCT c.Id
		INTO #tCalendariVisibili
		FROM
			dbo.tblCalendari c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id IN (SELECT Id FROM @IdCalendario);

		DECLARE @IdTipo tvpId_char_1;
		INSERT INTO @IdTipo (Id) VALUES ('V');

		-- Solo con sovrapposizioni (S9.14): le occorrenze sovrapposte del periodo per risorsa, calcolate su tutti i
		-- calendari delle risorse ("Occupato" conta), prima della pagina
		CREATE TABLE #tSovrapposti (
			IdOsepe CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
			IdServizio CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
			Inizio SMALLDATETIME NOT NULL
		);
		IF ISNULL(@SoloSovrapposti, 0) = 1
			INSERT INTO #tSovrapposti (IdOsepe, IdServizio, Inizio)
			SELECT x.IdOsepe, x.IdServizio, x.Inizio
			FROM
				dbo.ufnServizi_get_Sovrapposti_List(@inizio, @fine, @IdCalendario, @IdTipo) x
				INNER JOIN #tRisorse r ON x.IdOsepe = r.Id;

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		/*
		*   Una riga per risorsa e occorrenza del servizio, annullati esclusi (S9.3), in ordine di data e risorsa.
		*   Descrizione ed etichette si cercano solo nei servizi dei calendari visibili: un servizio "Occupato"
		*   non deve rivelare il suo contenuto attraverso la ricerca. Prima la pagina sulle chiavi, poi i dettagli
		*   (come uspServizi_get_List). Per le occorrenze generate stato ed etichette sono quelli della serie
		*/
		;WITH tbl AS (
			SELECT
				IdOsepe = r.Id,
				r.Risorsa,
				s.Id,
				IdEvento = e.Id,
				e.[Data],
				e.IdStato,
				e.Stato,
				e.InGiornata,
				e.Ricorre,
				e.Eccezione,
				e.Etichette,
				Visibile = IIF(v.Id IS NULL, 0, 1)
			FROM
				dbo.ufnEventi_get_List(@inizio, @fine, @IdCalendario, @IdTipo) e
				INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
				INNER JOIN dbo.tblServiziOsepe o ON s.Id = o.Id
				INNER JOIN #tRisorse r ON o.IdOsepe = r.Id
				LEFT JOIN #tCalendariVisibili v ON e.IdCalendario = v.Id
			WHERE
				e.IdStato <> 'A'
				AND
					(
					ISNULL(@SoloSovrapposti, 0) = 0
					OR EXISTS (SELECT 1 FROM #tSovrapposti x WHERE x.IdOsepe = r.Id AND x.IdServizio = s.Id AND x.Inizio = e.[Data])
					)
				AND
					(
					@Stato = 'T'
					OR (@Stato = 'S' AND e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE())
					OR e.IdStato = @Stato
					)
				AND
					(
					@Search IS NULL
					OR (v.Id IS NOT NULL AND s.Descrizione LIKE '%' + @Search + '%')
					)
				AND
					(
					@Etichetta IS NULL
					OR
						(
						v.Id IS NOT NULL
						AND s.IdEvento IN (
							SELECT t.Id
							FROM
								dbo.tblEventiEtichette t
								INNER JOIN dbo.tblEtichette et ON t.IdEtichetta = et.Id
							WHERE et.Nome LIKE '%' + @Etichetta + '%'
							)
						)
					)
		),
		pagina AS (
			SELECT
				tbl.*,
				RowsCount = COUNT(*) OVER ()
			FROM tbl
			ORDER BY tbl.[Data], tbl.Risorsa, tbl.IdOsepe, tbl.Id
			OFFSET @Offset ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
		)
		SELECT
			p.IdOsepe,
			TipoRisorsa = r.Tipo,
			p.Risorsa,
			p.Id,
			StatoValore = CASE
				WHEN p.IdStato IN ('D', 'I') AND p.[Data] < GETDATE() THEN 1
				ELSE 0
			END,
			StatoDescrizione = p.Stato + IIF(p.IdStato IN ('D', 'I') AND p.[Data] < GETDATE(), ' - Scaduto', ''),
			IdSerie = ISNULL(s2.Id, p.Id),
			p.IdEvento,
			p.[Data],
			InGiornata = CAST(ISNULL(p.InGiornata, 0) AS BIT),
			s.Durata,
			o.Quantita,
			Tipo = IIF(p.Visibile = 1, t.Nome, NULL),
			Descrizione = IIF(p.Visibile = 1, s.Descrizione, 'Occupato'),
			Etichette = IIF(p.Visibile = 1, p.Etichette, NULL),
			Visibile = CAST(p.Visibile AS BIT),
			p.Ricorre,
			p.Eccezione,
			p.RowsCount
		FROM
			pagina p
			INNER JOIN #tRisorse r ON p.IdOsepe = r.Id
			INNER JOIN dbo.tblServizi s ON p.Id = s.Id
			INNER JOIN dbo.tblServiziOsepe o ON p.Id = o.Id AND p.IdOsepe = o.IdOsepe
			INNER JOIN dbo.tblTipi t ON s.IdTipo = t.Id
			-- Serie dell'occorrenza modificata (sostituto di un'eccezione): "Tutta la serie" apre la serie
			OUTER APPLY (
				SELECT TOP (1) s3.Id
				FROM
					dbo.tblRicorrenzeEccezioni zs
					INNER JOIN dbo.tblServizi s3 ON zs.Id = s3.IdEvento
				WHERE
					zs.IdEvento = p.IdEvento
					AND zs.Lock = 0
					AND p.Ricorre = 0
			) s2
		ORDER BY p.[Data], p.Risorsa, p.IdOsepe, p.Id
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
