SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServizi_get_Impegni_List]
	@IdSessione CHAR(16) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@IdVista CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	SET DATEFIRST 1;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
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
		GROUP BY u.Id, u.Tipo;

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
			d.Testo
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
