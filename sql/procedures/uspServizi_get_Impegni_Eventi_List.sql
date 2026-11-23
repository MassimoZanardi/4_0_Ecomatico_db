SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_Impegni_Eventi_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@AllaData SMALLDATETIME = NULL,
	@TipoRisorsa CHAR(1) = NULL,
	@Risorsa VARCHAR(50) = NULL,
	@PageNumber INT = NULL,
	@RowsPerPage INT = NULL,
	@SoloSovrapposti BIT = 0
AS
-- Servizi > Impegni a blocchi (S9.9): una riga per risorsa e servizio da @DallaData (compresa) ad @AllaData (esclusa),
-- con i campi del calendario a blocchi (uspServizi_get_Calendario_Eventi_List). Stesse risorse e stessi servizi di
-- uspServizi_get_Impegni_Elenco_List (S9.2, S9.3): persone e oggetti impiegabili dell'azienda del calendario del
-- contesto, servizi di tutti i calendari in cui sono impiegate, annullati esclusi; quelli dei calendari non visibili
-- all'utente sono "Occupato" (Visibile = 0), senza descrizione, risorse e serie. Risorse = le altre persone e oggetti
-- del servizio (la risorsa della riga e' la colonna della vista). Le colonne (anche le risorse senza servizi) le da'
-- uspServizi_get_Impegni_List
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permesso TINYINT;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		-- Filtro della finestra Cerca degli Impegni (S9.12): tipo di risorsa (P persone, O oggetti) e testo contenuto nel nome
		SET @TipoRisorsa = NULLIF(LTRIM(RTRIM(@TipoRisorsa)), '');
		SET @Risorsa = dbo.ufnStringhe_get_SenzaSpazi(@Risorsa, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DallaData IS NULL OR @AllaData IS NULL OR @AllaData <= @DallaData
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il periodo indicato non è valido';
			GOTO BRANCH_END;
		END

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

		-- Fine esclusa: ufnEventi_get_List prende gli estremi compresi
		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, -1, @AllaData);

		-- Azienda del calendario del contesto: senza calendario nessuna riga
		DECLARE @idAziendaInterna CHAR(16);
		SELECT @idAziendaInterna = s.IdAziendaInterna
		FROM
			dbo.tblSessioni e
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE e.Id = @IdSessione;

		-- Risorse: le righe di Servizi > Impegni (stesso filtro di uspServizi_get_Impegni_List)
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
			AND (@TipoRisorsa IS NULL OR u.Tipo = @TipoRisorsa)
			AND (@Risorsa IS NULL OR u.[Text] LIKE '%' + @Risorsa + '%')
		GROUP BY u.Id, u.Tipo;

		-- Solo con sovrapposizioni (S9.14): restano le risorse con almeno un servizio sovrapposto nel periodo, prima
		-- delle pagine (le pagine contano solo queste); i calendari sono quelli di tutti i loro servizi ("Occupato" conta)
		IF ISNULL(@SoloSovrapposti, 0) = 1
		BEGIN
			DECLARE @calendariSovrapposti tvpId_char_16;
			INSERT INTO @calendariSovrapposti (Id)
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

			DECLARE @tipiSovrapposti tvpId_char_1;
			INSERT INTO @tipiSovrapposti (Id) VALUES ('V');

			DELETE r
			FROM #tRisorse r
			WHERE NOT EXISTS (
				SELECT 1
				FROM dbo.ufnServizi_get_Sovrapposti_List(@DallaData, @fine, @calendariSovrapposti, @tipiSovrapposti) x
				WHERE x.IdOsepe = r.Id
			);
		END

		-- Paracadute (S9.13): le risorse a pagine, @RowsPerPage per pagina nello stesso ordine delle righe (prima le
		-- persone, poi gli oggetti, per nome); senza @RowsPerPage tutte. Le altre si tolgono qui, prima di leggere i
		-- servizi, cosi' il carico e' quello della sola pagina
		DECLARE @risorseCount INT = (SELECT COUNT(*) FROM #tRisorse);
		IF ISNULL(@RowsPerPage, 0) > 0
		BEGIN
			SET @PageNumber = IIF(ISNULL(@PageNumber, 0) < 1, 1, @PageNumber);
			DELETE r
			FROM
				#tRisorse r
				INNER JOIN (
					SELECT Id, Numero = ROW_NUMBER() OVER (ORDER BY IIF(Tipo = 'P', 0, 1), Risorsa, Id)
					FROM #tRisorse
				) n ON r.Id = n.Id
			WHERE n.Numero NOT BETWEEN (@PageNumber - 1) * @RowsPerPage + 1 AND @PageNumber * @RowsPerPage;
		END
		CREATE UNIQUE CLUSTERED INDEX IX_tRisorse_Id ON #tRisorse (Id);

		-- Calendari in cui le risorse sono impiegate, anche di sedi non accessibili all'utente ("Occupato")
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

		SELECT
			IdOsepe = r.Id,
			TipoRisorsa = r.Tipo,
			r.Risorsa,
			s.Id,
			s.IdEvento,
			IdSerie = IIF(v.Id IS NULL, NULL, ISNULL(s2.Id, s.Id)),
			e.[Data],
			InGiornata = CAST(ISNULL(e.InGiornata, 0) AS BIT),
			s.Durata,
			Stato = CASE
				WHEN e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE() THEN 'S'
				WHEN e.IdStato IN ('D', 'I') THEN 'D'
				ELSE e.IdStato
			END,
			StatoDescrizione = e.Stato + IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), ' - Scaduto', ''),
			Orario = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata),
			Descrizione = IIF(v.Id IS NULL, 'Occupato', ISNULL(NULLIF(CONCAT_WS(' - ', t.Nome, r0.NomeCompleto), ''), ISNULL(e.AvvisoTesto, ''))),
			Indirizzo = IIF(v.Id IS NULL, NULL, r0.IndirizzoCompleto),
			Risorse = IIF(v.Id IS NULL, NULL, a.Risorse),
			o.Quantita,
			Visibile = CAST(IIF(v.Id IS NULL, 0, 1) AS BIT),
			e.Ricorre,
			e.Eccezione
		FROM
			dbo.ufnEventi_get_List(@DallaData, @fine, @IdCalendario, @IdTipo) e
			INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
			INNER JOIN dbo.tblServiziOsepe o ON s.Id = o.Id
			INNER JOIN #tRisorse r ON o.IdOsepe = r.Id
			LEFT JOIN #tCalendariVisibili v ON e.IdCalendario = v.Id
			LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
			LEFT JOIN dbo.tblSedi r0 ON s.IdRichiedente = r0.Id
			-- Serie dell'occorrenza modificata (come uspServizi_get_ByData_List)
			OUTER APPLY (
				SELECT TOP (1) s3.Id
				FROM
					dbo.tblRicorrenzeEccezioni zs
					INNER JOIN dbo.tblServizi s3 ON zs.Id = s3.IdEvento
				WHERE
					zs.IdEvento = s.IdEvento
					AND zs.Lock = 0
					AND e.Ricorre = 0
			) s2
			-- Le altre persone e oggetti del servizio (la risorsa della riga e' la colonna)
			OUTER APPLY (
				SELECT Risorse = STRING_AGG(n.Nome, ', ') WITHIN GROUP (ORDER BY x.Tipo, n.Nome)
				FROM
					dbo.tblServiziOsepe so
					INNER JOIN dbo.tblOsepe x ON so.IdOsepe = x.Id
					CROSS APPLY (
						SELECT Nome = p.NomeCompleto FROM dbo.tblPersone p WHERE p.Id = so.IdOsepe AND x.Tipo = 'P'
						UNION ALL
						SELECT Nome = g.Nome FROM dbo.tblOggetti g WHERE g.Id = so.IdOsepe AND x.Tipo = 'O'
					) n
				WHERE
					so.Id = s.Id
					AND so.IdOsepe <> o.IdOsepe
			) a
		WHERE e.IdStato <> 'A'
		ORDER BY r.Risorsa, r.Id, e.[Data], s.Id
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
