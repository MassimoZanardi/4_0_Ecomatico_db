-- =====================================================================================
-- Deploy produzione 2026-09-05: Firma remota xFIR - anagrafica utente + blocco cascade
-- Repo: 4_0_ecomatico
--
-- Contesto: l'editing di Codice Fiscale/Nome/Cognome dell'utente si sposta da
-- Impostazioni/Utenti/Edit alla modale "Modifica" di Rentri/FirmaRemota (unico
-- consumatore di questi campi) - uspUtenti_upd non li tocca piu'. Inoltre,
-- tblRentriFirmeCredenziali (introdotta il 2026-09-04) ha 2 FK senza ON DELETE CASCADE
-- (IdCredenziale -> tblRentriCredenziali, IdUtente -> tblUtenti) mai considerate finora
-- nelle SP di cancellazione: aggiunto un blocco esplicito, stesso schema del blocco
-- gia' esistente su Sedi associate in uspRentriCredenziali_del.
--
-- Contenuto:
--   1) CREATE OR ALTER uspUtenti_upd (rimossi @CodiceFiscale/@Nome/@Cognome)
--   2) CREATE uspUtenti_upd_Anagrafica (nuova: gestisce i 3 campi con titolarita' duale,
--      stesso schema di uspRentriFirmeCredenziali_upd_Boarding)
--   3) CREATE OR ALTER uspRentriCredenziali_del (blocca se firma remota Lock=0 collegata)
--   4) CREATE OR ALTER uspUtenti_del (blocca se firma remota Lock=0 collegata; corretto
--      anche un header SET ANSI_NULLS/QUOTED_IDENTIFIER ON mancante da sempre)
--
-- Eseguire con: sqlcmd -S <server> -d 4_0_ecomatico -E -f 65001 -b -i <questo file>
-- =====================================================================================


-- 1) uspUtenti_upd --------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdRuolo CHAR(2) = NULL,
	@Email VARCHAR(50) = NULL,
	@Scadenza DATE = NULL,
	@PasswordScadenzaGiorni INT = NULL,
	@PasswordPrecedenti INT = NULL,
	@PasswordLunghezzaMinima INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametri
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRuolo = NULLIF(LTRIM(RTRIM(@IdRuolo)), '');
		SET @Email = LOWER(dbo.ufnStringhe_get_SenzaSpazi(@Email, 0, 1));

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
		IF @IdRuolo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRuolo non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Email IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Email non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Scadenza IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Scadenza non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @PasswordScadenzaGiorni IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @PasswordScadenzaGiorni non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @PasswordPrecedenti IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @PasswordPrecedenti non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @PasswordLunghezzaMinima IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @PasswordLunghezzaMinima non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controllo permesso sulla funzione (UTE = Gestione Utenti)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'UTE',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idDominioSessione CHAR(16);
		SELECT @idDominioSessione = a.IdDominio
		FROM dbo.tblSessioni s INNER JOIN dbo.tblUtenti a ON a.Id = s.IdUtente
		WHERE s.Id = @IdSessione;

		-- Titolarità: Admin dello stesso Dominio dell'utente target, oppure Admin di un Dominio Master.
		-- Il bypass Master è intenzionale (stesso schema di uspSedi_*): un Master-admin deve poter
		-- gestire utenti di qualsiasi dominio, non solo del proprio.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblUtenti
		WHERE
			Id = @Id
			AND IdDominio = @idDominioSessione
		)
		AND NOT EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE
			Id = @idDominioSessione
			AND [Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'amministratore connesso non può declassarsi a utente
		IF EXISTS (SELECT 1
		FROM dbo.tblUtenti
		WHERE
			Id = @Id
			AND Lock = 0
		)
		AND EXISTS (SELECT 1
		FROM dbo.tblSessioni
		WHERE
			Id = @IdSessione
			AND IdUtente = @Id
		)
		AND @IdRuolo <> 'AD'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''amministratore connesso non può essere declassato al ruolo di utente';
			GOTO BRANCH_END;
		END

		-- Il ruolo Utente Standard richiede almeno una sede interna
		IF @IdRuolo = 'US'
		AND NOT EXISTS (SELECT 1
		FROM dbo.tblUtentiSediInterne
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Aggiungere almeno una sede interna';
			GOTO BRANCH_END;
		END

		-- Deve essere stata impostata una password
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblUtentiPassword
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Impostare una password';
			GOTO BRANCH_END;
		END

		-- Controllo email duplicata PRIMA della transazione:
		-- è una sola lettura, non ha motivo di stare dentro BEGIN TRAN
		IF EXISTS (
			SELECT 1
			FROM dbo.tblUtenti
			WHERE
				Id <> @Id
				AND Lock = 0
				AND Email = @Email
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro utente con lo stesso indirizzo email è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE dbo.tblUtenti
			SET
				IdRuolo = @IdRuolo,
				Email = @Email,
				Scadenza = @Scadenza,
				PasswordScadenzaGiorni = @PasswordScadenzaGiorni,
				PasswordPrecedenti = @PasswordPrecedenti,
				PasswordLunghezzaMinima = @PasswordLunghezzaMinima,
				Lock = 0
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Utente non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			-- Gli Admin non hanno sedi interne né funzioni specifiche
			IF @IdRuolo = 'AD'
			BEGIN
				DELETE dbo.tblUtentiSediInterne
				WHERE Id = @Id;
				DELETE dbo.tblUtentiFunzioni
				WHERE Id = @Id;
			END

			-- Sincronizza la password corrente (la più recente) di tutti gli utenti
			-- Master con quella dell'Admin del Dominio Master
			IF EXISTS (
				SELECT 1
				FROM dbo.tblUtenti u
				INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
				WHERE
					u.Id = @Id
					AND u.IdRuolo = 'AD'
					AND u.Lock = 0
					AND d.[Master] = 1
			)
			BEGIN
				UPDATE up
				SET [Password] = mp.[Password]
				FROM dbo.tblUtentiPassword up
				INNER JOIN dbo.tblUtenti uu ON up.Id = uu.Id
					   -- TOP 1 ORDER BY: solo la password più recente dell'Admin Master
				CROSS JOIN (
						   SELECT TOP 1 [Password]
						   FROM dbo.tblUtentiPassword
						   WHERE Id = @Id
						   ORDER BY [Data] DESC
					   ) mp
				WHERE uu.[Master] = 1;
			END

			-- Invalida i permessi salvati nelle sessioni attive dell'utente
			DELETE p
			FROM dbo.tblSessioniFunzioniPermessi p
			INNER JOIN dbo.tblSessioni s ON p.Id = s.Id
			WHERE s.IdUtente = @Id;

		COMMIT TRANSACTION;

		-- Aggiorna il log operazioni FUORI dalla transazione:
		-- uspId_upd gestisce internamente la propria transazione
		EXEC dbo.uspId_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@Operazione = 'U';

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;


-- 2) uspUtenti_upd_Anagrafica (nuova) -------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_upd_Anagrafica]
	@IdSessione CHAR(16) = NULL,
	@IdUtente CHAR(16) = NULL,
	@CodiceFiscale VARCHAR(20) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Cognome VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		SET @CodiceFiscale = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@CodiceFiscale, 0, 1));
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Cognome = dbo.ufnStringhe_get_SenzaSpazi(@Cognome, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @CodiceFiscale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @CodiceFiscale non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Cognome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Cognome non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFX',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtenteSessione CHAR(16);
		SELECT @idUtenteSessione = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idUtenteSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida';
			GOTO BRANCH_END;
		END

		-- Titolarità sull'utente target: se stesso, oppure Amministratore del suo Dominio
		-- (o di un Dominio Master). Stesso schema di uspRentriFirmeCredenziali_upd_Boarding.
		IF @idUtenteSessione <> @IdUtente
		BEGIN
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblUtenti target
				INNER JOIN dbo.tblUtenti admin ON admin.IdDominio = target.IdDominio
				WHERE
					target.Id = @IdUtente
					AND admin.Id = @idUtenteSessione
					AND admin.IdRuolo = 'AD'
					AND admin.Lock = 0
			)
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblUtenti target
				INNER JOIN dbo.tblUtenti admin ON admin.Id = @idUtenteSessione
				INNER JOIN dbo.tblDomini d ON admin.IdDominio = d.Id
				WHERE
					target.Id = @IdUtente
					AND admin.IdRuolo = 'AD'
					AND admin.Lock = 0
					AND d.[Master] = 1
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END
		END

		UPDATE dbo.tblUtenti
		SET
			CodiceFiscale = @CodiceFiscale,
			Nome = @Nome,
			Cognome = @Cognome
		WHERE
			Id = @IdUtente
			AND Lock = 0;

		IF @@ROWCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Utente non trovato o già eliminato';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspId_upd
			@Id = @IdUtente,
			@IdSessione = @IdSessione,
			@Operazione = 'U';

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


-- 3) uspRentriCredenziali_del ---------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriCredenziali_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: un @Id mai esistito o già cancellato è trattato come cancellazione
		-- già avvenuta con successo, non come errore.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRentriCredenziali
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

			-- Controlla il permesso sul record (titolarità)
			IF NOT EXISTS (
				SELECT 1
				FROM
					dbo.tblRentriCredenziali c
					INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
				WHERE
					c.Id = @Id
					AND e.Id = @IdSessione
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			-- Blocca la cancellazione se esistono Sedi associate
			IF EXISTS (
				SELECT 1
				FROM dbo.tblRentriCredenzialiSedi
				WHERE IdCredenziale = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Impossibile eliminare: la credenziale è associata ad almeno una sede';
				GOTO BRANCH_END;
			END

			-- Blocca la cancellazione se esiste una firma remota attualmente collegata: lo
			-- scollegamento (uspRentriFirmeCredenziali_del) non cancella mai la riga (mantiene
			-- il DeviceIdentifier per un futuro ricollegamento), quindi qui conta solo Lock = 0 -
			-- una riga già scollegata non blocca la cancellazione.
			IF EXISTS (
				SELECT 1
				FROM dbo.tblRentriFirmeCredenziali
				WHERE
					IdCredenziale = @Id
					AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Impossibile eliminare: esiste una firma remota collegata a questa credenziale';
				GOTO BRANCH_END;
			END

			DECLARE @lock INT = (SELECT Lock
			FROM dbo.tblRentriCredenziali
			WHERE Id = @Id);

			-- ── CASO 1: credenziale attiva (Lock = 0) → soft delete ────────────────
			-- La riga hub NON viene toccata, per non perdere dati in caso di Undo.
			IF @lock = 0
			BEGIN
				BEGIN TRANSACTION;
					UPDATE dbo.tblRentriCredenziali
					SET Lock = 4
					WHERE
						Id = @Id
						AND Lock = 0;

					IF @@ROWCOUNT = 0
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Credenziale non trovata o già eliminata';
						GOTO BRANCH_END;
					END

					IF @Reset = 1
						DELETE dbo.tblIdCancellati
						WHERE IdSessione = @IdSessione;
					ELSE
						DELETE dbo.tblIdCancellati
						WHERE Id = @Id;

					INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
					VALUES (@Id, @IdSessione, GETDATE());
				COMMIT TRANSACTION;

				EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
			END

			-- ── CASO 2: credenziale in bozza (Lock = 2) → hard delete ──────────────
			-- Nessuna riga hub esiste ancora a questo punto (creata solo da _upd).
			ELSE IF @lock = 2
			BEGIN
				BEGIN TRANSACTION;
					DELETE dbo.tblRentriFirmeCredenziali
					WHERE IdCredenziale = @Id;
					DELETE dbo.tblRentriCredenziali
					WHERE Id = @Id;
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;
					DELETE dbo.tblIdLog
					WHERE Id = @Id;
					DELETE dbo.tblId
					WHERE Id = @Id;
				COMMIT TRANSACTION;
			END

			-- ── CASO 3: Lock in stato non gestito ───────────────────────────────────
			ELSE
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La credenziale è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
				GOTO BRANCH_END;
			END

		END

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


-- 4) uspUtenti_del --------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametri
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

		-- Controllo permesso sulla funzione (UTE = Gestione Utenti)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'UTE',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idDominioSessione CHAR(16);
		SELECT @idDominioSessione = a.IdDominio
		FROM dbo.tblSessioni s INNER JOIN dbo.tblUtenti a ON a.Id = s.IdUtente
		WHERE s.Id = @IdSessione;

		-- Idempotenza: verifica prima di tutto se l'utente esiste, indipendentemente dalla
		-- titolarità sottostante — mai esistito o già cancellato (es. doppio invio della
		-- richiesta di annullamento lato UI) viene trattato come cancellazione già avvenuta con
		-- successo, non come errore.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblUtenti
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Titolarità: Admin dello stesso Dominio dell'utente target, oppure Admin di un Dominio Master.
		-- Il bypass Master è intenzionale (stesso schema di uspSedi_*): un Master-admin deve poter
		-- gestire utenti di qualsiasi dominio, non solo del proprio.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblUtenti
		WHERE
			Id = @Id
			AND IdDominio = @idDominioSessione
		)
		AND NOT EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE
			Id = @idDominioSessione
			AND [Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Legge Lock dentro la transazione con UPDLOCK:
		-- impedisce che un altro processo modifichi il record
		-- tra la lettura e i DML successivi
		BEGIN TRANSACTION;

			DECLARE @lock INT;
			SELECT @lock = Lock
			FROM dbo.tblUtenti WITH (UPDLOCK)
			WHERE Id = @Id;

			IF @lock IS NULL
			BEGIN
				-- Idempotenza (race condition): l'utente è stato cancellato da un'altra sessione
				-- tra il controllo di esistenza sopra e questa lettura con UPDLOCK — stesso
				-- trattamento, successo silenzioso (il COMMIT sottostante chiude una transazione
				-- senza modifiche, innocuo).
				SET @returnValue = 0;
			END

			-- ── CASO 1: utente attivo (Lock = 0) → soft delete ──────────────
			ELSE IF @lock = 0
			BEGIN
				-- Il master non può essere cancellato
				-- Controllo su tabelle base invece di viewUtenti
				IF EXISTS (
					SELECT 1
					FROM dbo.tblUtenti u
					INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
					WHERE
						u.Id = @Id
						AND u.Lock = 0
						AND d.[Master] = 1 -- dominio Master = visibilità globale
				)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'L''utente Master non può essere cancellato';
					GOTO BRANCH_END;
				END

				-- L'utente connesso non può cancellare se stesso
				IF EXISTS (
					SELECT 1
					FROM dbo.tblSessioni
					WHERE
						Id = @IdSessione
						AND IdUtente = @Id
				)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'L''utente connesso non può cancellare se stesso';
					GOTO BRANCH_END;
				END

				-- Blocca la cancellazione se esiste una firma remota attualmente collegata a
				-- questo utente (stesso schema di uspRentriCredenziali_del): lo scollegamento
				-- non cancella mai la riga, quindi qui conta solo Lock = 0.
				IF EXISTS (
					SELECT 1
					FROM dbo.tblRentriFirmeCredenziali
					WHERE
						IdUtente = @Id
						AND Lock = 0
				)
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'Impossibile eliminare: esiste una firma remota collegata a questo utente';
					GOTO BRANCH_END;
				END

				-- Soft delete: marca l'utente come cancellato
				UPDATE dbo.tblUtenti
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock <= 2;
				--                            ↑ Lock = 4 = cancellato logicamente

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			END

			-- ── CASO 2: utente in bozza (Lock = 2) → hard delete ────────────
			ELSE IF @lock = 2
			BEGIN
				-- Cancellazione fisica a cascata di tutti i dati dell'utente
				DELETE dbo.tblEventiUtenti
				WHERE IdUtente = @Id;
				DELETE dbo.tblUtentiDefault
				WHERE Id = @Id;
				DELETE dbo.tblUtentiFunzioni
				WHERE Id = @Id;
				DELETE dbo.tblUtentiSediInterne
				WHERE Id = @Id;
				DELETE dbo.tblRentriFirmeCredenziali
				WHERE IdUtente = @Id;
				DELETE dbo.tblUtentiPassword
				WHERE Id = @Id;
				DELETE dbo.tblUtenti
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			END

			-- ── CASO 3: Lock in stato non gestito ────────────────────────────
			ELSE
			BEGIN
				-- Lock = 4 (già cancellato) o qualsiasi altro valore imprevisto
				SET @returnValue = -1;
				SET @returnMessage = 'L''utente è già in uno stato non modificabile (Lock = '
									 + CAST(@lock AS VARCHAR(5)) + ')';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		IF @lock = 0
			EXEC dbo.uspId_upd
				@Id = @Id,
				@IdSessione = @IdSessione,
				@Operazione = 'D';

		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
GO
