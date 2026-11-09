SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione da Ecomatico 3.1, fase 8: configurazione RENTRI. SP interna di uspMigrazioni31_ins, eseguita dentro la
-- sua transazione (scrive anche nel DB dell'hub [1_0_rentri], sulla stessa istanza); legge #registri calcolato da
-- uspMigrazioni31_get_Perimetro e scrive nel #log del chiamante. Va eseguita dopo gli utenti (fase 7), per lo storico.
-- La 3.1 e la 4.0 restano collegate agli stessi certificati e agli stessi registri RENTRI, ma ognuna con le proprie
-- righe dell'hub, tranne il certificato: cosi' le modifiche di un'app (per esempio "Scollega", che cancella la riga
-- dell'hub del registro, o il cambio di credenziale di una sede) non toccano l'altra.
-- 1) Certificati attivi del dominio 3.1 collegati all'hub: la riga dell'hub (file e password) e' condivisa, il
--    certificato 4.0 ha lo stesso IdRentri. Se nel dominio 4.0 c'e' gia' un certificato attivo con quell'IdRentri si
--    abbina (Creato = 0). Nome unico nel dominio come uspRentriCertificati_upd (" (2)", " (3)"...).
-- 2) Credenziali attive del dominio 3.1 collegate all'hub, con il certificato migrato: nuova riga dell'hub con gli
--    stessi dati (identificativo, accreditamento) sul certificato condiviso. Si abbinano a una credenziale attiva del
--    dominio 4.0 con lo stesso certificato, identificativo e accreditamento.
-- 3) Sedi RENTRI delle sedi dei registri del perimetro: nuova riga dell'hub con lo stesso identificativo della sede
--    RENTRI, sulla credenziale migrata, in posizione 0 (la 3.1 ha una sola credenziale per sede). Una sede 4.0 gia'
--    collegata a RENTRI resta com'e' (W se con un'altra credenziale).
-- 4) Registri del perimetro collegati a RENTRI: nuova riga dell'hub con tutti i dati della riga 3.1 (identificativo,
--    blocco formulari, data di inizio invio, conservazione sostitutiva e suo responsabile), sulla sede RENTRI in
--    posizione 0 della sede 4.0; la quota xFIR (che la 3.1 non ha) resta da impostare. Lo storico degli invii e delle
--    conservazioni della riga 3.1 si copia sulla nuova riga (senza doppioni a una nuova esecuzione), con l'utente 4.0
--    migrato al posto di quello 3.1 (vuoto se l'utente non e' migrato).
-- Gli Id delle righe dell'hub si generano come nelle SP dell'app (NEWID, C1.6 delle regole RENTRI). I limiti del
-- dominio (RentriMax, ConservazioniMax) non si applicano: li segnala uspMigrazioni31_get_Perimetro.
CREATE OR ALTER PROCEDURE dbo.uspMigrazioni31_ins_Rentri
	@IdMigrazione INT = NULL,
	@IdDominioDa VARCHAR(50) = NULL,
	@IdDominioA CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		IF @IdMigrazione IS NULL OR @IdDominioDa IS NULL OR @IdDominioA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @IdMigrazione, @IdDominioDa e @IdDominioA sono obbligatori';
			GOTO BRANCH_END;
		END

		DECLARE @id CHAR(16);
		DECLARE @idEsistente CHAR(16);
		DECLARE @idRentri CHAR(16);
		DECLARE @nomeBase VARCHAR(50);
		DECLARE @nome VARCHAR(50);
		DECLARE @progressivo INT;
		DECLARE @dataInserimento DATETIME2(0);

		-- 1) Certificati
		DECLARE @idCertificato31 CHAR(16);
		DECLARE @scadenza DATE;

		DECLARE cc CURSOR LOCAL FAST_FORWARD FOR
			SELECT c.IDCertificato, c.IDRentri, ISNULL(NULLIF(LTRIM(RTRIM(c.Nome)), ''), 'Certificato'), c.Scadenza, x.DataInserimento
			FROM
				dbo.syn31RentriCertificati c
				INNER JOIN [1_0_rentri]..tblCertificati h ON c.IDRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
				LEFT JOIN dbo.syn31ID x ON c.IDCertificato = x.ID
			WHERE
				c.IDDominio = @IdDominioDa
				AND ISNULL(c.Lock, 0) = 0
				AND NOT EXISTS (SELECT 1 FROM dbo.tblMigrazioniId mc WHERE mc.Versione = '31' AND mc.IdDominioA = @IdDominioA AND mc.Tabella = 'tblRentriCertificati' AND mc.IdOrigine = c.IDCertificato COLLATE DATABASE_DEFAULT)
			ORDER BY c.IDCertificato;

		OPEN cc;
		FETCH cc INTO @idCertificato31, @idRentri, @nomeBase, @scadenza, @dataInserimento;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblRentriCertificati
			WHERE
				IdRentri = @idRentri COLLATE DATABASE_DEFAULT
				AND Lock < 2
				AND IdDominio <> @IdDominioA
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = CONCAT('Certificato ', @nomeBase, ': gia'' collegato a un certificato di un altro dominio 4.0');
				GOTO BRANCH_END;
			END

			SET @idEsistente = (SELECT TOP 1 Id
			FROM dbo.tblRentriCertificati
			WHERE
				IdRentri = @idRentri COLLATE DATABASE_DEFAULT
				AND Lock = 0
				AND IdDominio = @IdDominioA
			ORDER BY Id);

			IF @idEsistente IS NOT NULL
			BEGIN
				SET @id = @idEsistente;

				EXEC dbo.uspMigrazioniId_ins
					@Versione = '31',
					@IdDominioA = @IdDominioA,
					@Tabella = 'tblRentriCertificati',
					@IdOrigine = @idCertificato31,
					@IdMigrazione = @IdMigrazione,
					@Id = @id OUTPUT;

				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				VALUES ('RENTRI', 'I', 'tblRentriCertificati', @idCertificato31, 0, CONCAT('Certificato ', @nomeBase, ' abbinato al certificato 4.0 ', @id, ' con la stessa riga dell''hub'));
			END
			ELSE
			BEGIN
				SET @nome = @nomeBase;
				SET @progressivo = 1;

				WHILE EXISTS (SELECT 1
				FROM dbo.tblRentriCertificati
				WHERE
					IdDominio = @IdDominioA
					AND Lock = 0
					AND Nome = @nome
				)
				BEGIN
					SET @progressivo += 1;
					SET @nome = CONCAT(LEFT(@nomeBase, 50 - LEN(CONCAT(' (', @progressivo, ')'))), ' (', @progressivo, ')');
				END

				SET @id = NULL;

				EXEC dbo.uspMigrazioniId_ins
					@Versione = '31',
					@IdDominioA = @IdDominioA,
					@Tabella = 'tblRentriCertificati',
					@IdOrigine = @idCertificato31,
					@IdMigrazione = @IdMigrazione,
					@DataInserimento = @dataInserimento,
					@Id = @id OUTPUT;

				INSERT INTO dbo.tblRentriCertificati (Id, IdDominio, IdRentri, Nome, DataScadenza, Lock)
				VALUES (@id, @IdDominioA, @idRentri, @nome, @scadenza, 0);

				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				VALUES ('RENTRI', IIF(@nome = @nomeBase, 'I', 'W'), 'tblRentriCertificati', @idCertificato31, 1,
					CONCAT('Creato il certificato ', @id, ' "', @nome, '" sulla riga dell''hub della 3.1 (', @idRentri, ')', IIF(@nome = @nomeBase, '', ' (nome gia'' presente nel dominio)')));
			END

			FETCH cc INTO @idCertificato31, @idRentri, @nomeBase, @scadenza, @dataInserimento;
		END

		CLOSE cc;
		DEALLOCATE cc;

		-- 2) Credenziali
		DECLARE @idCredenziale31 CHAR(16);
		DECLARE @idCertificato40 CHAR(16);
		DECLARE @idRentriCertificato CHAR(16);
		DECLARE @idAccreditamento CHAR(1);
		DECLARE @identificativo VARCHAR(30);
		DECLARE @accreditamento VARCHAR(20);

		DECLARE ck CURSOR LOCAL FAST_FORWARD FOR
			SELECT k.IDCredenziale, mc.IdDestinazione, c40.IdRentri, k.IDAccreditamento, h.Identificativo, h.Accreditamento, ISNULL(NULLIF(LTRIM(RTRIM(k.Nome)), ''), 'Credenziale'), x.DataInserimento
			FROM
				dbo.syn31RentriCredenziali k
				INNER JOIN [1_0_rentri]..tblCredenziali h ON k.IDRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
				INNER JOIN dbo.tblMigrazioniId mc ON mc.Versione = '31'
					AND mc.IdDominioA = @IdDominioA
					AND mc.Tabella = 'tblRentriCertificati'
					AND mc.IdOrigine = k.IDCertificato COLLATE DATABASE_DEFAULT
				INNER JOIN dbo.tblRentriCertificati c40 ON mc.IdDestinazione = c40.Id
				LEFT JOIN dbo.syn31ID x ON k.IDCredenziale = x.ID
			WHERE
				k.IDDominio = @IdDominioDa
				AND ISNULL(k.Lock, 0) = 0
				AND NOT EXISTS (SELECT 1 FROM dbo.tblMigrazioniId mk WHERE mk.Versione = '31' AND mk.IdDominioA = @IdDominioA AND mk.Tabella = 'tblRentriCredenziali' AND mk.IdOrigine = k.IDCredenziale COLLATE DATABASE_DEFAULT)
			ORDER BY k.IDCredenziale;

		OPEN ck;
		FETCH ck INTO @idCredenziale31, @idCertificato40, @idRentriCertificato, @idAccreditamento, @identificativo, @accreditamento, @nomeBase, @dataInserimento;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblRentriAccreditamenti
			WHERE Id = @idAccreditamento COLLATE DATABASE_DEFAULT)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = CONCAT('Credenziale ', @nomeBase, ': accreditamento non presente nella 4.0');
				GOTO BRANCH_END;
			END

			SET @idEsistente = (SELECT TOP 1 k.Id
			FROM
				dbo.tblRentriCredenziali k
				INNER JOIN [1_0_rentri]..tblCredenziali h ON k.IdRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
			WHERE
				k.IdDominio = @IdDominioA
				AND k.Lock = 0
				AND k.IdCertificato = @idCertificato40
				AND k.IdAccreditamento = @idAccreditamento COLLATE DATABASE_DEFAULT
				AND ISNULL(h.Identificativo, '') = ISNULL(@identificativo, '') COLLATE DATABASE_DEFAULT
			ORDER BY k.Id);

			IF @idEsistente IS NOT NULL
			BEGIN
				SET @id = @idEsistente;

				EXEC dbo.uspMigrazioniId_ins
					@Versione = '31',
					@IdDominioA = @IdDominioA,
					@Tabella = 'tblRentriCredenziali',
					@IdOrigine = @idCredenziale31,
					@IdMigrazione = @IdMigrazione,
					@Id = @id OUTPUT;

				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				VALUES ('RENTRI', 'I', 'tblRentriCredenziali', @idCredenziale31, 0, CONCAT('Credenziale ', @nomeBase, ' abbinata alla credenziale 4.0 ', @id, ' (stesso certificato e identificativo)'));
			END
			ELSE
			BEGIN
				SET @nome = @nomeBase;
				SET @progressivo = 1;

				WHILE EXISTS (SELECT 1
				FROM dbo.tblRentriCredenziali
				WHERE
					IdDominio = @IdDominioA
					AND Lock = 0
					AND Nome = @nome
				)
				BEGIN
					SET @progressivo += 1;
					SET @nome = CONCAT(LEFT(@nomeBase, 50 - LEN(CONCAT(' (', @progressivo, ')'))), ' (', @progressivo, ')');
				END

				SET @id = NULL;

				EXEC dbo.uspMigrazioniId_ins
					@Versione = '31',
					@IdDominioA = @IdDominioA,
					@Tabella = 'tblRentriCredenziali',
					@IdOrigine = @idCredenziale31,
					@IdMigrazione = @IdMigrazione,
					@DataInserimento = @dataInserimento,
					@Id = @id OUTPUT;

				SET @idRentri = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));

				INSERT INTO [1_0_rentri]..tblCredenziali (Id, IdCertificato, Identificativo, Accreditamento)
				VALUES (@idRentri, @idRentriCertificato, @identificativo, @accreditamento);

				INSERT INTO dbo.tblRentriCredenziali (Id, IdDominio, IdCertificato, IdAccreditamento, IdRentri, Nome, Lock)
				VALUES (@id, @IdDominioA, @idCertificato40, @idAccreditamento, @idRentri, @nome, 0);

				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				VALUES ('RENTRI', IIF(@nome = @nomeBase, 'I', 'W'), 'tblRentriCredenziali', @idCredenziale31, 1,
					CONCAT('Creata la credenziale ', @id, ' "', @nome, '" (', @identificativo, ')', IIF(@nome = @nomeBase, '', ' (nome gia'' presente nel dominio)')));
			END

			FETCH ck INTO @idCredenziale31, @idCertificato40, @idRentriCertificato, @idAccreditamento, @identificativo, @accreditamento, @nomeBase, @dataInserimento;
		END

		CLOSE ck;
		DEALLOCATE ck;

		-- 3) Sedi RENTRI delle sedi dei registri del perimetro
		DECLARE @idSede31 CHAR(16);
		DECLARE @idSede40 CHAR(16);
		DECLARE @idCredenziale40 CHAR(16);
		DECLARE @idRentriCredenziale CHAR(16);
		DECLARE @idCredenzialePos0 CHAR(16);

		DECLARE cs CURSOR LOCAL FAST_FORWARD FOR
			SELECT rs.IDSede, ms.IdDestinazione, mk.IdDestinazione, k40.IdRentri, h.Identificativo
			FROM
				(SELECT DISTINCT IdSede
				FROM #registri) g
				INNER JOIN dbo.syn31RentriSedi rs ON g.IdSede = rs.IDSede COLLATE DATABASE_DEFAULT
				INNER JOIN [1_0_rentri]..tblSedi h ON rs.IDRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
				INNER JOIN dbo.tblMigrazioniId ms ON ms.Versione = '31'
					AND ms.IdDominioA = @IdDominioA
					AND ms.Tabella = 'tblSedi'
					AND ms.IdOrigine = rs.IDSede COLLATE DATABASE_DEFAULT
				LEFT JOIN dbo.tblMigrazioniId mk ON mk.Versione = '31'
					AND mk.IdDominioA = @IdDominioA
					AND mk.Tabella = 'tblRentriCredenziali'
					AND mk.IdOrigine = rs.IDCredenziale COLLATE DATABASE_DEFAULT
				LEFT JOIN dbo.tblRentriCredenziali k40 ON mk.IdDestinazione = k40.Id
					AND k40.Lock = 0
			ORDER BY rs.IDSede;

		OPEN cs;
		FETCH cs INTO @idSede31, @idSede40, @idCredenziale40, @idRentriCredenziale, @identificativo;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @idCredenzialePos0 = (SELECT IdCredenziale
			FROM dbo.tblRentriCredenzialiSedi
			WHERE
				IdSede = @idSede40
				AND Pos = 0
			);

			IF @idCredenzialePos0 IS NOT NULL
			BEGIN
				IF @idCredenzialePos0 <> ISNULL(@idCredenziale40, '')
					INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Messaggio)
					VALUES ('RENTRI', 'W', 'tblRentriCredenzialiSedi', @idSede31, CONCAT('La sede 4.0 ', @idSede40, ' e'' gia'' collegata a RENTRI con un''altra credenziale: collegamento della 4.0 mantenuto'));
			END
			ELSE IF @idRentriCredenziale IS NULL
			BEGIN
				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Messaggio)
				VALUES ('RENTRI', 'W', 'tblRentriCredenzialiSedi', @idSede31, 'Credenziale RENTRI della sede non migrata (non attiva o senza certificato collegato): sede non collegata a RENTRI');
			END
			ELSE
			BEGIN
				SET @idRentri = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));

				INSERT INTO [1_0_rentri]..tblSedi (Id, IdCredenziale, Identificativo)
				VALUES (@idRentri, @idRentriCredenziale, @identificativo);

				INSERT INTO dbo.tblRentriCredenzialiSedi (IdSede, IdCredenziale, IdRentri, Pos)
				VALUES (@idSede40, @idCredenziale40, @idRentri, 0);

				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				VALUES ('RENTRI', 'I', 'tblRentriCredenzialiSedi', @idSede31, 1, CONCAT('Sede ', @idSede40, ' collegata a RENTRI (', @identificativo, ')'));
			END

			FETCH cs INTO @idSede31, @idSede40, @idCredenziale40, @idRentriCredenziale, @identificativo;
		END

		CLOSE cs;
		DEALLOCATE cs;

		-- 4) Registri del perimetro collegati a RENTRI, con lo storico di invii e conservazioni
		DECLARE @idRegistro31 CHAR(16);
		DECLARE @idRegistro40 CHAR(16);
		DECLARE @idRentri31 CHAR(16);
		DECLARE @idRentriSede CHAR(16);
		DECLARE @conservazione BIT;
		DECLARE @invii INT;
		DECLARE @conservazioni INT;

		DECLARE cr CURSOR LOCAL FAST_FORWARD FOR
			SELECT g.Id, mr.IdDestinazione, h.Id, h.Identificativo, ISNULL(h.Conservazione, 0)
			FROM
				#registri g
				INNER JOIN dbo.syn31RentriRegistri rr ON g.Id = rr.IDRegistro COLLATE DATABASE_DEFAULT
				INNER JOIN [1_0_rentri]..tblRegistri h ON rr.IDRentri COLLATE DATABASE_DEFAULT = h.Id COLLATE DATABASE_DEFAULT
				INNER JOIN dbo.tblMigrazioniId mr ON mr.Versione = '31'
					AND mr.IdDominioA = @IdDominioA
					AND mr.Tabella = 'tblRifiutiRegistri'
					AND mr.IdOrigine = g.Id
			ORDER BY g.Id;

		OPEN cr;
		FETCH cr INTO @idRegistro31, @idRegistro40, @idRentri31, @identificativo, @conservazione;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @idRentri = (SELECT IdRentri
			FROM dbo.tblRentriRegistri
			WHERE Id = @idRegistro40);

			IF @idRentri IS NULL
			BEGIN
				SET @idRentriSede = (SELECT cs0.IdRentri
				FROM
					dbo.tblRifiutiRegistri r
					INNER JOIN dbo.tblRentriCredenzialiSedi cs0 ON r.IdSede = cs0.IdSede
						AND cs0.Pos = 0
				WHERE r.Id = @idRegistro40);

				IF @idRentriSede IS NULL
				BEGIN
					INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Messaggio)
					VALUES ('RENTRI', 'W', 'tblRentriRegistri', @idRegistro31, CONCAT('Registro ', ISNULL(@identificativo, '(senza identificativo)'), ': la sede non e'' collegata a RENTRI, collegamento del registro non migrato'));
				END
				ELSE
				BEGIN
					-- Identificativo unico tra i registri 4.0 (uspRentriRegistri_upd); lo controlla gia' la verifica
					IF @identificativo IS NOT NULL
						AND EXISTS (SELECT 1
						FROM
							dbo.tblRentriRegistri x
							INNER JOIN [1_0_rentri]..tblRegistri hx ON x.IdRentri COLLATE DATABASE_DEFAULT = hx.Id COLLATE DATABASE_DEFAULT
						WHERE hx.Identificativo = @identificativo)
					BEGIN
						SET @returnValue = -1;
						SET @returnMessage = CONCAT('Registro ', @identificativo, ': identificativo gia'' usato da un registro 4.0');
						GOTO BRANCH_END;
					END

					SET @idRentri = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));

					INSERT INTO [1_0_rentri]..tblRegistri
						(Id, IdSede, Identificativo, BloccoFormulari, DataInizioInvio, Conservazione, ConservazioneNome, ConservazioneCodiceFiscale, ConservazioneEmail)
					SELECT @idRentri, @idRentriSede, h.Identificativo, h.BloccoFormulari, h.DataInizioInvio, h.Conservazione, h.ConservazioneNome, h.ConservazioneCodiceFiscale, h.ConservazioneEmail
					FROM [1_0_rentri]..tblRegistri h
					WHERE h.Id = @idRentri31;

					INSERT INTO dbo.tblRentriRegistri (Id, IdRentri)
					VALUES (@idRegistro40, @idRentri);

					INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
					VALUES ('RENTRI', 'I', 'tblRentriRegistri', @idRegistro31, 1,
						CONCAT('Registro ', @idRegistro40, ' collegato a RENTRI (', ISNULL(@identificativo, 'senza identificativo'), ')',
							IIF(@conservazione = 1, ', conservazione sostitutiva abilitata: quota xFIR da impostare', '')));
				END
			END

			-- Storico: righe della 3.1 non ancora copiate (stessa data e intervallo)
			IF @idRentri IS NOT NULL
			BEGIN
				INSERT INTO [1_0_rentri]..tblRegistriInvii (Id, IdRegistro, [Data], IdUtente, DalNumero, AlNumero, DalNumeroAnno, AlNumeroAnno)
				SELECT CONVERT(CHAR(36), NEWID()), @idRentri, i.[Data], mu.IdDestinazione, i.DalNumero, i.AlNumero, i.DalNumeroAnno, i.AlNumeroAnno
				FROM
					[1_0_rentri]..tblRegistriInvii i
					LEFT JOIN dbo.tblMigrazioniId mu ON mu.Versione = '31'
						AND mu.IdDominioA = @IdDominioA
						AND mu.Tabella = 'tblUtenti'
						AND mu.IdOrigine COLLATE DATABASE_DEFAULT = i.IdUtente COLLATE DATABASE_DEFAULT
				WHERE
					i.IdRegistro = @idRentri31
					AND NOT EXISTS (SELECT 1 FROM [1_0_rentri]..tblRegistriInvii n WHERE n.IdRegistro = @idRentri AND n.[Data] = i.[Data] AND ISNULL(n.DalNumero, -1) = ISNULL(i.DalNumero, -1) AND ISNULL(n.AlNumero, -1) = ISNULL(i.AlNumero, -1) AND ISNULL(n.DalNumeroAnno, -1) = ISNULL(i.DalNumeroAnno, -1) AND ISNULL(n.AlNumeroAnno, -1) = ISNULL(i.AlNumeroAnno, -1));

				SET @invii = @@ROWCOUNT;

				INSERT INTO [1_0_rentri]..tblRegistriConservazioni (Id, IdRegistro, [Data], DalNumero, AlNumero, Anno, Blocco, Digest, IdUtente, Conservazione)
				SELECT CONVERT(CHAR(36), NEWID()), @idRentri, c.[Data], c.DalNumero, c.AlNumero, c.Anno, c.Blocco, c.Digest, mu.IdDestinazione, c.Conservazione
				FROM
					[1_0_rentri]..tblRegistriConservazioni c
					LEFT JOIN dbo.tblMigrazioniId mu ON mu.Versione = '31'
						AND mu.IdDominioA = @IdDominioA
						AND mu.Tabella = 'tblUtenti'
						AND mu.IdOrigine COLLATE DATABASE_DEFAULT = c.IdUtente COLLATE DATABASE_DEFAULT
				WHERE
					c.IdRegistro = @idRentri31
					AND NOT EXISTS (SELECT 1 FROM [1_0_rentri]..tblRegistriConservazioni n WHERE n.IdRegistro = @idRentri AND n.[Data] = c.[Data] AND ISNULL(n.Anno, -1) = ISNULL(c.Anno, -1) AND ISNULL(n.DalNumero, -1) = ISNULL(c.DalNumero, -1) AND ISNULL(n.AlNumero, -1) = ISNULL(c.AlNumero, -1));

				SET @conservazioni = @@ROWCOUNT;

				IF @invii + @conservazioni > 0
					INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
					VALUES ('RENTRI', 'I', 'tblRegistriInvii', @idRegistro31, @invii + @conservazioni, CONCAT('Storico del registro ', ISNULL(@identificativo, @idRegistro40), ': copiati ', @invii, ' invii e ', @conservazioni, ' conservazioni'));
			END

			FETCH cr INTO @idRegistro31, @idRegistro40, @idRentri31, @identificativo, @conservazione;
		END

		CLOSE cr;
		DEALLOCATE cr;
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
