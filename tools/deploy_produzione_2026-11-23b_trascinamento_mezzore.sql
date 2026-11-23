/*
	Deploy produzione - 2026-11-23 (integrativo) - trascinamento a mezz'ore nei calendari

	Da eseguire DOPO deploy_produzione_2026-11-23_servizi_impegni_calendari.sql nella versione delle 15:58 (repo
	0a8788a, quella eseguita in produzione): aggiunge il solo commit e3f2c3a, che la versione rigenerata alle 19:39
	conteneva gia'. Se in produzione fosse stata eseguita la versione delle 19:39 questo script non cambia nulla.

	Solo 4_0_ecomatico. Due stored procedure CREATE OR ALTER: lo script e' rieseguibile. Nessun dato modificato. Da
	eseguire da SSMS sul database 4_0_ecomatico (o con sqlcmd -f 65001 -I), PRIMA di pubblicare l'app 5f0a8d6: l'app
	manda gia' @IdIntervallo = '30' quando si trascina un servizio o una scadenza nelle viste Giorno e Settimana.

	1. uspServizi_upd_Data: @IdIntervallo '30' = @DataCella e' il nuovo inizio, alle :00 o alle :30.
	2. uspScadenze_upd_Data: lo stesso per le scadenze.

	In fondo la verifica: le due procedure con la data di modifica, QUOTED_IDENTIFIER e il supporto di '30'.
*/

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

-- ===== 1. uspServizi_upd_Data (sql/procedures/uspServizi_upd_Data.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspServizi_upd_Data]
	@IdSessione CHAR(16) = NULL,
	@IdEvento CHAR(16) = NULL,
	@DataOccorrenza SMALLDATETIME = NULL,
	@DataCella SMALLDATETIME = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@IdOsepeDa CHAR(16) = NULL,
	@IdOsepeA CHAR(16) = NULL
AS
-- Sposta un servizio nella cella di un'altra data e ora (trascinamento nel calendario, S4.7.6): cambia solo la data,
-- il resto del servizio resta com'e'. @IdEvento e @DataOccorrenza (la data del servizio o dell'occorrenza) sono quelli
-- del servizio trascinato; @DataCella e' l'inizio della cella di arrivo, @IdIntervallo la sua ampiezza: '1H' l'ora delle
-- viste Giorno e Settimana (nuova ora = ora della cella con i minuti del servizio), '1D' il giorno (vista Mese e fascia
-- In giornata: cambia solo il giorno), '30' la mezz'ora (viste Giorno e Settimana dal 2026-11-23:
-- @DataCella e' il nuovo inizio, su :00 o :30, come nell'anteprima del trascinamento). Il servizio "In giornata" cambia sempre solo il giorno.
-- Impegni per risorsa (S9.10): con @IdOsepeDa (risorsa della colonna di partenza) e @IdOsepeA (risorsa della colonna di
-- arrivo) diverse cambia anche la risorsa, nella stessa transazione: stesso tipo (persona con persona, oggetto con
-- oggetto), Da ancora nel servizio, A impiegabile come in uspServizi_ins_Osepe (S4.5.1); A prende la quantita' di Da,
-- oppure, se e' gia' nel servizio, si toglie solo Da.
-- Per un'occorrenza di una serie ricorrente si cambia la sola occorrenza, che diventa un'occorrenza modificata
-- (eccezione con un evento sostituto, come "Solo questa occorrenza" della scheda, S5.3): la serie non si cambia mai
-- trascinando. Si spostano solo i servizi da eseguire o in esecuzione. Restituisce l'Id del servizio (il nuovo, per
-- un'occorrenza) ed Esito: "Servizio spostato", "Risorsa cambiata" o "Servizio spostato e risorsa cambiata" (NULL se
-- non cambia niente).
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
		DECLARE @cambioRisorsa BIT = 0;
		DECLARE @esito NVARCHAR(50) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEvento = NULLIF(LTRIM(RTRIM(@IdEvento)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @IdOsepeDa = NULLIF(LTRIM(RTRIM(@IdOsepeDa)), '');
		SET @IdOsepeA = NULLIF(LTRIM(RTRIM(@IdOsepeA)), '');
		SET @cambioRisorsa = IIF(@IdOsepeDa IS NOT NULL AND @IdOsepeA IS NOT NULL AND @IdOsepeDa <> @IdOsepeA, 1, 0);

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
		IF @IdIntervallo IS NULL OR @IdIntervallo NOT IN ('1H', '1D', '30')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non è valido';
			GOTO BRANCH_END;
		END
		-- Mezz'ora: la cella parte alle :00 o alle :30
		IF @IdIntervallo = '30' AND DATEPART(MINUTE, @DataCella) NOT IN (0, 30)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataCella non è l''inizio di una mezz''ora';
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
		ELSE IF @IdIntervallo = '30'
			-- Mezz'ora (anteprima del trascinamento): l'inizio e' quello della cella
			SET @data = @DataCella;
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

		-- Cambio di risorsa (Impegni per risorsa): controlli prima di scrivere qualunque cosa
		IF @cambioRisorsa = 1
		BEGIN
			IF NOT EXISTS (
				SELECT 1
				FROM
					dbo.tblOsepe da
					INNER JOIN dbo.tblOsepe a ON a.Tipo = da.Tipo
				WHERE
					da.Id = @IdOsepeDa
					AND a.Id = @IdOsepeA
					AND da.Tipo IN ('P', 'O')
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Si sostituisce una persona con una persona e un oggetto con un oggetto';
				GOTO BRANCH_END;
			END

			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblServiziOsepe
				WHERE
					Id = @idServizio
					AND IdOsepe = @IdOsepeDa
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La persona o l''oggetto non è più nel servizio: aggiornare la pagina';
				GOTO BRANCH_END;
			END

			-- Stesso controllo di uspServizi_ins_Osepe (S4.5.1): impiegabile nei servizi, non disabilitato, dell'azienda
			-- del calendario del servizio o condiviso tramite le Aree; una risorsa gia' nel servizio va sempre bene
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblServiziOsepe
				WHERE
					Id = @idServizio
					AND IdOsepe = @IdOsepeA
			)
			AND NOT EXISTS (
				SELECT 1
				FROM
					dbo.tblCalendari c
					INNER JOIN dbo.tblSedi d ON c.IdSede = d.Id
					CROSS JOIN dbo.tblSessioni n
					CROSS APPLY dbo.ufnOsepe_get_ByUtente_List(n.IdUtente) u
				WHERE
					c.Id = @idCalendario
					AND n.Id = @IdSessione
					AND u.Id = @IdOsepeA
					AND
						(
							(
							u.IdDominio = n.IdDominio
							AND u.Condivisa = 1
							)
						OR u.IdSede = d.IdAziendaInterna
						)
					AND u.Tipo IN ('P', 'O')
					AND u.Disabilitata = 0
					AND u.ImpiegabileServizi = 1
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La persona o l''oggetto indicato non è impiegabile nei servizi';
				GOTO BRANCH_END;
			END
		END

		-- Nessuna modifica: rilasciato nella cella da cui e' partito, nella stessa risorsa
		IF @data = @dataPartenza AND @cambioRisorsa = 0
		BEGIN
			SELECT @idServizio AS Id, @esito AS Esito;
			GOTO BRANCH_END;
		END

		SET @esito = CASE
			WHEN @data <> @dataPartenza AND @cambioRisorsa = 1 THEN 'Servizio spostato e risorsa cambiata'
			WHEN @cambioRisorsa = 1 THEN 'Risorsa cambiata'
			ELSE 'Servizio spostato'
		END;

		IF @ricorre = 0
		BEGIN
			BEGIN TRANSACTION;

				UPDATE dbo.tblEventi
				SET [Data] = @data
				WHERE
					Id = @IdEvento
					AND Lock = 0;

				SET @returnId = @idServizio;

				IF @cambioRisorsa = 1
				BEGIN
					IF EXISTS (SELECT 1 FROM dbo.tblServiziOsepe WHERE Id = @returnId AND IdOsepe = @IdOsepeA)
						DELETE dbo.tblServiziOsepe
						WHERE
							Id = @returnId
							AND IdOsepe = @IdOsepeDa;
					ELSE
						UPDATE dbo.tblServiziOsepe
						SET IdOsepe = @IdOsepeA
						WHERE
							Id = @returnId
							AND IdOsepe = @IdOsepeDa;
				END

			COMMIT TRANSACTION;
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

				-- Risorse della serie; con il cambio di risorsa A prende il posto di Da (o, se c'e' gia', si toglie Da)
				INSERT INTO dbo.tblServiziOsepe (Id, IdOsepe, Quantita)
				SELECT @returnId, IIF(@cambioRisorsa = 1 AND o.IdOsepe = @IdOsepeDa, @IdOsepeA, o.IdOsepe), o.Quantita
				FROM dbo.tblServiziOsepe o
				WHERE
					o.Id = @idServizio
					AND NOT (
						@cambioRisorsa = 1
						AND o.IdOsepe = @IdOsepeDa
						AND EXISTS (SELECT 1 FROM dbo.tblServiziOsepe x WHERE x.Id = @idServizio AND x.IdOsepe = @IdOsepeA)
					);

			COMMIT TRANSACTION;
		END

		EXEC dbo.uspId_upd @Id = @returnId, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT @returnId AS Id, @esito AS Esito;

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

-- ===== 2. uspScadenze_upd_Data (sql/procedures/uspScadenze_upd_Data.sql)
CREATE OR ALTER PROCEDURE [dbo].[uspScadenze_upd_Data]
	@IdSessione CHAR(16) = NULL,
	@IdEvento CHAR(16) = NULL,
	@DataOccorrenza SMALLDATETIME = NULL,
	@DataCella SMALLDATETIME = NULL,
	@IdIntervallo CHAR(2) = NULL
AS
-- Sposta una scadenza su un'altra ora o un altro giorno (trascinamento nel calendario, S4.7.6, gemella di
-- uspServizi_upd_Data): cambia solo la data. @IdEvento e @DataOccorrenza (la data della scadenza o dell'occorrenza)
-- sono quelli della riga trascinata; @DataCella e' l'inizio della cella di arrivo, @IdIntervallo la sua ampiezza:
-- '1H' l'ora delle viste Giorno e Settimana (nuova ora = ora della cella con i minuti della scadenza), '1D' il giorno
-- (vista Mese e fascia In giornata: cambia solo il giorno), '30' la mezz'ora (viste Giorno e Settimana dal 2026-11-23:
-- @DataCella e' il nuovo inizio, su :00 o :30, come nell'anteprima del trascinamento). La scadenza "In giornata" cambia sempre solo il giorno.
-- Per un'occorrenza di una serie ricorrente si sposta la sola occorrenza, che diventa un'occorrenza modificata
-- (come "Solo questa occorrenza" della scheda, S5.3); la serie non si sposta mai trascinando. Si spostano solo le
-- scadenze da eseguire o in esecuzione. Le scadenze non hanno durata. Restituisce l'Id della scadenza spostata
-- (la nuova, per un'occorrenza).
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
		DECLARE @dataEvento SMALLDATETIME;
		DECLARE @dataPartenza SMALLDATETIME;
		DECLARE @data SMALLDATETIME;
		DECLARE @idCalendario CHAR(16);
		DECLARE @idScadenza CHAR(16);

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
		IF @IdIntervallo IS NULL OR @IdIntervallo NOT IN ('1H', '1D', '30')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdIntervallo non è valido';
			GOTO BRANCH_END;
		END
		-- Mezz'ora: la cella parte alle :00 o alle :30
		IF @IdIntervallo = '30' AND DATEPART(MINUTE, @DataCella) NOT IN (0, 30)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataCella non è l''inizio di una mezz''ora';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			@idScadenza = s.Id,
			@idStato = e.IdStato,
			@inGiornata = e.InGiornata,
			@dataEvento = e.[Data],
			@idCalendario = e.IdCalendario,
			@ricorre = IIF(r.Id IS NULL, 0, 1)
		FROM
			dbo.tblEventi e
			INNER JOIN dbo.tblScadenze s ON e.Id = s.IdEvento
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			LEFT JOIN dbo.tblRicorrenze r ON e.Id = r.Id
		WHERE
			e.Id = @IdEvento
			AND e.Lock = 0;

		IF @idScadenza IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Scadenza non trovata o già eliminata';
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
			SET @returnMessage = 'Si spostano solo le scadenze da eseguire o in esecuzione: per le altre modificare la data nella scheda';
			GOTO BRANCH_END;
		END

		-- Nuova data: il giorno della cella di arrivo con l'ora della scadenza (vista Mese e scadenze In giornata),
		-- oppure l'ora della cella con i minuti della scadenza (viste Giorno e Settimana)
		SET @dataPartenza = IIF(@ricorre = 1, @DataOccorrenza, @dataEvento);

		IF @IdIntervallo = '1D' OR @inGiornata = 1
			SET @data = DATEADD(MINUTE, DATEDIFF(MINUTE, CAST(CAST(@dataPartenza AS DATE) AS SMALLDATETIME), @dataPartenza),
				CAST(CAST(@DataCella AS DATE) AS SMALLDATETIME));
		ELSE IF @IdIntervallo = '30'
			-- Mezz'ora (anteprima del trascinamento): l'inizio e' quello della cella
			SET @data = @DataCella;
		ELSE
			SET @data = DATEADD(MINUTE, DATEPART(MINUTE, @dataPartenza),
				DATEADD(HOUR, DATEDIFF(HOUR, CAST(CAST(@DataCella AS DATE) AS SMALLDATETIME), @DataCella), CAST(CAST(@DataCella AS DATE) AS SMALLDATETIME)));

		IF @data < dbo.ufnDate_get_Min() OR @data > dbo.ufnDate_get_Max()
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data deve essere compresa fra il ' + FORMAT(dbo.ufnDate_get_Min(), 'dd/MM/yyyy') + ' e il ' + FORMAT(dbo.ufnDate_get_Max(), 'dd/MM/yyyy');
			GOTO BRANCH_END;
		END

		-- Nessuno spostamento: rilasciato nella cella da cui e' partito
		IF @data = @dataPartenza
		BEGIN
			SELECT @idScadenza AS Id;
			GOTO BRANCH_END;
		END

		IF @ricorre = 0
		BEGIN
			UPDATE dbo.tblEventi
			SET [Data] = @data
			WHERE
				Id = @IdEvento
				AND Lock = 0;

			SET @returnId = @idScadenza;
		END
		ELSE
		BEGIN
			-- Occorrenza di una serie: la data deve essere un'occorrenza vera (non cancellata ne' gia' modificata)
			DECLARE @calendari tvpId_char_16;
			INSERT INTO @calendari (Id) VALUES (@idCalendario);
			DECLARE @tipi tvpId_char_1;
			INSERT INTO @tipi (Id) VALUES ('S');

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

			-- Nuovi Id FUORI dalla transazione (uspId_get ha la propria transazione), come in uspScadenze_ins
			DECLARE @returnIdEvento CHAR(16) = NULL;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @returnIdEvento OUTPUT;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

			BEGIN TRANSACTION;

				-- Copia dell'occorrenza come in uspScadenze_ins (ramo della singola occorrenza), gia' alla nuova data e
				-- senza bozza (Lock = 0): non passa dalla scheda. Proprieta' del tipo comprese
				INSERT INTO dbo.tblEventi
					(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Email, Avviso, Etichette, Lock)
				SELECT
					@returnIdEvento, IdCalendario, 'D', 'S', @data,
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

				INSERT INTO dbo.tblScadenze (Id, IdEvento, IdTipo, Descrizione)
				SELECT TOP 1 @returnId, @returnIdEvento, IdTipo, Descrizione
				FROM dbo.tblScadenze
				WHERE IdEvento = @IdEvento;

				INSERT INTO dbo.tblScadenzeOsepe (Id, IdOsepe)
				SELECT @returnId, o.IdOsepe
				FROM dbo.tblScadenzeOsepe o
				WHERE o.Id = @idScadenza;

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
GO

-- ===== Verifica: Mezzora = 1 se la procedura accetta '30'
SELECT o.name, o.modify_date, m.uses_quoted_identifier,
	Mezzora = IIF(m.[definition] LIKE '%''1H'', ''1D'', ''30''%', 1, 0)
FROM
	sys.objects o
	INNER JOIN sys.sql_modules m ON o.object_id = m.object_id
WHERE o.name IN (N'uspServizi_upd_Data', N'uspScadenze_upd_Data')
ORDER BY o.name;
GO