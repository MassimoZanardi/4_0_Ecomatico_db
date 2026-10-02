SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_esegui
	@IdRegistrazione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazione non può essere vuoto';
			GOTO BRANCH_END;
		END
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati della registrazione (deve essere causale M)
		DECLARE @idSedeRegistrazione CHAR(16);
		DECLARE @idMovimento CHAR(16);
		DECLARE @idMaterialeRegistrazione CHAR(2);
		SELECT
			@idSedeRegistrazione = g.IdSede,
			@idMovimento = m.Id,
			@idMaterialeRegistrazione = r.IdMateriale
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			r.Id = @IdRegistrazione
			AND r.Lock < 2
			AND o.IsMateriale = 1;

		IF @idSedeRegistrazione IS NULL OR @idMaterialeRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata, non di causale materiale prodotto, o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica o annullamento non è un movimento reale: non riceve quote EoW
		IF EXISTS (SELECT 1
		FROM dbo.viewRifiutiRegistrazioniEffettive
		WHERE
			Id = @IdRegistrazione
			AND IsRettifica = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può ricevere quote EoW';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati dell'allocazione
		DECLARE @idSedeAllocazione CHAR(16);
		DECLARE @idAllocazioneTipo CHAR(1);
		SELECT
			@idSedeAllocazione = c.IdSede,
			@idAllocazioneTipo = c.IdAllocazioneTipo
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE
			c.Id = @Id
			AND c.Lock = 0;

		IF @idSedeAllocazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allocazione non trovata o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idSedeAllocazione <> @idSedeRegistrazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''allocazione selezionata non appartiene alla sede della registrazione';
			GOTO BRANCH_END;
		END

		IF @idAllocazioneTipo = 'M'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questo tipo di allocazione non supporta l''esecuzione automatica';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Lock di tutti i lotti coinvolti in un unico statement (ordine di acquisizione stabile,
			-- via index seek sulla PK, per ridurre il rischio di deadlock con esecuzioni concorrenti
			-- su insiemi di lotti sovrapposti), poi del movimento - stesso ordine di
			-- uspEoWLottiRifiutiRegistrazioni_ins.
			DECLARE @lockRow CHAR(16);
			SELECT @lockRow = l.Id
			FROM dbo.tblEoWLotti l WITH (UPDLOCK, HOLDLOCK)
			WHERE l.Id IN (SELECT IdLotto FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id)
			ORDER BY l.Id;

			SELECT @lockRow = Id
			FROM dbo.tblRifiutiMovimenti WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @idMovimento;

			-- Righe di configurazione + quantità già allocata ad ognuno dei lotti coinvolti, lette
			-- sotto lock (fonte unica di verità, nessun ricalcolo su dati stimati prima del lock)
			DECLARE @righe TABLE (IdLotto CHAR(16) PRIMARY KEY, Valore DECIMAL(18, 2) NULL, QuantitaMax DECIMAL(18, 2) NULL, QuantitaAllocata DECIMAL(18, 2) NOT NULL);
			INSERT INTO @righe (IdLotto, Valore, QuantitaMax, QuantitaAllocata)
			SELECT
				la.IdLotto,
				la.Valore,
				l.QuantitaMax,
				QuantitaAllocata = ISNULL((SELECT SUM(r.Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni r INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
				WHERE
					r.IdLotto = la.IdLotto
					AND rr.Lock < 2
				), 0)
			FROM
				dbo.tblEoWLottiAllocazioni la
				INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
			WHERE la.IdAllocazione = @Id;

			IF NOT EXISTS (SELECT 1
			FROM @righe)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'L''allocazione non ha lotti configurati';
				GOTO BRANCH_END;
			END

			-- Lotti non utilizzabili: chiusi (data di chiusura impostata), disabilitati o eliminati,
			-- come per l'attribuzione manuale (uspEoWLottiRifiutiRegistrazioni_ins). Con il tipo C
			-- (priorità/capacità) vengono saltati come i lotti pieni e si passa al successivo; con
			-- U e P (lotto unico / percentuale) non c'è un lotto successivo: errore bloccante.
			DECLARE @lottoNonUtilizzabile VARCHAR(50) = (
				SELECT TOP 1 l.Nome
				FROM
					@righe r
					INNER JOIN dbo.tblEoWLotti l ON r.IdLotto = l.Id
				WHERE
					l.Lock <> 0
					OR l.DataChiusura IS NOT NULL
					OR ISNULL(l.Disabilitato, 0) = 1
				ORDER BY l.Nome
			);
			IF @lottoNonUtilizzabile IS NOT NULL AND @idAllocazioneTipo IN ('U', 'P')
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Il lotto ' + @lottoNonUtilizzabile + ' dell''allocazione è chiuso o disabilitato';
				GOTO BRANCH_END;
			END
			IF @lottoNonUtilizzabile IS NOT NULL
			BEGIN
				DELETE r
				FROM
					@righe r
					INNER JOIN dbo.tblEoWLotti l ON r.IdLotto = l.Id
				WHERE
					l.Lock <> 0
					OR l.DataChiusura IS NOT NULL
					OR ISNULL(l.Disabilitato, 0) = 1;

				IF NOT EXISTS (SELECT 1
				FROM @righe)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Tutti i lotti dell''allocazione sono chiusi o disabilitati';
					GOTO BRANCH_END;
				END
			END

			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			DECLARE @quantitaMovimento DECIMAL(18, 2) = (SELECT Quantita
			FROM dbo.viewRifiutiRegistrazioniEffettive
			WHERE Id = @IdRegistrazione);
			DECLARE @quantitaAllocataRegistrazione DECIMAL(18, 2) = ISNULL((
				SELECT SUM(Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdRegistrazione = @IdRegistrazione), 0);
			DECLARE @quantitaDaAllocare DECIMAL(18, 2) = ISNULL(@quantitaMovimento, 0) - @quantitaAllocataRegistrazione;

			IF @quantitaDaAllocare <= 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Non c''è quantità residua da allocare per questa registrazione';
				GOTO BRANCH_END;
			END

			-- Piano di ripartizione calcolato per tipo (U = Lotto unico, P = Percentuale, C = Priorità/Capacità)
			DECLARE @piano TABLE (IdLotto CHAR(16) PRIMARY KEY, Quantita DECIMAL(18, 2) NOT NULL);

			IF @idAllocazioneTipo = 'U'
			BEGIN
				IF (SELECT COUNT(*)
				FROM @righe) <> 1
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Un''allocazione di tipo Lotto unico deve avere esattamente un lotto configurato';
					GOTO BRANCH_END;
				END

				INSERT INTO @piano (IdLotto, Quantita)
				SELECT IdLotto, @quantitaDaAllocare
				FROM @righe;
			END
			ELSE IF @idAllocazioneTipo = 'P'
			BEGIN
				DECLARE @sommaPercentuali DECIMAL(18, 2) = (SELECT SUM(ISNULL(Valore, 0))
				FROM @righe);
				IF @sommaPercentuali > 100
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Le percentuali configurate non possono superare 100';
					GOTO BRANCH_END;
				END

				-- Arrotondamento a 2 decimali per riga. Il resto viene pareggiato sull'ultimo lotto (per
				-- Id) solo se le percentuali configurate coprono l'intero 100%: in quel caso il resto è
				-- puro errore di arrotondamento da correggere. Se invece sommano a meno di 100 (allocazione
				-- volutamente parziale, es. un solo lotto al 60%), il resto è quantità non allocata per
				-- scelta e deve restare tale, non va scaricato sull'ultimo lotto.
				INSERT INTO @piano (IdLotto, Quantita)
				SELECT
					IdLotto,
					Quantita = ROUND(@quantitaDaAllocare * Valore / 100.0, 2)
				FROM @righe;

				IF @sommaPercentuali = 100
				BEGIN
					DECLARE @idUltimoLotto CHAR(16) = (SELECT TOP 1 IdLotto
					FROM @righe ORDER BY IdLotto DESC);
					DECLARE @resto DECIMAL(18, 2) = @quantitaDaAllocare - (SELECT SUM(Quantita)
					FROM @piano);
					UPDATE @piano
					SET Quantita = Quantita + @resto
					WHERE IdLotto = @idUltimoLotto;
				END
			END
			ELSE IF @idAllocazioneTipo = 'C'
			BEGIN
				-- Ripartizione greedy per priorità (Valore crescente = priorità più alta): iterazione
				-- riga per riga, nessun pattern set-based equivalente per un bin-packing sequenziale.
				DECLARE @rimanente DECIMAL(18, 2) = @quantitaDaAllocare;
				DECLARE @curIdLotto CHAR(16), @curQuantitaMax DECIMAL(18, 2), @curQuantitaAllocata DECIMAL(18, 2);

				DECLARE curRighe CURSOR LOCAL FAST_FORWARD FOR
					SELECT IdLotto, QuantitaMax, QuantitaAllocata
					FROM @righe
					ORDER BY ISNULL(Valore, 999999999), IdLotto;

				OPEN curRighe;
				FETCH NEXT
				FROM curRighe INTO @curIdLotto, @curQuantitaMax, @curQuantitaAllocata;
				WHILE @@FETCH_STATUS = 0 AND @rimanente > 0
				BEGIN
					DECLARE @capacitaResidua DECIMAL(18, 2) = CASE
						WHEN @curQuantitaMax IS NULL THEN @rimanente
						ELSE @curQuantitaMax - @curQuantitaAllocata
					END;
					IF @capacitaResidua > 0
					BEGIN
						DECLARE @presoQui DECIMAL(18, 2) = IIF(@capacitaResidua < @rimanente, @capacitaResidua, @rimanente);
						INSERT INTO @piano (IdLotto, Quantita) VALUES (@curIdLotto, @presoQui);
						SET @rimanente -= @presoQui;
					END
					FETCH NEXT
					FROM curRighe INTO @curIdLotto, @curQuantitaMax, @curQuantitaAllocata;
				END
				CLOSE curRighe;
				DEALLOCATE curRighe;

				IF @rimanente > 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'La capacità configurata nei lotti è insufficiente per la quantità da allocare';
					GOTO BRANCH_END;
				END
			END

			-- Verifica finale capacità per riga (ridondante per U/P dove già implicito, ma protegge
			-- comunque da una configurazione QuantitaMax incoerente) e upsert nella tabella risultato
			IF EXISTS (
				SELECT 1
				FROM @piano p INNER JOIN @righe r ON p.IdLotto = r.IdLotto
				WHERE
					r.QuantitaMax IS NOT NULL
					AND r.QuantitaAllocata + p.Quantita > r.QuantitaMax
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità calcolata supera la capacità residua di uno o più lotti';
				GOTO BRANCH_END;
			END

			-- Pos = ordine di riempimento e IdAllocazioneTipo = metodo: quando la quantita' operativa della M scende,
			-- uspEoWLottiRifiutiRegistrazioni_upd_Allinea riduce partendo dall'ultima allocazione fatta rispettando
			-- il metodo (P in proporzione, C/U dall'ultimo lotto riempito). I lotti di questa esecuzione seguono
			-- quelli gia' allocati, nell'ordine di configurazione (Valore crescente = per il tipo C la priorita'
			-- con cui sono stati riempiti). Un lotto gia' allocato prende metodo e Pos di questa esecuzione
			-- (l'ultima operazione).
			DECLARE @posMax INT = ISNULL((SELECT MAX(Pos)
			FROM dbo.tblEoWLottiRifiutiRegistrazioni
			WHERE IdRegistrazione = @IdRegistrazione), 0);

			MERGE dbo.tblEoWLottiRifiutiRegistrazioni AS target
			USING (
				SELECT
					p.IdLotto,
					p.Quantita,
					Pos = @posMax + ROW_NUMBER() OVER (ORDER BY ISNULL(r.Valore, 999999999), p.IdLotto)
				FROM
					@piano p
					INNER JOIN @righe r ON p.IdLotto = r.IdLotto
			) AS source
				ON target.IdRegistrazione = @IdRegistrazione AND target.IdLotto = source.IdLotto
			WHEN MATCHED THEN
				UPDATE SET
					Quantita = target.Quantita + source.Quantita,
					Pos = source.Pos,
					IdAllocazioneTipo = @idAllocazioneTipo
			WHEN NOT MATCHED THEN
				INSERT (IdRegistrazione, IdLotto, Quantita, Pos, IdAllocazioneTipo)
				VALUES (@IdRegistrazione, source.IdLotto, source.Quantita, source.Pos, @idAllocazioneTipo);

		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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
