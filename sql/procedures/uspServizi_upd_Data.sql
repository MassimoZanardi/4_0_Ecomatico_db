CREATE OR ALTER PROCEDURE [dbo].[uspServizi_upd_Data]
	@IdSessione CHAR(16) = NULL,
	@IdEvento CHAR(16) = NULL,
	@DataOccorrenza SMALLDATETIME = NULL,
	@DataCella SMALLDATETIME = NULL,
	@IdIntervallo CHAR(2) = NULL
AS
-- Sposta un servizio nella cella di un'altra data e ora (trascinamento nel calendario, S4.7.6): cambia solo la data,
-- il resto del servizio resta com'e'. @IdEvento e @DataOccorrenza (la data del servizio o dell'occorrenza) sono quelli
-- della cella di partenza, letti con uspServizi_get_ByData_List; @DataCella e' l'inizio della cella di arrivo, @IdIntervallo
-- la sua ampiezza: '1H' l'ora delle viste Giorno e Settimana (nuova ora = ora della cella con i minuti del servizio),
-- '1D' il giorno della vista Mese (cambia solo il giorno). Il servizio "In giornata" cambia sempre solo il giorno.
-- Per un'occorrenza di una serie ricorrente si sposta la sola occorrenza, che diventa un'occorrenza modificata
-- (eccezione con un evento sostituto, come "Solo questa occorrenza" della scheda, S5.3): la serie non si sposta mai
-- trascinando. Si spostano solo i servizi da eseguire o in esecuzione. Restituisce l'Id del servizio spostato
-- (il nuovo, per un'occorrenza).
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permesso TINYINT;
		DECLARE @ricorre BIT = 0;
		DECLARE @idStato CHAR(1);
		DECLARE @inGiornata BIT;
		DECLARE @durata INT;
		DECLARE @dataEvento SMALLDATETIME;
		DECLARE @dataPartenza SMALLDATETIME;
		DECLARE @data SMALLDATETIME;
		DECLARE @idCalendario CHAR(16);
		DECLARE @idServizio CHAR(16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEvento = NULLIF(LTRIM(RTRIM(@IdEvento)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdEvento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdEvento non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataCella IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataCella non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdIntervallo IS NULL OR @IdIntervallo NOT IN ('1H', '1D')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non è valido';
			GOTO BRANCH_END;
		END

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

		SELECT
			@idServizio = s.Id,
			@idStato = e.IdStato,
			@inGiornata = e.InGiornata,
			@durata = s.Durata,
			@dataEvento = e.[Data],
			@idCalendario = e.IdCalendario,
			@ricorre = IIF(r.Id IS NULL, 0, 1)
		FROM
			dbo.tblEventi e
			INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			LEFT JOIN dbo.tblRicorrenze r ON e.Id = r.Id
		WHERE
			e.Id = @IdEvento
			AND e.Lock = 0;

		IF @idServizio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Servizio non trovato o già eliminato';
			GOTO BRANCH_END;
		END

		IF @ricorre = 1 AND @DataOccorrenza IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataOccorrenza non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @idStato NOT IN ('D', 'I')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Si spostano solo i servizi da eseguire o in esecuzione: per gli altri modificare la data nella scheda';
			GOTO BRANCH_END;
		END

		-- Nuova data: il giorno della cella di arrivo con l'ora del servizio (vista Mese e servizi In giornata),
		-- oppure l'ora della cella con i minuti del servizio (viste Giorno e Settimana)
		SET @dataPartenza = IIF(@ricorre = 1, @DataOccorrenza, @dataEvento);

		IF @IdIntervallo = '1D' OR @inGiornata = 1
			SET @data = DATEADD(MINUTE, DATEDIFF(MINUTE, CAST(CAST(@dataPartenza AS DATE) AS SMALLDATETIME), @dataPartenza),
				CAST(CAST(@DataCella AS DATE) AS SMALLDATETIME));
		ELSE
			SET @data = DATEADD(MINUTE, DATEPART(MINUTE, @dataPartenza),
				DATEADD(HOUR, DATEDIFF(HOUR, CAST(CAST(@DataCella AS DATE) AS SMALLDATETIME), @DataCella), CAST(CAST(@DataCella AS DATE) AS SMALLDATETIME)));

		IF @data < dbo.ufnDate_get_Min() OR @data > dbo.ufnDate_get_Max()
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data deve essere compresa fra il ' + FORMAT(dbo.ufnDate_get_Min(), 'dd/MM/yyyy') + ' e il ' + FORMAT(dbo.ufnDate_get_Max(), 'dd/MM/yyyy');
			GOTO BRANCH_END;
		END

		-- Stessa regola di uspServizi_upd (S6.7): il servizio termina entro la mezzanotte del giorno di inizio
		IF @durata IS NOT NULL
		   AND DATEADD(MINUTE, @durata, IIF(ISNULL(@inGiornata, 0) = 1, CAST(CAST(@data AS DATE) AS DATETIME), CAST(@data AS DATETIME)))
			   > DATEADD(DAY, 1, CAST(CAST(@data AS DATE) AS DATETIME))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il servizio deve terminare entro la mezzanotte del giorno di inizio: con la sua durata non può iniziare a quest''ora';
			GOTO BRANCH_END;
		END

		-- Nessuno spostamento: rilasciato nella cella da cui e' partito
		IF @data = @dataPartenza
		BEGIN
			SELECT @idServizio AS Id;
			GOTO BRANCH_END;
		END

		IF @ricorre = 0
		BEGIN
			UPDATE dbo.tblEventi
			SET [Data] = @data
			WHERE
				Id = @IdEvento
				AND Lock = 0;

			SET @returnId = @idServizio;
		END
		ELSE
		BEGIN
			-- Occorrenza di una serie: la data deve essere un'occorrenza vera (non cancellata ne' gia' modificata)
			DECLARE @calendari tvpId_char_16;
			INSERT INTO @calendari (Id) VALUES (@idCalendario);
			DECLARE @tipi tvpId_char_1;
			INSERT INTO @tipi (Id) VALUES ('V');

			IF NOT EXISTS (
				SELECT 1
				FROM dbo.ufnEventi_get_List(@DataOccorrenza, @DataOccorrenza, @calendari, @tipi) e
				WHERE
					e.Id = @IdEvento
					AND e.[Data] = @DataOccorrenza
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Occorrenza non trovata: aggiornare il calendario';
				GOTO BRANCH_END;
			END

			-- Nuovi Id FUORI dalla transazione (uspId_get ha la propria transazione), come in uspServizi_ins
			DECLARE @returnIdEvento CHAR(16) = NULL;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @returnIdEvento OUTPUT;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

			BEGIN TRANSACTION;

				-- Copia dell'occorrenza come in uspServizi_ins (ramo della singola occorrenza), gia' alla nuova data e
				-- senza bozza (Lock = 0): non passa dalla scheda
				INSERT INTO dbo.tblEventi
					(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Email, Avviso, Etichette, Lock)
				SELECT
					@returnIdEvento, IdCalendario, 'D', 'V', @data,
					InGiornata, AvvisoAnticipo, Email, Avviso, Etichette, 0
				FROM dbo.tblEventi
				WHERE Id = @IdEvento;

				INSERT INTO dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @returnIdEvento, IdProprieta, Valore
				FROM dbo.tblEventiProprieta
				WHERE Id = @IdEvento;

				INSERT INTO dbo.tblEventiEtichette (Id, IdEtichetta)
				SELECT @returnIdEvento, IdEtichetta
				FROM dbo.tblEventiEtichette
				WHERE Id = @IdEvento;

				DELETE dbo.tblRicorrenzeEccezioni
				WHERE
					Id = @IdEvento
					AND [Data] = @DataOccorrenza;

				INSERT INTO dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
				VALUES (@IdEvento, @DataOccorrenza, @returnIdEvento, 0);

				INSERT INTO dbo.tblServizi (Id, IdEvento, IdTipo, IdRichiedente, DataRichiesta, Descrizione, Durata)
				SELECT TOP 1 @returnId, @returnIdEvento, IdTipo, IdRichiedente, DataRichiesta, Descrizione, Durata
				FROM dbo.tblServizi
				WHERE IdEvento = @IdEvento;

				INSERT INTO dbo.tblServiziOsepe (Id, IdOsepe, Quantita)
				SELECT @returnId, o.IdOsepe, o.Quantita
				FROM dbo.tblServiziOsepe o
				WHERE o.Id = @idServizio;

			COMMIT TRANSACTION;
		END

		EXEC dbo.uspId_upd @Id = @returnId, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT @returnId AS Id;

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
