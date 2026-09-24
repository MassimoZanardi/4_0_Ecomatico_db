SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimenti_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Data DATE = NULL,
	@Numero INT = NULL,
	@DdtIdCausale CHAR(1) = NULL,
	@DdtNumeroFornitore VARCHAR(20) = NULL,
	@DdtSezionale CHAR(1) = NULL,
	@DdtData DATE = NULL,
	@DdtIdMittente CHAR(16) = NULL,
	@DdtIdDestinatario CHAR(16) = NULL,
	@DdtIdTrasportatore CHAR(16) = NULL,
	@DdtDataInizioTrasporto SMALLDATETIME = NULL,
	@DdtPeso DECIMAL(18, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @confermato BIT = 0;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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
		IF @Data IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data del movimento';
			GOTO BRANCH_END;
		END
		IF @Numero IS NOT NULL AND @Numero <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = c.IdSede
		FROM
			dbo.tblMagazziniMovimenti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Salva sempre Data/Numero (anche se il movimento resta in bozza): il numero
			-- digitato dall'utente non viene ancora validato qui, solo persistito - la
			-- validazione/rinumerazione definitiva avviene più sotto, solo se si confermano
			-- anche le righe nello stesso salvataggio (vedi @pronto). IdOperazione è fissato
			-- alla creazione (uspMagazziniMovimenti_ins) e non è più modificabile.
			UPDATE dbo.tblMagazziniMovimenti
			SET
				Data = @Data,
				Numero = @Numero
			WHERE
				Id = @Id
				AND Lock = 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Movimento non trovato, già confermato o già eliminato';
				GOTO BRANCH_END;
			END

			-- DDT: se presente e ancora in bozza, valida e persiste sempre i campi (salvataggio
			-- di bozza, come la testata del Movimento); lo conferma (Lock 2->0, Numero
			-- assegnato) solo se i campi obbligatori (Causale, Data, Destinatario) sono tutti
			-- presenti in questo salvataggio - "Salva" fa da Salva e Conferma anche per il DDT,
			-- nello stesso click e nella stessa SP (non più un "Salva DDT" separato). Se il DDT
			-- è già confermato (Lock = 0) resta immutabile, coerente con la testata Movimento.
			DECLARE @idDdt CHAR(16), @idSedeDdt CHAR(16), @lockDdt INT;
			SELECT @idDdt = Id, @idSedeDdt = IdSede, @lockDdt = Lock
			FROM dbo.tblMagazziniDdt
			WHERE IdMovimento = @Id;

			IF @idDdt IS NOT NULL AND @lockDdt = 2
			BEGIN
				SET @DdtIdCausale = NULLIF(LTRIM(RTRIM(@DdtIdCausale)), '');
				SET @DdtNumeroFornitore = dbo.ufnStringhe_get_SenzaSpazi(@DdtNumeroFornitore, 0, 1);
				SET @DdtSezionale = NULLIF(LTRIM(RTRIM(@DdtSezionale)), '');
				SET @DdtIdMittente = NULLIF(LTRIM(RTRIM(@DdtIdMittente)), '');
				SET @DdtIdDestinatario = NULLIF(LTRIM(RTRIM(@DdtIdDestinatario)), '');
				SET @DdtIdTrasportatore = NULLIF(LTRIM(RTRIM(@DdtIdTrasportatore)), '');

				IF @DdtIdCausale IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniCausali WHERE Id = @DdtIdCausale)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Causale del DDT non valida';
					GOTO BRANCH_END;
				END
				IF @DdtPeso IS NOT NULL AND @DdtPeso <= 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il peso del DDT deve essere maggiore di zero';
					GOTO BRANCH_END;
				END
				-- IdMittente è un campo libero della testata (valore stampato sul documento,
				-- l'utente lo compila a piacimento): nessuna relazione con la sede interna
				IF @DdtIdMittente IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @DdtIdMittente)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il mittente del DDT indicato non esiste';
					GOTO BRANCH_END;
				END
				IF @DdtIdDestinatario IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @DdtIdDestinatario)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il destinatario del DDT indicato non esiste';
					GOTO BRANCH_END;
				END
				IF @DdtIdTrasportatore IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @DdtIdTrasportatore)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il trasportatore del DDT indicato non esiste';
					GOTO BRANCH_END;
				END

				DECLARE @ddtPronto BIT = IIF(@DdtIdCausale IS NOT NULL AND @DdtData IS NOT NULL AND @DdtIdDestinatario IS NOT NULL, 1, 0);

				IF @ddtPronto = 1
				BEGIN
					-- Numerazione indipendente per sede interna + sezionale, calcolata dentro
					-- la transazione con lock di riga per evitare duplicati in caso di
					-- richieste concorrenti sulla stessa sede/sezionale
					DECLARE @numeroDdt INT;
					SELECT @numeroDdt = ISNULL(MAX(Numero), 0) + 1
					FROM dbo.tblMagazziniDdt WITH (UPDLOCK, HOLDLOCK)
					WHERE
						IdSede = @idSedeDdt
						AND (Sezionale = @DdtSezionale OR (Sezionale IS NULL AND @DdtSezionale IS NULL))
						AND Id <> @idDdt;

					UPDATE dbo.tblMagazziniDdt
					SET
						Lock = 0,
						IdCausale = @DdtIdCausale,
						Numero = @numeroDdt,
						NumeroFornitore = @DdtNumeroFornitore,
						Sezionale = @DdtSezionale,
						Data = @DdtData,
						IdMittente = @DdtIdMittente,
						IdDestinatario = @DdtIdDestinatario,
						IdTrasportatore = @DdtIdTrasportatore,
						DataInizioTrasporto = @DdtDataInizioTrasporto,
						Peso = @DdtPeso
					WHERE Id = @idDdt;
				END
				ELSE
				BEGIN
					UPDATE dbo.tblMagazziniDdt
					SET
						IdCausale = @DdtIdCausale,
						NumeroFornitore = @DdtNumeroFornitore,
						Sezionale = @DdtSezionale,
						Data = @DdtData,
						IdMittente = @DdtIdMittente,
						IdDestinatario = @DdtIdDestinatario,
						IdTrasportatore = @DdtIdTrasportatore,
						DataInizioTrasporto = @DdtDataInizioTrasporto,
						Peso = @DdtPeso
					WHERE Id = @idDdt;
				END
			END

			-- Il movimento è pronto per la conferma se esiste almeno una riga (tradizionale o
			-- EoW), tutte le righe sono completamente allocate sui lotti, e non c'è un DDT
			-- ancora in bozza. "Salva" fa da "Salva" e da "Conferma" nello stesso click: se
			-- non è pronto, resta semplicemente in bozza, senza errore.
			DECLARE @pronto BIT = 1;

			IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE IdMovimento = @Id)
				AND NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheEoW WHERE IdMovimento = @Id)
				SET @pronto = 0;

			IF @pronto = 1 AND EXISTS (
				SELECT 1
				FROM
					dbo.tblMagazziniMovimentiRighe r
					OUTER APPLY (SELECT Allocata = SUM(rl.Quantita) FROM dbo.tblMagazziniMovimentiRigheLotti rl WHERE rl.Id = r.Id) q
				WHERE
					r.IdMovimento = @Id
					AND ISNULL(q.Allocata, 0) <> r.Quantita
			)
				SET @pronto = 0;

			IF @pronto = 1 AND EXISTS (
				SELECT 1
				FROM
					dbo.tblMagazziniMovimentiRigheEoW r
					OUTER APPLY (SELECT Allocata = SUM(rl.Quantita) FROM dbo.tblMagazziniMovimentiRigheEoWLotti rl WHERE rl.Id = r.Id) q
				WHERE
					r.IdMovimento = @Id
					AND ISNULL(q.Allocata, 0) <> r.Quantita
			)
				SET @pronto = 0;

			IF @pronto = 1 AND EXISTS (SELECT 1 FROM dbo.tblMagazziniDdt WHERE IdMovimento = @Id AND Lock = 2)
				SET @pronto = 0;

			IF @pronto = 1
			BEGIN
				-- Numerazione: progressivo annuale per Azienda + anno di Data, tra i soli
				-- movimenti già confermati (Lock = 0). UPDLOCK/HOLDLOCK per serializzare
				-- conferme concorrenti nello stesso anno/azienda.
				DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@Data), 1, 1);
				DECLARE @annoFine DATE = DATEADD(YEAR, 1, @annoInizio);

				IF @Numero IS NULL
				BEGIN
					SELECT @Numero = ISNULL(MAX(Numero), 0) + 1
					FROM dbo.tblMagazziniMovimenti WITH (UPDLOCK, HOLDLOCK)
					WHERE
						IdSede = @idAzienda
						AND Lock = 0
						AND Data >= @annoInizio
						AND Data < @annoFine;
				END
				ELSE
				BEGIN
					-- Collisione esatta con un altro movimento già confermato: rinumera (+1)
					-- tutti i movimenti con Numero >= quello scelto, nello stesso anno/azienda,
					-- per fare spazio - permette di riusare un "buco" lasciato da una
					-- cancellazione senza doverli spostare manualmente uno per uno.
					IF EXISTS (
						SELECT 1
						FROM dbo.tblMagazziniMovimenti WITH (UPDLOCK, HOLDLOCK)
						WHERE
							Id <> @Id
							AND IdSede = @idAzienda
							AND Lock = 0
							AND Data >= @annoInizio
							AND Data < @annoFine
							AND Numero = @Numero
					)
					BEGIN
						UPDATE dbo.tblMagazziniMovimenti
						SET Numero = Numero + 1
						WHERE
							Id <> @Id
							AND IdSede = @idAzienda
							AND Lock = 0
							AND Data >= @annoInizio
							AND Data < @annoFine
							AND Numero >= @Numero;
					END

					-- Coerenza cronologica: un movimento con Data precedente non può avere un
					-- numero maggiore o uguale, uno con Data successiva non può averne uno
					-- minore o uguale, nello stesso anno/azienda. Qui si blocca con un errore
					-- invece di tentare un riordino automatico più ampio, per non correggere
					-- inavvertitamente dati che potrebbero già essere corretti per altri motivi.
					IF EXISTS (
						SELECT 1
						FROM dbo.tblMagazziniMovimenti
						WHERE
							Id <> @Id
							AND IdSede = @idAzienda
							AND Lock = 0
							AND Data >= @annoInizio
							AND Data < @annoFine
							AND (
								(Data < @Data AND Numero >= @Numero)
								OR (Data > @Data AND Numero <= @Numero)
							)
					)
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Il numero indicato non è coerente con la data rispetto ad altri movimenti dello stesso anno';
						GOTO BRANCH_END;
					END
				END

				UPDATE dbo.tblMagazziniMovimenti
				SET
					Lock = 0,
					Numero = @Numero
				WHERE
					Id = @Id
					AND Lock = 2;

				UPDATE dbo.tblMagazziniMovimentiRighe
				SET Lock = 0
				WHERE IdMovimento = @Id;

				UPDATE dbo.tblMagazziniMovimentiRigheEoW
				SET Lock = 0
				WHERE IdMovimento = @Id;

				SET @confermato = 1;
			END

		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';
		IF @idDdt IS NOT NULL
			EXEC dbo.uspId_upd @Id = @idDdt, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue, Confermato = @confermato, Numero = @Numero;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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
