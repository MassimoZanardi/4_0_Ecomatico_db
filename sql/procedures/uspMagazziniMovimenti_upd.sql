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
	@DdtPeso DECIMAL(18, 2) = NULL,
	@DdtNumero INT = NULL
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

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione.
		-- Come le Registrazioni Rifiuti (uspRifiutiRegistrazioni_upd): "Salva" conferma sempre
		-- il movimento (Lock 2->0) oppure si blocca con un errore, e un movimento già
		-- confermato (Lock = 0) si può risalvare modificando anche data e numero (l'operazione
		-- resta quella fissata alla creazione), con i controlli cronologici sulle relazioni.
		DECLARE @idAzienda CHAR(16), @idOperazione CHAR(1), @lockMovimento INT, @dataPrecedente DATE, @numeroPrecedente INT;
		SELECT
			@idAzienda = c.IdSede,
			@idOperazione = c.IdOperazione,
			@lockMovimento = c.Lock,
			@dataPrecedente = c.[Data],
			@numeroPrecedente = c.Numero
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
		IF @lockMovimento NOT IN (0, 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Movimento non trovato o già eliminato';
			GOTO BRANCH_END;
		END
		IF @Data IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data del movimento';
			GOTO BRANCH_END;
		END
		-- Le righe descrittive del DDT (senza articolo) non bastano: serve almeno una riga di merce
		IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE IdMovimento = @Id AND IdArticolo IS NOT NULL)
			AND NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheEoW WHERE IdMovimento = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Aggiungere almeno una riga';
			GOTO BRANCH_END;
		END

		-- Movimento già confermato con data o numero modificati: le relazioni carico/scarico
		-- vanno ricontrollate/ricostruite rispetto alla nuova posizione cronologica
		DECLARE @dataNumeroModificati BIT = IIF(
			@lockMovimento = 0
			AND (@Data <> @dataPrecedente OR ISNULL(@Numero, -1) <> ISNULL(@numeroPrecedente, -1)), 1, 0);

		BEGIN TRANSACTION;

			-- Data/Numero: il numero digitato dall'utente viene validato/rinumerato più sotto,
			-- dopo le relazioni. IdOperazione è fissato alla creazione
			-- (uspMagazziniMovimenti_ins) e non è più modificabile.
			UPDATE dbo.tblMagazziniMovimenti
			SET
				Data = @Data,
				Numero = @Numero
			WHERE
				Id = @Id
				AND Lock IN (0, 2);

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Movimento non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			-- DDT: se presente e ancora in bozza, viene confermato insieme al movimento (Lock
			-- 2->0, Numero assegnato) nello stesso click e nella stessa SP; se i campi
			-- obbligatori (Causale, Data, Destinatario) non sono completi il salvataggio si
			-- blocca con un errore (come le Registrazioni Rifiuti). Un DDT già confermato
			-- (Lock = 0) resta modificabile con gli stessi controlli, e in più se ne può
			-- cambiare il numero (@DdtNumero); la sede interna resta immutabile.
			DECLARE @idDdt CHAR(16), @idSedeDdt CHAR(16), @lockDdt INT;
			SELECT @idDdt = Id, @idSedeDdt = IdSede, @lockDdt = Lock
			FROM dbo.tblMagazziniDdt
			WHERE IdMovimento = @Id;

			IF @idDdt IS NOT NULL AND @lockDdt IN (0, 2)
			BEGIN
				SET @DdtIdCausale = NULLIF(LTRIM(RTRIM(@DdtIdCausale)), '');
				SET @DdtNumeroFornitore = dbo.ufnStringhe_get_SenzaSpazi(@DdtNumeroFornitore, 0, 1);
				SET @DdtSezionale = NULLIF(LTRIM(RTRIM(@DdtSezionale)), '');
				SET @DdtIdMittente = NULLIF(LTRIM(RTRIM(@DdtIdMittente)), '');
				SET @DdtIdDestinatario = NULLIF(LTRIM(RTRIM(@DdtIdDestinatario)), '');
				SET @DdtIdTrasportatore = NULLIF(LTRIM(RTRIM(@DdtIdTrasportatore)), '');

				-- DDT ricevuto (emesso da un fornitore esterno) = sezionale R, riservato: ammesso
				-- solo sui movimenti di carico e sempre con il numero del documento del fornitore;
				-- viceversa il numero fornitore esiste solo per i DDT ricevuti. Nessun controllo
				-- di univocità sul numero fornitore (scelta esplicita).
				IF @DdtSezionale = 'R'
					AND NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimenti WHERE Id = @Id AND IdOperazione = 'C')
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il sezionale R è riservato ai DDT ricevuti, ammessi solo sui movimenti di carico';
					GOTO BRANCH_END;
				END
				IF @DdtSezionale = 'R' AND @DdtNumeroFornitore IS NULL
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Indicare il numero fornitore del DDT ricevuto';
					GOTO BRANCH_END;
				END
				IF @DdtNumeroFornitore IS NOT NULL AND ISNULL(@DdtSezionale, '') <> 'R'
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il numero fornitore si indica solo per i DDT ricevuti';
					GOTO BRANCH_END;
				END

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

				IF @DdtIdCausale IS NULL OR @DdtData IS NULL OR @DdtIdDestinatario IS NULL
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Completare il DDT: causale, data e destinatario';
					GOTO BRANCH_END;
				END

				-- Numerazione indipendente per sede interna + sezionale, calcolata dentro
				-- la transazione con lock di riga per evitare duplicati in caso di
				-- richieste concorrenti sulla stessa sede/sezionale
				DECLARE @numeroDdt INT;
				IF @lockDdt = 2
				BEGIN
					-- DDT in bozza: numero assegnato qui, progressivo della serie
					SELECT @numeroDdt = ISNULL(MAX(Numero), 0) + 1
					FROM dbo.tblMagazziniDdt WITH (UPDLOCK, HOLDLOCK)
					WHERE
						IdSede = @idSedeDdt
						AND (Sezionale = @DdtSezionale OR (Sezionale IS NULL AND @DdtSezionale IS NULL))
						AND Id <> @idDdt;
				END
				ELSE
				BEGIN
					-- DDT già confermato: numero indicato dall'utente, unico nella serie (sede
					-- interna + sezionale) tra i DDT confermati. Nessuna rinumerazione automatica
					-- degli altri DDT: sono documenti già emessi.
					IF @DdtNumero IS NULL OR @DdtNumero < 1
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Indicare il numero del DDT';
						GOTO BRANCH_END;
					END
					IF EXISTS (
						SELECT 1
						FROM dbo.tblMagazziniDdt WITH (UPDLOCK, HOLDLOCK)
						WHERE
							IdSede = @idSedeDdt
							AND (Sezionale = @DdtSezionale OR (Sezionale IS NULL AND @DdtSezionale IS NULL))
							AND Numero = @DdtNumero
							AND Lock = 0
							AND Id <> @idDdt
					)
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Un altro DDT della stessa sede e dello stesso sezionale ha già il numero ' + CAST(@DdtNumero AS VARCHAR(10));
						GOTO BRANCH_END;
					END
					SET @numeroDdt = @DdtNumero;
				END

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

			-- Relazioni carico/scarico delle righe tradizionali (stessa logica di
			-- uspRifiutiRegistrazioni_upd): la riga di carico è essa stessa la giacenza, la
			-- riga di scarico si relaziona alle righe di carico che consuma. L'unica variante
			-- è l'ordine di consumo, dato dal criterio di scarico della riga:
			--   M (Manuale) solo i carichi del lotto scelto sulla riga, dal più vecchio;
			--   F (FIFO per lotto) lotti per data di apertura crescente, poi carichi dal più vecchio;
			--   L (LIFO per lotto) lotti per data di apertura decrescente, poi carichi dal più recente;
			--   E (FEFO) lotti per scadenza (DataChiusura) crescente, poi carichi dal più vecchio;
			--   V (FIFO per carico) carichi per data/numero crescenti;
			--   R (LIFO per carico) carichi per data/numero decrescenti.
			-- Carichi candidati: stessa Sede+Articolo, movimento di carico confermato,
			-- cronologicamente precedente allo scarico (a parità di data, numero inferiore;
			-- scarico non ancora numerato = dopo tutti i confermati), residuo > 0. Il residuo
			-- di un carico è la sua quantità meno le relazioni di scarichi non eliminati.
			-- Si ricostruiscono tutte le righe in bozza o se sono cambiati data/numero di un
			-- movimento confermato; altrimenti, sul confermato, solo le righe non ancora
			-- completamente relazionate (le altre sono storia consolidata).
			IF @idOperazione = 'S'
			BEGIN
				DECLARE
					@idRiga CHAR(16),
					@idSedeRiga CHAR(16),
					@idArticoloRiga CHAR(16),
					@idCriterioRiga CHAR(1),
					@idLottoRiga CHAR(16),
					@quantitaRiga DECIMAL(18, 2),
					@articoloNome VARCHAR(50),
					@lottoNome VARCHAR(50),
					@isNumero BIT,
					@daRelazionare DECIMAL(18, 2),
					@idCarico CHAR(16),
					@residuoCarico DECIMAL(18, 2),
					@quotaCarico DECIMAL(18, 2),
					@rowNum INT,
					@maxRow INT;

				CREATE TABLE #Candidati (
					RowNum INT IDENTITY(1, 1) PRIMARY KEY,
					IdCarico CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
					Residuo DECIMAL(18, 2) NOT NULL
				);

				DECLARE cRighe CURSOR LOCAL FAST_FORWARD FOR
					SELECT
						r.Id,
						r.IdSede,
						r.IdArticolo,
						r.IdCriterio,
						r.IdLotto,
						r.Quantita,
						a.Nome,
						lr.Nome,
						CAST(IIF(a.IdUnitaMisura = 'NR', 1, 0) AS BIT)
					FROM
						dbo.tblMagazziniMovimentiRighe r
						LEFT JOIN dbo.tblMagazziniArticoli a ON r.IdArticolo = a.Id
						LEFT JOIN dbo.tblMagazziniLotti lr ON r.IdLotto = lr.Id
						OUTER APPLY (SELECT Relazionata = SUM(rel.Quantita) FROM dbo.tblMagazziniMovimentiRigheRelazioni rel WHERE rel.IdParent = r.Id) q
					WHERE
						r.IdMovimento = @Id
						-- Le righe descrittive del DDT (senza articolo) non scaricano nulla
						AND r.IdArticolo IS NOT NULL
						AND (@lockMovimento = 2 OR @dataNumeroModificati = 1 OR ISNULL(q.Relazionata, 0) <> r.Quantita)
					ORDER BY r.Id;

				OPEN cRighe;
				FETCH cRighe INTO @idRiga, @idSedeRiga, @idArticoloRiga, @idCriterioRiga, @idLottoRiga, @quantitaRiga, @articoloNome, @lottoNome, @isNumero;

				WHILE @@FETCH_STATUS = 0
				BEGIN
					IF @idCriterioRiga IS NULL OR (@idCriterioRiga = 'M' AND @idLottoRiga IS NULL)
					BEGIN
						CLOSE cRighe;
						DEALLOCATE cRighe;
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Completare il criterio di scarico della riga dell''articolo ' + ISNULL(@articoloNome, '');
						GOTO BRANCH_END;
					END

					-- Relazioni ricostruite da zero nell'ordine del criterio. Lock di riga
					-- (UPDLOCK/HOLDLOCK) sulle relazioni dei carichi candidati, per serializzare
					-- scarichi concorrenti sugli stessi carichi.
					TRUNCATE TABLE #Candidati;

					DELETE dbo.tblMagazziniMovimentiRigheRelazioni
					WHERE IdParent = @idRiga;

					INSERT INTO #Candidati (IdCarico, Residuo)
					SELECT
						rc.Id,
						rc.Quantita - ISNULL(c.Consumata, 0)
					FROM
						dbo.tblMagazziniMovimentiRighe rc
						INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
						LEFT JOIN dbo.tblMagazziniLotti l ON rc.IdLotto = l.Id
						OUTER APPLY (
							SELECT Consumata = SUM(rel.Quantita)
							FROM
								dbo.tblMagazziniMovimentiRigheRelazioni rel WITH (UPDLOCK, HOLDLOCK)
								INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
								INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
							WHERE
								rel.Id = rc.Id
								AND mp.Lock IN (0, 2)
						) c
					WHERE
						mc.IdOperazione = 'C'
						AND mc.Lock = 0
						AND rc.Lock = 0
						AND rc.IdSede = @idSedeRiga
						AND rc.IdArticolo = @idArticoloRiga
						AND (@idCriterioRiga <> 'M' OR rc.IdLotto = @idLottoRiga)
						AND (
							mc.[Data] < @Data
							OR (mc.[Data] = @Data AND (@Numero IS NULL OR mc.Numero < @Numero))
						)
						AND rc.Quantita - ISNULL(c.Consumata, 0) > 0
					ORDER BY
						CASE WHEN @idCriterioRiga = 'F' THEN l.DataApertura END ASC,
						CASE WHEN @idCriterioRiga = 'L' THEN l.DataApertura END DESC,
						CASE WHEN @idCriterioRiga = 'E' THEN ISNULL(l.DataChiusura, '9999-12-31') END ASC,
						CASE WHEN @idCriterioRiga IN ('L', 'R') THEN mc.[Data] END DESC,
						CASE WHEN @idCriterioRiga IN ('L', 'R') THEN mc.Numero END DESC,
						mc.[Data] ASC,
						mc.Numero ASC,
						rc.Id;

					-- Distribuzione greedy, carico per carico, fino al residuo di ciascuno
					SET @daRelazionare = @quantitaRiga;
					SET @rowNum = 1;
					SET @maxRow = ISNULL((SELECT MAX(RowNum) FROM #Candidati), 0);

					WHILE @daRelazionare > 0 AND @rowNum <= @maxRow
					BEGIN
						SELECT @idCarico = IdCarico, @residuoCarico = Residuo FROM #Candidati WHERE RowNum = @rowNum;
						SET @quotaCarico = IIF(@residuoCarico < @daRelazionare, @residuoCarico, @daRelazionare);

						IF @quotaCarico > 0
						BEGIN
							INSERT dbo.tblMagazziniMovimentiRigheRelazioni (Id, IdParent, Quantita, Pos)
							VALUES (@idCarico, @idRiga, @quotaCarico, @rowNum - 1);

							SET @daRelazionare = @daRelazionare - @quotaCarico;
						END

						SET @rowNum = @rowNum + 1;
					END

					IF @daRelazionare > 0
					BEGIN
						CLOSE cRighe;
						DEALLOCATE cRighe;
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage =
							'Giacenza insufficiente '
							+ IIF(@idCriterioRiga = 'M', 'nel lotto ' + ISNULL(@lottoNome, '') + ' ', '')
							+ 'per l''articolo ' + ISNULL(@articoloNome, '')
							+ ' (mancano ' + FORMAT(@daRelazionare, IIF(@isNumero = 1, 'N0', 'N2'), 'it-IT') + ')';
						GOTO BRANCH_END;
					END

					FETCH cRighe INTO @idRiga, @idSedeRiga, @idArticoloRiga, @idCriterioRiga, @idLottoRiga, @quantitaRiga, @articoloNome, @lottoNome, @isNumero;
				END

				CLOSE cRighe;
				DEALLOCATE cRighe;
			END

			-- Relazioni delle righe EoW (stessa logica delle righe tradizionali): per l'EoW il
			-- "carico" è il lotto EoW, alimentato dalle quote delle registrazioni rifiuti M
			-- (tblEoWLottiRifiutiRegistrazioni); la riga EoW di scarico si relaziona ai lotti EoW
			-- che consuma (tblMagazziniMovimentiRigheEoWLotti). Ordine di consumo dal criterio:
			--   M (Manuale) solo il lotto EoW scelto sulla riga;
			--   F (FIFO) lotti per data di apertura crescente; L (LIFO) decrescente;
			--   E (FEFO) lotti per scadenza (DataChiusura) crescente.
			-- Lotti candidati: stessa Sede+Materiale, attivi, non disabilitati. Disponibile alla
			-- data dello scarico = quote di registrazioni M attive con data <= data dello scarico
			-- (non si scarica materiale non ancora prodotto a quella data) meno quanto già
			-- scaricato dal lotto da scarichi non eliminati.
			DECLARE
				@idRigaEoW CHAR(16),
				@idSedeRigaEoW CHAR(16),
				@idMaterialeRigaEoW CHAR(2),
				@idCriterioRigaEoW CHAR(1),
				@idLottoRigaEoW CHAR(16),
				@quantitaRigaEoW DECIMAL(18, 2),
				@materialeNome VARCHAR(100),
				@lottoEoWNome VARCHAR(50),
				@daRelazionareEoW DECIMAL(18, 2),
				@idLottoEoW CHAR(16),
				@residuoLottoEoW DECIMAL(18, 2),
				@quotaLottoEoW DECIMAL(18, 2),
				@rowNumEoW INT,
				@maxRowEoW INT;

			CREATE TABLE #CandidatiEoW (
				RowNum INT IDENTITY(1, 1) PRIMARY KEY,
				IdLotto CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
				Residuo DECIMAL(18, 2) NOT NULL
			);

			DECLARE cRigheEoW CURSOR LOCAL FAST_FORWARD FOR
				SELECT
					r.Id,
					r.IdSede,
					r.IdMateriale,
					r.IdCriterio,
					r.IdLotto,
					r.Quantita,
					m.Nome,
					lr.Nome
				FROM
					dbo.tblMagazziniMovimentiRigheEoW r
					LEFT JOIN dbo.tblRifiutiMateriali m ON r.IdMateriale = m.Id
					LEFT JOIN dbo.tblEoWLotti lr ON r.IdLotto = lr.Id
					OUTER APPLY (SELECT Relazionata = SUM(rl.Quantita) FROM dbo.tblMagazziniMovimentiRigheEoWLotti rl WHERE rl.Id = r.Id) q
				WHERE
					r.IdMovimento = @Id
					AND (@lockMovimento = 2 OR @dataNumeroModificati = 1 OR ISNULL(q.Relazionata, 0) <> r.Quantita)
				ORDER BY r.Id;

			OPEN cRigheEoW;
			FETCH cRigheEoW INTO @idRigaEoW, @idSedeRigaEoW, @idMaterialeRigaEoW, @idCriterioRigaEoW, @idLottoRigaEoW, @quantitaRigaEoW, @materialeNome, @lottoEoWNome;

			WHILE @@FETCH_STATUS = 0
			BEGIN
				IF @idCriterioRigaEoW IS NULL OR @idCriterioRigaEoW NOT IN ('M', 'F', 'L', 'E') OR (@idCriterioRigaEoW = 'M' AND @idLottoRigaEoW IS NULL)
				BEGIN
					CLOSE cRigheEoW;
					DEALLOCATE cRigheEoW;
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Completare il criterio di scarico della riga del materiale ' + ISNULL(@materialeNome, '');
					GOTO BRANCH_END;
				END

				-- Relazioni ricostruite da zero nell'ordine del criterio. Lock di riga
				-- (UPDLOCK/HOLDLOCK) sulle relazioni dei lotti candidati, per serializzare
				-- scarichi concorrenti sugli stessi lotti EoW.
				TRUNCATE TABLE #CandidatiEoW;

				DELETE dbo.tblMagazziniMovimentiRigheEoWLotti
				WHERE Id = @idRigaEoW;

				INSERT INTO #CandidatiEoW (IdLotto, Residuo)
				SELECT
					l.Id,
					ISNULL(p.Prodotta, 0) - ISNULL(sc.Scaricata, 0)
				FROM
					dbo.tblEoWLotti l
					OUTER APPLY (
						SELECT Prodotta = SUM(qp.Quantita)
						FROM
							dbo.tblEoWLottiRifiutiRegistrazioni qp
							INNER JOIN dbo.tblRifiutiRegistrazioni rr ON qp.IdRegistrazione = rr.Id
						WHERE
							qp.IdLotto = l.Id
							AND rr.Lock < 2
							AND rr.[Data] <= @Data
					) p
					OUTER APPLY (
						SELECT Scaricata = SUM(rs.Quantita)
						FROM
							dbo.tblMagazziniMovimentiRigheEoWLotti rs WITH (UPDLOCK, HOLDLOCK)
							INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rp ON rs.Id = rp.Id
							INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
						WHERE
							rs.IdLotto = l.Id
							AND mp.Lock IN (0, 2)
					) sc
				WHERE
					l.IdSede = @idSedeRigaEoW
					AND l.IdMateriale = @idMaterialeRigaEoW
					AND l.Lock = 0
					AND ISNULL(l.Disabilitato, 0) = 0
					AND (@idCriterioRigaEoW <> 'M' OR l.Id = @idLottoRigaEoW)
					AND ISNULL(p.Prodotta, 0) - ISNULL(sc.Scaricata, 0) > 0
				ORDER BY
					CASE WHEN @idCriterioRigaEoW = 'L' THEN l.DataApertura END DESC,
					CASE WHEN @idCriterioRigaEoW = 'E' THEN ISNULL(l.DataChiusura, '9999-12-31') END ASC,
					l.DataApertura ASC,
					l.Id;

				-- Distribuzione greedy, lotto per lotto, fino al disponibile di ciascuno
				SET @daRelazionareEoW = @quantitaRigaEoW;
				SET @rowNumEoW = 1;
				SET @maxRowEoW = ISNULL((SELECT MAX(RowNum) FROM #CandidatiEoW), 0);

				WHILE @daRelazionareEoW > 0 AND @rowNumEoW <= @maxRowEoW
				BEGIN
					SELECT @idLottoEoW = IdLotto, @residuoLottoEoW = Residuo FROM #CandidatiEoW WHERE RowNum = @rowNumEoW;
					SET @quotaLottoEoW = IIF(@residuoLottoEoW < @daRelazionareEoW, @residuoLottoEoW, @daRelazionareEoW);

					IF @quotaLottoEoW > 0
					BEGIN
						INSERT dbo.tblMagazziniMovimentiRigheEoWLotti (Id, IdLotto, Quantita, Pos)
						VALUES (@idRigaEoW, @idLottoEoW, @quotaLottoEoW, @rowNumEoW - 1);

						SET @daRelazionareEoW = @daRelazionareEoW - @quotaLottoEoW;
					END

					SET @rowNumEoW = @rowNumEoW + 1;
				END

				IF @daRelazionareEoW > 0
				BEGIN
					CLOSE cRigheEoW;
					DEALLOCATE cRigheEoW;
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage =
						'Giacenza insufficiente '
						+ IIF(@idCriterioRigaEoW = 'M', 'nel lotto EoW ' + ISNULL(@lottoEoWNome, '') + ' ', '')
						+ 'per il materiale ' + ISNULL(@materialeNome, '')
						+ ' (mancano ' + FORMAT(@daRelazionareEoW, 'N2', 'it-IT') + ')';
					GOTO BRANCH_END;
				END

				FETCH cRigheEoW INTO @idRigaEoW, @idSedeRigaEoW, @idMaterialeRigaEoW, @idCriterioRigaEoW, @idLottoRigaEoW, @quantitaRigaEoW, @materialeNome, @lottoEoWNome;
			END

			CLOSE cRigheEoW;
			DEALLOCATE cRigheEoW;

			-- Conferma (o riconferma) del movimento: "Salva" conferma sempre, come le
			-- Registrazioni Rifiuti; ogni condizione non soddisfatta ha già bloccato sopra
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

				-- Carico già confermato spostato di data/numero: non può finire dopo gli scarichi
				-- (non eliminati) che ne consumano le righe (come il "Controllo data relazioni"
				-- delle Registrazioni Rifiuti)
				IF @idOperazione = 'C' AND @dataNumeroModificati = 1 AND EXISTS (
					SELECT 1
					FROM
						dbo.tblMagazziniMovimentiRighe rc
						INNER JOIN dbo.tblMagazziniMovimentiRigheRelazioni rel ON rel.Id = rc.Id
						INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
						INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
					WHERE
						rc.IdMovimento = @Id
						AND mp.Lock IN (0, 2)
						AND (
							mp.[Data] < @Data
							OR (mp.[Data] = @Data AND mp.Numero IS NOT NULL AND mp.Numero <= @Numero)
						)
				)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il carico è già utilizzato da scarichi con data e/o numero precedenti';
					GOTO BRANCH_END;
				END

				UPDATE dbo.tblMagazziniMovimenti
				SET
					Lock = 0,
					Numero = @Numero
				WHERE
					Id = @Id
					AND Lock IN (0, 2);

				UPDATE dbo.tblMagazziniMovimentiRighe
				SET Lock = 0
				WHERE IdMovimento = @Id;

				UPDATE dbo.tblMagazziniMovimentiRigheEoW
				SET Lock = 0
				WHERE IdMovimento = @Id;

				SET @confermato = IIF(@lockMovimento = 2, 1, 0);
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
