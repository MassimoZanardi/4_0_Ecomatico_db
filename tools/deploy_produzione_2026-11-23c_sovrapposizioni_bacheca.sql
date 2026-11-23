/*
	Deploy produzione - rilascio successivo al 2026-11-23 - Impegni: Solo con sovrapposizioni; Servizi > Assegnati:
	vista Bacheca

	Da eseguire DOPO i due script del 2026-11-23 (deploy_produzione_2026-11-23_servizi_impegni_calendari.sql e
	l'integrativo deploy_produzione_2026-11-23b_trascinamento_mezzore.sql): contiene i commit del repo DB dopo e3f2c3a,
	fino a fae0347. Solo 4_0_ecomatico. Una funzione e cinque stored procedure CREATE OR ALTER, l'indirizzo di una
	voce di menu (aggiornato solo se manca): lo script e' rieseguibile. Nessun dato dei clienti modificato. Da
	eseguire da SSMS sul database 4_0_ecomatico (o con sqlcmd -f 65001 -I).

	Prima il DB, poi SUBITO l'app (commit 4.0 9c6c8fd o successivo): la voce di menu Servizi > Assegnati porta alla
	pagina Bacheca, che l'app precedente non ha. Le SP con parametri in piu' non disturbano l'app precedente.

	1. ufnServizi_get_Sovrapposti_List (nuova): servizi sovrapposti per risorsa nel periodo (S9.14).
	2-4. uspServizi_get_Impegni_List, _Eventi_List, _Elenco_List: @SoloSovrapposti (filtro Solo con sovrapposizioni).
	5. uspServiziAssegnati_get_Bacheca_List (nuova): servizi assegnati del giorno e rimasti indietro (S7.6).
	6. uspServiziAssegnati_upd_Stato (nuova): Inizia, da eseguire a in esecuzione.
	7. Menu: Servizi > Assegnati apre la Bacheca (tblPagine SRA, Url assegnati/bacheca).

	In fondo la verifica: funzione e procedure con data di modifica e QUOTED_IDENTIFIER, e la voce di menu.
*/

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

-- ===== 1. ufnServizi_get_Sovrapposti_List (sql/functions/ufnServizi_get_Sovrapposti_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnServizi_get_Sovrapposti_List] (
	@DallaData SMALLDATETIME,
	@AllaData SMALLDATETIME,
	@IdCalendario tvpId_char_16 READONLY,
	@IdTipo tvpId_char_1 READONLY)
RETURNS TABLE
-- WITH SCHEMABINDING non applicabile: dipende da TVP (tvpId_char_16, tvpId_char_1)
-- che non sono oggetti schema-bound
AS
-- Servizi sovrapposti per risorsa (S9.4.1, filtro "Solo con sovrapposizioni" degli Impegni, S9.14): una riga per
-- risorsa e occorrenza del servizio (IdServizio + Inizio, le occorrenze generate di una serie hanno lo stesso servizio
-- e date diverse) che si accavalla davvero con un'altra della stessa risorsa: inizia prima della sua fine e finisce
-- dopo il suo inizio. Senza durata conta il solo minuto di inizio; i servizi "In giornata" non hanno un'ora e non si
-- confrontano; annullati esclusi. Stessa regola delle viste a blocchi (calendario-blocchi.js, segnaSovrapposti) e di
-- uspServizi_get_Impegni_List. @IdCalendario: i calendari di tutti i servizi delle risorse, anche quelli non visibili
-- ("Occupato" conta), @IdTipo = 'V'. Il servizio termina entro la mezzanotte del giorno di inizio (uspServizi_upd),
-- quindi bastano i servizi che iniziano nel periodo
RETURN
(
	WITH cteServizi AS (
		SELECT
			o.IdOsepe,
			IdServizio = s.Id,
			Inizio = e.[Data],
			Fine = DATEADD(MINUTE, ISNULL(s.Durata, 1), e.[Data])
		FROM
			dbo.ufnEventi_get_List(@DallaData, @AllaData, @IdCalendario, @IdTipo) e
			INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
			INNER JOIN dbo.tblServiziOsepe o ON s.Id = o.Id
		WHERE
			e.IdStato <> 'A'
			AND ISNULL(e.InGiornata, 0) = 0
	)
	SELECT DISTINCT
		a.IdOsepe,
		a.IdServizio,
		a.Inizio
	FROM
		cteServizi a
		INNER JOIN cteServizi b ON
			b.IdOsepe = a.IdOsepe
			AND NOT (b.IdServizio = a.IdServizio AND b.Inizio = a.Inizio)
			AND b.Inizio < a.Fine
			AND a.Inizio < b.Fine
);
GO
GO

-- ===== 2. uspServizi_get_Impegni_List (sql/procedures/uspServizi_get_Impegni_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_Impegni_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@IdVista CHAR(1) = NULL,
	@TipoRisorsa CHAR(1) = NULL,
	@Risorsa VARCHAR(50) = NULL,
	@PageNumber INT = NULL,
	@RowsPerPage INT = NULL,
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
		-- Filtro della finestra Cerca degli Impegni (S9.12): tipo di risorsa (P persone, O oggetti) e testo contenuto nel nome
		SET @TipoRisorsa = NULLIF(LTRIM(RTRIM(@TipoRisorsa)), '');
		SET @Risorsa = dbo.ufnStringhe_get_SenzaSpazi(@Risorsa, 0, 1);
		SET @IdVista = NULLIF(LTRIM(RTRIM(@IdVista)), '');

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
		IF @IdVista IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdVista non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdVista NOT IN ('G', 'S', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdVista non è valido';
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
		*   Periodo della vista
		*   G = Giorno     → dalle 00:00 alle 23:59 del giorno, una colonna per ora + "In giornata"
		*   S = Settimana  → dal lunedi' alla domenica della settimana della data, una colonna per giorno
		*   M = Mese       → dal primo all'ultimo giorno del mese della data, una colonna per giorno
		*/
		DECLARE @inizio SMALLDATETIME = CAST(CAST(@DallaData AS DATE) AS SMALLDATETIME);
		IF @IdVista = 'S'
			SET @inizio = DATEADD(DAY, 1 - DATEPART(DW, @inizio), @inizio);
		ELSE IF @IdVista = 'M'
			SET @inizio = DATEFROMPARTS(YEAR(@inizio), MONTH(@inizio), 1);

		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, -1, CASE @IdVista
			WHEN 'G' THEN DATEADD(DAY, 1, @inizio)
			WHEN 'S' THEN DATEADD(DAY, 7, @inizio)
			ELSE DATEADD(MONTH, 1, @inizio)
		END);

		-- Azienda del calendario del contesto: senza calendario nessuna riga
		DECLARE @idAziendaInterna CHAR(16);
		SELECT @idAziendaInterna = s.IdAziendaInterna
		FROM
			dbo.tblSessioni e
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE e.Id = @IdSessione;

		-- Risorse (righe): persone e oggetti impiegabili nei servizi dell'azienda del calendario,
		-- compresi quelli condivisi tramite le Aree (stesso filtro di uspOsepe_get_SelectList
		-- con @Contesto = 5 e @ImpiegabileServizi = 1)
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
				FROM dbo.ufnServizi_get_Sovrapposti_List(@inizio, @fine, @calendariSovrapposti, @tipiSovrapposti) x
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

		-- Calendari in cui le risorse sono impiegate: tutti, anche quelli di sedi non accessibili
		-- all'utente, perche' l'impegno della risorsa sia completo (i servizi di quei calendari
		-- contano come "Occupato", senza descrizione)
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

		-- Servizi del periodo per risorsa, annullati esclusi. La colonna (Data) e' l'inizio della
		-- cella: l'ora (hh:00) nella vista Giorno, il giorno (00:00) nelle viste Settimana e Mese;
		-- nella vista Giorno i servizi "In giornata" vanno nella colonna dedicata (InGiornata = 1).
		-- Durata (minuti, facoltativa): nella vista Giorno il servizio occupa ogni ora che tocca, dall'ora
		-- di inizio a quella dell'ultimo minuto (h); senza durata la sola ora di inizio. Il servizio
		-- termina entro la mezzanotte del giorno di inizio (uspServizi_upd), quindi resta nel suo giorno e
		-- basta leggere i servizi che iniziano nel periodo. Durata del servizio di una serie: e' quella
		-- della serie (s.IdEvento = e.Id, l'Id della serie per le occorrenze generate)
		SELECT
			IdOsepe = r.Id,
			[Data] = CASE
				WHEN @IdVista = 'G' AND ISNULL(e.InGiornata, 0) = 0
					THEN DATEADD(HOUR, h.value, CAST(CAST(e.[Data] AS DATE) AS SMALLDATETIME))
				ELSE CAST(CAST(e.[Data] AS DATE) AS SMALLDATETIME)
			END,
			InGiornata = CAST(IIF(@IdVista = 'G' AND ISNULL(e.InGiornata, 0) = 1, 1, 0) AS BIT),
			Scaduto = IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0),
			Eseguito = IIF(e.IdStato = 'E', 1, 0),
			Minuti = ISNULL(s.Durata, 0),
			Testo = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata) + ' - '
				+ IIF(v.Id IS NULL, 'Occupato', ISNULL(e.AvvisoTesto, '')),
			-- Occorrenza del servizio (le occorrenze generate di una serie hanno lo stesso servizio e date diverse)
			-- con l'orario vero, per le sovrapposizioni: senza durata conta il solo minuto di inizio;
			-- i servizi "In giornata" non hanno un'ora e non si confrontano (Oraria = 0)
			IdServizio = s.Id,
			Inizio = e.[Data],
			Fine = DATEADD(MINUTE, ISNULL(s.Durata, 1), e.[Data]),
			Oraria = IIF(ISNULL(e.InGiornata, 0) = 0, 1, 0),
			Sovrapposto = 0
		INTO #tEventi
		FROM
			dbo.ufnEventi_get_List(@inizio, @fine, @IdCalendario, @IdTipo) e
			INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
			INNER JOIN dbo.tblServiziOsepe o ON s.Id = o.Id
			INNER JOIN #tRisorse r ON o.IdOsepe = r.Id
			LEFT JOIN #tCalendariVisibili v ON e.IdCalendario = v.Id
			-- Ore occupate nella vista Giorno (una riga per ora); nelle altre viste e per "In giornata" una sola riga
			CROSS APPLY GENERATE_SERIES(
				DATEPART(HOUR, e.[Data]),
				IIF(@IdVista = 'G' AND ISNULL(e.InGiornata, 0) = 0 AND s.Durata IS NOT NULL,
					DATEPART(HOUR, DATEADD(MINUTE, s.Durata - 1, e.[Data])),
					DATEPART(HOUR, e.[Data]))) h
		WHERE e.IdStato <> 'A';

		-- Sovrapposizioni vere: nella stessa cella un servizio e' sovrapposto se un altro servizio della risorsa
		-- inizia prima della sua fine e finisce dopo il suo inizio. Due servizi in fila nella stessa ora
		-- (09:00-09:30 e 09:30-10:00) contano come 2 eventi ma non sono sovrapposti
		UPDATE a
		SET Sovrapposto = 1
		FROM #tEventi a
		WHERE
			a.Oraria = 1
			AND EXISTS (
				SELECT 1
				FROM #tEventi b
				WHERE
					b.IdOsepe = a.IdOsepe
					AND b.[Data] = a.[Data]
					AND b.InGiornata = a.InGiornata
					AND b.Oraria = 1
					AND NOT (b.IdServizio = a.IdServizio AND b.Inizio = a.Inizio)
					AND b.Inizio < a.Fine
					AND a.Inizio < b.Fine
			);

		SELECT
			r.Id AS IdOsepe,
			r.Tipo,
			r.Risorsa,
			d.[Data],
			InGiornata = ISNULL(d.InGiornata, CAST(0 AS BIT)),
			Eventi = ISNULL(d.Eventi, 0),
			Scaduti = ISNULL(d.Scaduti, 0),
			Eseguiti = ISNULL(d.Eseguiti, 0),
			Minuti = ISNULL(d.Minuti, 0),
			Sovrapposti = ISNULL(d.Sovrapposti, 0),
			d.Testo,
			-- Tutte le risorse del filtro, per l'indicatore delle pagine
			RisorseCount = @risorseCount
		FROM
			#tRisorse r
			LEFT JOIN (
				SELECT
					IdOsepe,
					[Data],
					InGiornata,
					Eventi = COUNT(*),
					Scaduti = SUM(Scaduto),
					Eseguiti = SUM(Eseguito),
					-- Somma delle durate indicate (viste Settimana e Mese: ore impegnate nel giorno)
					Minuti = SUM(Minuti),
					-- Servizi della cella che si accavallano davvero con un altro
					Sovrapposti = SUM(Sovrapposto),
					-- Usato dalla cella solo quando c'e' un servizio
					Testo = MAX(Testo)
				FROM #tEventi
				GROUP BY IdOsepe, [Data], InGiornata
			) d ON r.Id = d.IdOsepe
		ORDER BY IIF(r.Tipo = 'P', 0, 1), r.Risorsa, r.Id, d.InGiornata DESC, d.[Data];

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
GO

-- ===== 3. uspServizi_get_Impegni_Eventi_List (sql/procedures/uspServizi_get_Impegni_Eventi_List.sql)
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
GO

-- ===== 4. uspServizi_get_Impegni_Elenco_List (sql/procedures/uspServizi_get_Impegni_Elenco_List.sql)
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
GO

-- ===== 5. uspServiziAssegnati_get_Bacheca_List (sql/procedures/uspServiziAssegnati_get_Bacheca_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServiziAssegnati_get_Bacheca_List]
	@IdSessione CHAR(16) = NULL,
	@Data SMALLDATETIME = NULL
AS
-- Servizi > Assegnati, vista Bacheca (S7.6): i servizi del calendario del contesto assegnati all'utente della sessione
-- nel giorno @Data, annullati esclusi, piu' quelli rimasti indietro, qualunque sia il giorno guardato: da eseguire con
-- la data di un giorno passato (riquadro Scaduti) e in esecuzione dei giorni passati (colonna In esecuzione).
-- Colonna: S scaduti, D da eseguire, I in esecuzione, E eseguiti. Come uspServiziAssegnati_get_List mostra i servizi
-- singoli e le occorrenze modificate (ufnEventi_get_Assegnati_List), mai le occorrenze generate di una serie
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
		IF @Data IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Data non può essere vuoto';
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

		DECLARE @idUtente CHAR(16);
		DECLARE @idCal CHAR(16);

		SELECT @idUtente = IdUtente, @idCal = IdCalendario
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		DECLARE @IdCalendario tvpId_char_16;
		INSERT INTO @IdCalendario (Id) SELECT @idCal
		WHERE @idCal IS NOT NULL;

		-- Il giorno guardato e l'inizio di oggi: prima di oggi i servizi da eseguire o in esecuzione sono rimasti indietro
		DECLARE @inizio SMALLDATETIME = CAST(CAST(@Data AS DATE) AS SMALLDATETIME);
		DECLARE @fine SMALLDATETIME = DATEADD(MINUTE, -1, DATEADD(DAY, 1, @inizio));
		DECLARE @oggi SMALLDATETIME = CAST(CAST(GETDATE() AS DATE) AS SMALLDATETIME);
		DECLARE @ieri SMALLDATETIME = DATEADD(MINUTE, -1, @oggi);

		;WITH cteEventi AS (
			-- Il giorno guardato
			SELECT e.Id, e.IdStato, e.[Data], e.InGiornata
			FROM dbo.ufnEventi_get_Assegnati_List(@inizio, @fine, @idUtente, @IdCalendario) e
			WHERE e.IdStato <> 'A'
			UNION
			-- Rimasti indietro, dai giorni passati
			SELECT e.Id, e.IdStato, e.[Data], e.InGiornata
			FROM dbo.ufnEventi_get_Assegnati_List('19000101', @ieri, @idUtente, @IdCalendario) e
			WHERE e.IdStato IN ('D', 'I')
		)
		SELECT
			s.Id,
			s.IdEvento,
			e.[Data],
			InGiornata = CAST(ISNULL(e.InGiornata, 0) AS BIT),
			s.Durata,
			e.IdStato,
			Colonna = CASE
				WHEN e.IdStato = 'D' AND e.[Data] < @oggi THEN 'S'
				ELSE e.IdStato
			END,
			-- Come negli altri elenchi: da eseguire o in esecuzione con la data passata (anche oggi, a un'ora gia' passata)
			Scaduto = CAST(IIF(e.IdStato IN ('D', 'I') AND e.[Data] < GETDATE(), 1, 0) AS BIT),
			Orario = dbo.ufnServizi_get_Orario(e.[Data], e.InGiornata, s.Durata),
			Tipo = t.Nome,
			Richiedente = r.NomeCompleto,
			Indirizzo = r.IndirizzoCompleto,
			ev.Etichette,
			-- Proprieta' del tipo compilate (con un valore) e in tutto, per l'icona della scheda. Le caselle si/no (tipo dato
			-- B) non contano: la scheda le salva sempre (false se non spuntate) e "no" e' gia' una risposta
			ProprietaCompilate = ISNULL(p.Compilate, 0),
			ProprietaTotali = ISNULL(p.Totali, 0)
		FROM
			cteEventi e
			INNER JOIN dbo.tblEventi ev ON e.Id = ev.Id
			INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
			LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
			LEFT JOIN dbo.tblSedi r ON s.IdRichiedente = r.Id
			OUTER APPLY (
				SELECT
					Totali = COUNT(*),
					Compilate = SUM(IIF(NULLIF(LTRIM(RTRIM(v.Valore)), '') IS NULL, 0, 1))
				FROM
					dbo.tblTipiProprieta tp
					LEFT JOIN dbo.tblEventiProprieta v ON v.Id = e.Id AND v.IdProprieta = tp.IdProprieta
					INNER JOIN dbo.tblProprieta pr ON tp.IdProprieta = pr.Id
				WHERE
					tp.Id = s.IdTipo
					AND tp.Lock = 0
					AND pr.IdTipoDato <> 'B'
			) p
		ORDER BY
			e.[Data],
			s.Id;

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
GO

-- ===== 6. uspServiziAssegnati_upd_Stato (sql/procedures/uspServiziAssegnati_upd_Stato.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServiziAssegnati_upd_Stato]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL
AS
-- Servizi > Assegnati, vista Bacheca (S7.6): pulsante Inizia, il servizio da eseguire passa a In esecuzione. Solo
-- questo passaggio: concludere (Eseguito) richiede la scheda, con le proprieta' e la firma, e tornare indietro si fa
-- dalla scheda. Stessi controlli di uspServiziAssegnati_upd: permesso di modifica su SRV o SRA, servizio di un
-- calendario di una sede accessibile e assegnato all'utente della sessione (S7.3). In Servizi > Assegnati ci sono solo
-- servizi singoli e occorrenze modificate, quindi si cambia sempre un solo evento
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permessoSrv TINYINT;
		DECLARE @permessoSra TINYINT;
		DECLARE @idEvento CHAR(16);
		DECLARE @idStato CHAR(1);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRV',
			@Permesso = @permessoSrv OUTPUT;

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permessoSra OUTPUT;

		IF 2 > @permessoSrv AND 2 > @permessoSra
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Servizio di un calendario accessibile e assegnato all'utente della sessione
		SELECT
			@idEvento = e.Id,
			@idStato = e.IdStato
		FROM
			dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			INNER JOIN dbo.tblEventiUtenti u ON e.Id = u.Id
			INNER JOIN dbo.tblSessioni ss ON u.IdUtente = ss.IdUtente AND ss.Id = @IdSessione
		WHERE
			s.Id = @Id
			AND e.Lock = 0;

		IF @idEvento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF @idStato <> 'D'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Si inizia solo un servizio da eseguire: aggiornare la pagina';
			GOTO BRANCH_END;
		END

		UPDATE dbo.tblEventi
		SET IdStato = 'I'
		WHERE
			Id = @idEvento
			AND IdStato = 'D'
			AND Lock = 0;

		IF @@ROWCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Si inizia solo un servizio da eseguire: aggiornare la pagina';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT @returnValue AS ReturnValue;

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
GO

-- ===== 7. servizi_assegnati_bacheca_menu (tools/servizi_assegnati_bacheca_menu.sql)
SET NOCOUNT ON;

-- Servizi > Assegnati: la voce di menu (tblMenu AE2, pagina SRA) apre la vista Bacheca (S7.6, pagina
-- /servizi/assegnati/bacheca) invece dell'Elenco, che resta raggiungibile dal menu della vista. Prima la pagina SRA
-- non aveva Url (indirizzo dal nome della voce: /servizi/assegnati). L'app usa lo stesso valore in
-- SideBar.PaginaAssegnati: va pubblicata insieme. Rieseguibile.
-- Eseguito su dev il 2026-11-23. NON ancora eseguito in produzione.

UPDATE dbo.tblPagine
SET [Url] = 'assegnati/bacheca'
WHERE
	Id = 'SRA'
	AND IdFunzione = 'SRA'
	AND [Url] IS NULL;

SELECT m.Id, m.IdParent, m.Pos, p.Id AS IdPagina, p.Nome, p.[Url], p.IdFunzione
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
WHERE m.Id = 'AE2';
GO
GO

-- ===== Verifica
SELECT o.name, o.type_desc, o.modify_date, m.uses_quoted_identifier
FROM
	sys.objects o
	INNER JOIN sys.sql_modules m ON o.object_id = m.object_id
WHERE o.name IN (N'ufnServizi_get_Sovrapposti_List', N'uspServizi_get_Impegni_List', N'uspServizi_get_Impegni_Eventi_List', N'uspServizi_get_Impegni_Elenco_List', N'uspServiziAssegnati_get_Bacheca_List', N'uspServiziAssegnati_upd_Stato')
ORDER BY o.name;

SELECT 'Menu Servizi > Assegnati -> Bacheca' AS Oggetto,
	IIF(EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'SRA' AND [Url] = 'assegnati/bacheca'), 'ok', 'DA CONTROLLARE') AS Esito;
GO