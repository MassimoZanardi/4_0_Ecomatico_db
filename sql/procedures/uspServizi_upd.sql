SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspServizi_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdRichiedente CHAR(16) = NULL,
	@DataRichiesta SMALLDATETIME = NULL,
	@Descrizione VARCHAR(1000) = NULL,
	@FirmaRichiedente IMAGE = NULL,
	@FirmaEsecutore IMAGE = NULL,
	@IdEvento CHAR(16) = NULL,
	@IdStato CHAR(1) = NULL,
	@Data SMALLDATETIME = NULL,
	@InGiornata BIT = 0,
	@Durata INT = NULL,
	@Ricorre BIT = 0,
	@Avviso BIT = 0,
	@AvvisoAnticipo INT = 0,
	@Email VARCHAR(1000) = NULL,
	@IdEtichette VARCHAR(50) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@Frequenza INT = NULL,
	@DataFine SMALLDATETIME = NULL,
	@Ripetizioni INT = NULL,
	@Relativo INT = 0,
	@OccorrenzaESuccessive BIT = 0,
	@Proprieta NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @permesso TINYINT;
		DECLARE @frequenzaMax INT = 0;
		DECLARE @minuti INT;
		DECLARE @idEventoParent CHAR(16);
		DECLARE @dataFineParent SMALLDATETIME;
		DECLARE @idFirmaRichiedente UNIQUEIDENTIFIER;
		DECLARE @idFirmaEsecutore UNIQUEIDENTIFIER;
		DECLARE @idTipo CHAR(16);

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEvento = NULLIF(LTRIM(RTRIM(@IdEvento)), '');
		SET @IdRichiedente = NULLIF(LTRIM(RTRIM(@IdRichiedente)), '');
		SET @IdStato = NULLIF(LTRIM(RTRIM(@IdStato)), '');
		SET @IdIntervallo = NULLIF(LTRIM(RTRIM(@IdIntervallo)), '');
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);
		SET @Email = dbo.ufnStringhe_get_SenzaSpazi(@Email, 0, 1);

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
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

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblServizi s
			INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE
				s.Id = @Id
				AND e.Id = @IdEvento
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Proprietà del tipo (JSON, ufnEventi_get_ProprietaValori_List): NULL le lascia invariate
		IF @Proprieta IS NOT NULL
		BEGIN
			IF ISJSON(@Proprieta) = 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il parametro @Proprieta non è valido';
				GOTO BRANCH_END;
			END

			SELECT @idTipo = IdTipo
			FROM dbo.tblServizi
			WHERE Id = @Id;

			SELECT TOP 1 @returnMessage = Errore
			FROM dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @idTipo, @Proprieta)
			WHERE Errore IS NOT NULL
			ORDER BY Pos;

			IF @returnMessage IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				GOTO BRANCH_END;
			END
		END

		-- Campi obbligatori del tipo (S3.6): per segnare come eseguito il servizio vanno compilati (le caselle si/no spuntate),
		-- con i valori inviati dalla scheda o quelli gia' salvati
		IF @IdStato = 'E'
		BEGIN
			IF @idTipo IS NULL
				SELECT @idTipo = IdTipo
				FROM dbo.tblServizi
				WHERE Id = @Id;

			SELECT @returnMessage = Messaggio
			FROM dbo.ufnEventi_get_ProprietaObbligatoriaMancante(@IdEvento, @idTipo, @Proprieta);

			IF @returnMessage IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				GOTO BRANCH_END;
			END
		END

		-- Durata in minuti, facoltativa (NULL = non indicata): il servizio termina entro la mezzanotte del giorno di
		-- inizio, cosi' non occupa il giorno successivo (vale anche per le occorrenze della serie, alla stessa ora).
		-- "In giornata" non ha un'ora precisa: la durata arriva a 24 ore, qualunque sia l'ora rimasta nella data
		IF @Durata IS NOT NULL AND @Durata <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La durata del servizio deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		IF @Durata IS NOT NULL
		   AND DATEADD(MINUTE, @Durata, IIF(ISNULL(@InGiornata, 0) = 1, CAST(CAST(@Data AS DATE) AS DATETIME), CAST(@Data AS DATETIME)))
			   > DATEADD(DAY, 1, CAST(CAST(@Data AS DATE) AS DATETIME))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il servizio deve terminare entro la mezzanotte del giorno di inizio: ridurre la durata o anticipare l''ora';
			GOTO BRANCH_END;
		END

		IF @Ricorre = 1 AND EXISTS (SELECT 1
		FROM dbo.tblEventiUtenti
		WHERE Id = @IdEvento)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un servizio assegnato non può essere ricorrente';
			GOTO BRANCH_END;
		END

		-- Limiti della serie: le date ammesse dall'applicazione (ufnDate_get_Min / _Max = Constants.SQL.MinDate / MaxDate)
		IF @Ricorre = 1 AND @Data < dbo.ufnDate_get_Min()
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data minima per i servizi ricorrenti è il ' + FORMAT(dbo.ufnDate_get_Min(), 'dd/MM/yyyy');
			GOTO BRANCH_END;
		END

		IF @Ricorre = 1 AND @DataFine IS NOT NULL AND @DataFine < @Data
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine della serie non può essere inferiore alla data di inizio';
			GOTO BRANCH_END;
		END

		-- La serie è solo pianificazione: si esegue (e si fattura) l'occorrenza modificata, che è un
		-- servizio a sé. Serie = ricorrenza propria (casella Ricorre o "Questa e le successive"), mai
		-- l'occorrenza modificata, che è il sostituto di un'eccezione della serie
		IF @IdStato = 'E'
		   AND (@Ricorre = 1 OR @OccorrenzaESuccessive = 1)
		   AND NOT EXISTS (SELECT 1
		FROM dbo.tblRicorrenzeEccezioni
		WHERE IdEvento = @IdEvento)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un servizio ricorrente non può essere eseguito: per segnare come eseguita un''occorrenza, modificare la sola occorrenza';
			GOTO BRANCH_END;
		END

		IF @IdIntervallo = 'YY'
		BEGIN
			SET @frequenzaMax = DATEDIFF(YEAR, @Data, dbo.ufnDate_get_Max()) - 1;
			IF @Frequenza > @frequenzaMax
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La frequenza massima per l''intervallo indicato è di ' + CAST(@frequenzaMax AS VARCHAR(10)) + ' anni';
				GOTO BRANCH_END;
			END
		END
		ELSE IF @IdIntervallo = 'MM'
		BEGIN
			SET @frequenzaMax = DATEDIFF(MONTH, @Data, dbo.ufnDate_get_Max()) - 1;
			IF @Frequenza > @frequenzaMax
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La frequenza massima per l''intervallo indicato è di ' + CAST(@frequenzaMax AS VARCHAR(10)) + ' mesi';
				GOTO BRANCH_END;
			END
		END

		IF @FirmaRichiedente IS NOT NULL
			SELECT @idFirmaRichiedente = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'R';

		IF @FirmaEsecutore IS NOT NULL
			SELECT @idFirmaEsecutore = IdFirma
			FROM dbo.tblEventiFirme
			WHERE
				Id = @IdEvento
				AND IdTipo = 'E';

		BEGIN TRANSACTION;

			-- Gestione ricorrenze
			IF EXISTS (SELECT 1
			FROM dbo.tblRicorrenze
			WHERE Id = @IdEvento)
			   AND @OccorrenzaESuccessive = 0
			BEGIN
				IF @Ricorre = 0
				BEGIN
					DELETE dbo.tblRicorrenze
					WHERE Id = @IdEvento;
					DELETE dbo.tblRicorrenzeEccezioni
					WHERE Id = @IdEvento;
				END
				ELSE
				BEGIN
					IF EXISTS (
						SELECT 1
						FROM dbo.tblRicorrenze
						WHERE
							Id = @IdEvento
							AND
								(
								IdIntervallo <> @IdIntervallo
								OR Frequenza <> @Frequenza
								OR Relativo <> @Relativo
								)
					)
						DELETE dbo.tblRicorrenzeEccezioni
						WHERE
							Id = @IdEvento
							AND IdEvento IS NULL;

					SELECT @minuti = DATEDIFF(MINUTE, [Data], @Data)
					FROM dbo.tblEventi
					WHERE Id = @IdEvento;

					IF ISNULL(@minuti, 0) <> 0
						UPDATE dbo.tblRicorrenzeEccezioni
						SET [Data] = DATEADD(MINUTE, @minuti, [Data])
						WHERE Id = @IdEvento;

					UPDATE dbo.tblRicorrenze
					SET
						IdIntervallo = @IdIntervallo,
						Frequenza = @Frequenza,
						DataFine = @DataFine,
						Ripetizioni = @Ripetizioni,
						Relativo = @Relativo
					WHERE Id = @IdEvento;
				END
			END
			ELSE IF @Ricorre = 1 AND @OccorrenzaESuccessive = 0
			BEGIN
				INSERT dbo.tblRicorrenze
					(Id, IdIntervallo, Frequenza, DataFine, Ripetizioni, Relativo)
				VALUES
					(@IdEvento, @IdIntervallo, @Frequenza, @DataFine, @Ripetizioni, @Relativo);
			END
			ELSE IF @OccorrenzaESuccessive = 1
			BEGIN
				SELECT @idEventoParent = IdParent
				FROM dbo.tblRicorrenze
				WHERE Id = @IdEvento;

				-- La serie originale finisce il giorno prima dell'occorrenza scelta (la data della nuova serie
				-- prima del salvataggio, scritta da uspServizi_ins), anche se la nuova serie viene spostata
				SELECT @minuti = DATEDIFF(MINUTE, [Data], @Data)
				FROM dbo.tblEventi
				WHERE Id = @IdEvento;

				SET @dataFineParent =
					DATEADD(MINUTE, 59, DATEADD(HOUR, 23,
						DATEADD(DAY, DATEDIFF(DAY, 0, DATEADD(MINUTE, -ISNULL(@minuti, 0), @Data)), -1)));

				UPDATE dbo.tblRicorrenze
				SET
					DataFine = @dataFineParent,
					Ripetizioni = 0
				WHERE Id = @idEventoParent;

				UPDATE dbo.tblRicorrenze
				SET
					IdIntervallo = @IdIntervallo,
					Frequenza = @Frequenza,
					DataFine = @DataFine,
					Ripetizioni = @Ripetizioni,
					Relativo = @Relativo
				WHERE Id = @IdEvento;

				-- Le occorrenze cancellate o modificate della serie originale dalla data scelta in poi passano alla
				-- nuova serie, spostate come la nuova serie (stessa regola della modifica di tutta la serie):
				-- cancellate, una cancellata ricomparirebbe e una modificata sarebbe doppia. Se cambia la frequenza
				-- le date non coincidono piu': passano solo le occorrenze modificate (eventi a se', S5.4)
				INSERT dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
				SELECT @IdEvento, DATEADD(MINUTE, ISNULL(@minuti, 0), z.[Data]), z.IdEvento, z.Lock
				FROM
					dbo.tblRicorrenzeEccezioni z
					INNER JOIN dbo.tblRicorrenze p ON z.Id = p.Id
				WHERE
					z.Id = @idEventoParent
					AND z.[Data] > @dataFineParent
					AND
						(
						z.IdEvento IS NOT NULL
						OR
							(
							p.IdIntervallo = @IdIntervallo
							AND p.Frequenza = @Frequenza
							AND p.Relativo = @Relativo
							)
						)
					AND NOT EXISTS (
						SELECT 1
						FROM dbo.tblRicorrenzeEccezioni y
						WHERE
							y.Id = @IdEvento
							AND y.[Data] = DATEADD(MINUTE, ISNULL(@minuti, 0), z.[Data])
					);

				DELETE dbo.tblRicorrenzeEccezioni
				WHERE
					Id = @idEventoParent
					AND [Data] > @dataFineParent;
			END

			-- Sblocca l'eccezione di ricorrenza che referenzia questo evento come sostituto
			-- (occorrenza singola modificata): senza questo sblocco l'occorrenza originale
			-- resta visibile in calendario insieme a quella modificata. No-op se @IdEvento
			-- non e' il sostituto di nessuna eccezione.
			UPDATE dbo.tblRicorrenzeEccezioni
			SET Lock = 0
			WHERE
				IdEvento = @IdEvento
				AND Lock <= 2;

			-- Gestione firma richiedente
			IF @FirmaRichiedente IS NULL
			BEGIN
				DELETE dbo.tblEventiFirme
				WHERE
					Id = @IdEvento
					AND IdTipo = 'R';
				DELETE dbo.tblFirme
				WHERE Id = @idFirmaRichiedente;
			END
			ELSE IF @idFirmaRichiedente IS NULL
			BEGIN
				SET @idFirmaRichiedente = NEWID();
				INSERT dbo.tblFirme (Id, Firma) VALUES (@idFirmaRichiedente, @FirmaRichiedente);
				INSERT dbo.tblEventiFirme (Id, IdFirma, IdTipo) VALUES (@IdEvento, @idFirmaRichiedente, 'R');
			END
			ELSE
				UPDATE dbo.tblFirme
				SET Firma = @FirmaRichiedente
				WHERE Id = @idFirmaRichiedente;

			-- Gestione firma esecutore
			IF @FirmaEsecutore IS NULL
			BEGIN
				DELETE dbo.tblEventiFirme
				WHERE
					Id = @IdEvento
					AND IdTipo = 'E';
				DELETE dbo.tblFirme
				WHERE Id = @idFirmaEsecutore;
			END
			ELSE IF @idFirmaEsecutore IS NULL
			BEGIN
				SET @idFirmaEsecutore = NEWID();
				INSERT dbo.tblFirme (Id, Firma) VALUES (@idFirmaEsecutore, @FirmaEsecutore);
				INSERT dbo.tblEventiFirme (Id, IdFirma, IdTipo) VALUES (@IdEvento, @idFirmaEsecutore, 'E');
			END
			ELSE
				UPDATE dbo.tblFirme
				SET Firma = @FirmaEsecutore
				WHERE Id = @idFirmaEsecutore;

			UPDATE dbo.tblServizi
			SET
				IdRichiedente = @IdRichiedente,
				DataRichiesta = @DataRichiesta,
				Descrizione = @Descrizione,
				Durata = @Durata
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Servizio non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			DELETE dbo.tblEventiEtichette
			WHERE Id = @IdEvento;

			INSERT dbo.tblEventiEtichette (Id, IdEtichetta)
			SELECT TOP 3 @IdEvento, e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value
			WHERE v.value <> '';

			IF @Proprieta IS NOT NULL
			BEGIN
				DELETE p
				FROM
					dbo.tblEventiProprieta p
					INNER JOIN dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @idTipo, @Proprieta) v ON p.IdProprieta = v.IdProprieta
				WHERE p.Id = @IdEvento;

				INSERT dbo.tblEventiProprieta (Id, IdProprieta, Valore)
				SELECT @IdEvento, IdProprieta, Valore
				FROM dbo.ufnEventi_get_ProprietaValori_List(@IdEvento, @idTipo, @Proprieta)
				WHERE Valore IS NOT NULL;
			END

			UPDATE e
			SET
				IdStato = @IdStato,
				[Data] = @Data,
				InGiornata = @InGiornata,
				AvvisoAnticipo = IIF(@Avviso = 0, NULL, @AvvisoAnticipo),
				Email = IIF(@Avviso = 0, NULL, @Email),
				Avviso = t.Nome + ' - ' + r.NomeCompleto + ' - ' + r.IndirizzoCompleto,
				Etichette = dbo.ufnEventi_get_Etichette(e.Id),
				Lock = 0
			FROM
				dbo.tblEventi e
				INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
				LEFT JOIN dbo.tblTipi t ON s.IdTipo = t.Id
				LEFT JOIN dbo.tblSedi r ON s.IdRichiedente = r.Id
			WHERE
				e.Id = @IdEvento
				AND e.Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Evento non trovato o già eliminato';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

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
