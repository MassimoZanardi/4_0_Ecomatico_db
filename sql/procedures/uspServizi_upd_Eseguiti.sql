SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Segna eseguiti (Servizi > Calendario > Elenco, Azioni > Segna eseguiti, S6.8; decisione dell'utente del 2026-11-24):
-- i servizi da eseguire o in esecuzione trovati dalla ricerca dell'Elenco (stessi filtri di uspServizi_get_List:
-- calendario del contesto, periodo, stato, etichetta, descrizione) con l'inizio gia' passato. Un servizio singolo o
-- un'occorrenza modificata cambia stato; un'occorrenza di una serie diventa un'occorrenza modificata eseguita (copia
-- come in uspServizi_upd_Data), perche' la serie non si esegue (S6.2). Restano fuori, e si elencano, quelli con un
-- campo obbligatorio vuoto (S3.6). Al massimo 500 per volta.
-- @Conferma = 0: anteprima senza scritture, restituisce DaSegnare ed Esclusi; con @Esclusi = 1 invece l'elenco degli
-- esclusi con il motivo (al massimo 100).
-- @Conferma = 1: esegue e restituisce Segnati.
CREATE OR ALTER PROCEDURE [dbo].[uspServizi_upd_Eseguiti]
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Etichetta VARCHAR(50) = NULL,
	@Search VARCHAR(50) = NULL,
	@Conferma BIT = 0,
	@Esclusi BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @Etichetta = dbo.ufnStringhe_get_SenzaSpazi(@Etichetta, 0, 1);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Stato = ISNULL(NULLIF(LTRIM(RTRIM(@Stato)), ''), 'T');

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

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Calendario del contesto, di una sede interna accessibile
		DECLARE @idCalendario CHAR(16) = (SELECT IdCalendario FROM dbo.tblSessioni WHERE Id = @IdSessione);
		IF @idCalendario IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il calendario';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblCalendari c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @idCalendario)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @calendari tvpId_char_16;
		INSERT INTO @calendari (Id) VALUES (@idCalendario);
		DECLARE @tipi tvpId_char_1;
		INSERT INTO @tipi (Id) VALUES ('V');

		-- Stesso periodo di uspServizi_get_List (S4.7.5): dalla data alle 00:00 per l'intervallo, fine esclusa
		SET @DallaData = DATEADD(DAY, DATEDIFF(DAY, 0, @DallaData), 0);
		DECLARE @AllaData SMALLDATETIME = DATEADD(MINUTE, -1, CASE
			WHEN @IdIntervallo = '1W' THEN DATEADD(WEEK, 1, @DallaData)
			WHEN @IdIntervallo = '2W' THEN DATEADD(WEEK, 2, @DallaData)
			WHEN @IdIntervallo = '1M' THEN DATEADD(MONTH, 1, @DallaData)
			WHEN @IdIntervallo = '2M' THEN DATEADD(MONTH, 2, @DallaData)
			WHEN @IdIntervallo = '6M' THEN DATEADD(MONTH, 6, @DallaData)
			WHEN @IdIntervallo = '1Y' THEN DATEADD(YEAR, 1, @DallaData)
			ELSE DATEADD(DAY, 1, @DallaData)
		END);

		DECLARE @adesso SMALLDATETIME = GETDATE();

		-- Servizi della ricerca da eseguire o in esecuzione, gia' iniziati (le occorrenze generate hanno lo stato della serie)
		CREATE TABLE #servizi (
			Riga INT IDENTITY(1, 1) PRIMARY KEY,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdEvento CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdTipo CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			[Data] SMALLDATETIME NOT NULL,
			Ricorre BIT NOT NULL,
			Messaggio NVARCHAR(200) NULL
		);

		INSERT INTO #servizi (Id, IdEvento, IdTipo, [Data], Ricorre)
		SELECT s.Id, s.IdEvento, s.IdTipo, e.[Data], e.Ricorre
		FROM
			dbo.tblServizi s
			INNER JOIN dbo.ufnEventi_get_List(@DallaData, @AllaData, @calendari, @tipi) e ON s.IdEvento = e.Id
		WHERE
			e.IdStato IN ('D', 'I')
			AND e.[Data] <= @adesso
			AND (@Stato IN ('T', 'S') OR e.IdStato = @Stato)
			AND (@Search IS NULL OR s.Descrizione LIKE '%' + @Search + '%')
			AND (@Etichetta IS NULL OR s.IdEvento IN (
				SELECT x.Id
				FROM
					dbo.tblEventiEtichette x
					INNER JOIN dbo.tblEtichette t ON x.IdEtichetta = t.Id
				WHERE t.Nome LIKE '%' + @Etichetta + '%'))
		ORDER BY e.[Data], s.Id;

		-- Campi obbligatori del tipo (S3.6) con i valori salvati (della serie, per un'occorrenza generata)
		UPDATE x
		SET Messaggio = m.Messaggio
		FROM
			#servizi x
			CROSS APPLY dbo.ufnEventi_get_ProprietaObbligatoriaMancante(x.IdEvento, x.IdTipo, NULL) m;

		DECLARE @daSegnare INT = (SELECT COUNT(*) FROM #servizi WHERE Messaggio IS NULL);
		DECLARE @numeroEsclusi INT = (SELECT COUNT(*) FROM #servizi WHERE Messaggio IS NOT NULL);

		IF @daSegnare > 500
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ci sono ' + CAST(@daSegnare AS VARCHAR(10)) + ' servizi da segnare: al massimo 500 per volta, restringere la ricerca';
			GOTO BRANCH_END;
		END

		IF @Conferma = 0
		BEGIN
			IF @Esclusi = 0
			BEGIN
				SELECT DaSegnare = @daSegnare, Esclusi = @numeroEsclusi;
				GOTO BRANCH_END;
			END

			SELECT TOP (100)
				x.[Data],
				Tipo = t.Nome,
				Richiedente = r.NomeCompleto,
				s.Descrizione,
				x.Messaggio
			FROM
				#servizi x
				INNER JOIN dbo.tblServizi s ON x.Id = s.Id
				LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
				LEFT JOIN dbo.tblSedi r ON s.IdRichiedente = r.Id
			WHERE x.Messaggio IS NOT NULL
			ORDER BY x.Riga;

			GOTO BRANCH_END;
		END

		DECLARE @segnati INT = 0;
		DECLARE @riga INT = 0;
		DECLARE @id CHAR(16), @idEvento CHAR(16), @data SMALLDATETIME, @ricorre BIT;
		DECLARE @returnId CHAR(16), @returnIdEvento CHAR(16);

		WHILE 1 = 1
		BEGIN
			SELECT TOP (1) @riga = Riga, @id = Id, @idEvento = IdEvento, @data = [Data], @ricorre = Ricorre
			FROM #servizi
			WHERE
				Riga > @riga
				AND Messaggio IS NULL
			ORDER BY Riga;

			IF @@ROWCOUNT = 0
				BREAK;

			IF @ricorre = 0
			BEGIN
				-- Servizio singolo o occorrenza modificata: cambia lo stato
				UPDATE dbo.tblEventi
				SET IdStato = 'E'
				WHERE
					Id = @idEvento
					AND Lock = 0
					AND IdStato IN ('D', 'I');

				IF @@ROWCOUNT > 0
				BEGIN
					SET @segnati += 1;
					EXEC dbo.uspId_upd @Id = @id, @IdSessione = @IdSessione, @Operazione = 'U';
				END
			END
			ELSE
			BEGIN
				-- Occorrenza di una serie, ancora da modificare: diventa un'occorrenza modificata eseguita (S5.3),
				-- con la copia di uspServizi_upd_Data alla stessa data
				IF NOT EXISTS (
					SELECT 1
					FROM dbo.tblRicorrenzeEccezioni
					WHERE
						Id = @idEvento
						AND [Data] = @data
						AND Lock = 0)
				BEGIN
					-- Nuovi Id FUORI dalla transazione (uspId_get ha la propria transazione)
					SET @returnIdEvento = NULL;
					SET @returnId = NULL;
					EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @returnIdEvento OUTPUT;
					EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

					BEGIN TRANSACTION;

						INSERT INTO dbo.tblEventi
							(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Email, Avviso, Etichette, Lock)
						SELECT
							@returnIdEvento, IdCalendario, 'E', 'V', @data,
							InGiornata, AvvisoAnticipo, Email, Avviso, Etichette, 0
						FROM dbo.tblEventi
						WHERE Id = @idEvento;

						INSERT INTO dbo.tblEventiProprieta (Id, IdProprieta, Valore)
						SELECT @returnIdEvento, IdProprieta, Valore
						FROM dbo.tblEventiProprieta
						WHERE Id = @idEvento;

						INSERT INTO dbo.tblEventiEtichette (Id, IdEtichetta)
						SELECT @returnIdEvento, IdEtichetta
						FROM dbo.tblEventiEtichette
						WHERE Id = @idEvento;

						DELETE dbo.tblRicorrenzeEccezioni
						WHERE
							Id = @idEvento
							AND [Data] = @data;

						INSERT INTO dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
						VALUES (@idEvento, @data, @returnIdEvento, 0);

						INSERT INTO dbo.tblServizi (Id, IdEvento, IdTipo, IdRichiedente, DataRichiesta, Descrizione, Durata)
						SELECT TOP 1 @returnId, @returnIdEvento, IdTipo, IdRichiedente, DataRichiesta, Descrizione, Durata
						FROM dbo.tblServizi
						WHERE IdEvento = @idEvento;

						INSERT INTO dbo.tblServiziOsepe (Id, IdOsepe, Quantita)
						SELECT @returnId, o.IdOsepe, o.Quantita
						FROM dbo.tblServiziOsepe o
						WHERE o.Id = @id;

					COMMIT TRANSACTION;

					SET @segnati += 1;
					EXEC dbo.uspId_upd @Id = @returnId, @IdSessione = @IdSessione, @Operazione = 'U';
				END
			END
		END

		SELECT Segnati = @segnati, Esclusi = @numeroEsclusi;

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
