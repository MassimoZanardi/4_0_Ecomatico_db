SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione da Ecomatico 3.1, fase 7: utenti del dominio e loro sedi. SP interna di uspMigrazioni31_ins, eseguita
-- dentro la sua transazione; scrive nel #log del chiamante. Le anomalie bloccanti (utente esterno, email vuota,
-- doppia nella 3.1 o usata da un altro dominio 4.0) le controlla gia' uspMigrazioni31_get_Perimetro.
-- 1) Utenti: tutti quelli attivi del dominio 3.1 (Lock = 0), esclusi gli utenti Master, anche quando la migrazione
--    riguarda una sola sede interna. Gia' migrati (tblMigrazioniId): restano come sono. Con la stessa email di un
--    utente attivo del dominio 4.0: abbinati (Creato = 0), l'utente 4.0 non si modifica. Gli altri si creano:
--    - ruolo (AD/US), stato (AT/SO) e scadenza come nella 3.1; regole della password 0/0/8 (nessuna scadenza, nessun
--      controllo sulle precedenti, lunghezza minima 8);
--    - nome: la 3.1 ha un solo campo, prima parola = nome, il resto = cognome;
--    - password: la stessa della 3.1 (SHA-1 in esadecimale maiuscolo, che la 4.0 riconosce e al primo accesso
--      riscrive in BCrypt), con la data dell'ultimo cambio nella 3.1; senza una password SHA-1 valida l'utente nasce
--      senza password (W) e la imposta con "Password dimenticata";
--    - nessuna funzione: anche agli utenti standard le assegna l'amministratore del dominio, utente per utente.
-- 2) Sedi degli utenti standard (gli amministratori vedono gia' tutto): quelle della 3.1 gia' migrate e interne al
--    dominio 4.0. Si aggiungono a ogni esecuzione, man mano che le sedi vengono migrate.
CREATE OR ALTER PROCEDURE dbo.uspMigrazioni31_ins_Utenti
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

		DECLARE @idUtente31 CHAR(16);
		DECLARE @email VARCHAR(50);
		DECLARE @nomeCompleto VARCHAR(50);
		DECLARE @idRuolo CHAR(2);
		DECLARE @idStato CHAR(2);
		DECLARE @scadenza DATE;
		DECLARE @password NVARCHAR(1600);
		DECLARE @dataPassword DATETIME2(0);
		DECLARE @dataInserimento DATETIME2(0);
		DECLARE @idEsistente CHAR(16);
		DECLARE @id CHAR(16);
		DECLARE @nome VARCHAR(50);
		DECLARE @cognome VARCHAR(50);
		DECLARE @passwordValida BIT;

		-- 1) Utenti
		DECLARE cu CURSOR LOCAL FAST_FORWARD FOR
			SELECT
				u.IDUtente,
				LTRIM(RTRIM(u.Email)),
				NULLIF(LTRIM(RTRIM(u.Nome)), ''),
				u.IDTipo,
				u.IDStato,
				u.Scadenza,
				u.[Password],
				pc.[Data],
				x.DataInserimento
			FROM
				dbo.syn31Utenti u
				LEFT JOIN dbo.syn31ID x ON u.IDUtente = x.ID
				OUTER APPLY (
					SELECT [Data] = MAX(c.[Data])
					FROM dbo.syn31UtentiPasswordChange c
					WHERE c.IDUtente = u.IDUtente) pc
			WHERE
				u.IDDominio = @IdDominioDa
				AND ISNULL(u.Lock, 0) = 0
				AND ISNULL(u.[Master], 0) = 0
				AND NOT EXISTS (SELECT 1 FROM dbo.tblMigrazioniId mu WHERE mu.Versione = '31' AND mu.IdDominioA = @IdDominioA AND mu.Tabella = 'tblUtenti' AND mu.IdOrigine = u.IDUtente COLLATE DATABASE_DEFAULT)
			ORDER BY u.IDUtente;

		OPEN cu;
		FETCH cu INTO @idUtente31, @email, @nomeCompleto, @idRuolo, @idStato, @scadenza, @password, @dataPassword, @dataInserimento;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblUtentiRuoli
			WHERE Id = @idRuolo COLLATE DATABASE_DEFAULT)
				OR NOT EXISTS (SELECT 1
				FROM dbo.tblUtentiStati
				WHERE Id = @idStato COLLATE DATABASE_DEFAULT)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = CONCAT('Utente ', @email, ': ruolo o stato non presente nella 4.0');
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblUtenti
			WHERE
				Email = @email COLLATE DATABASE_DEFAULT
				AND Lock = 0
				AND IdDominio <> @IdDominioA
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = CONCAT('Utente ', @email, ': email gia'' usata da un utente di un altro dominio 4.0');
				GOTO BRANCH_END;
			END

			SET @idEsistente = (SELECT TOP 1 Id
			FROM dbo.tblUtenti
			WHERE
				Email = @email COLLATE DATABASE_DEFAULT
				AND Lock = 0
				AND IdDominio = @IdDominioA
			ORDER BY Id);

			IF @idEsistente IS NOT NULL
			BEGIN
				SET @id = @idEsistente;

				EXEC dbo.uspMigrazioniId_ins
					@Versione = '31',
					@IdDominioA = @IdDominioA,
					@Tabella = 'tblUtenti',
					@IdOrigine = @idUtente31,
					@IdMigrazione = @IdMigrazione,
					@Id = @id OUTPUT;

				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				VALUES ('Utenti', 'I', 'tblUtenti', @idUtente31, 0, CONCAT('Utente ', @email, ' abbinato all''utente 4.0 ', @id, ' con la stessa email: ruolo, password e funzioni della 4.0 restano invariati'));
			END
			ELSE
			BEGIN
				-- Nome e cognome: prima parola = nome, il resto = cognome
				SET @nome = CASE WHEN @nomeCompleto IS NULL THEN NULL WHEN CHARINDEX(' ', @nomeCompleto) = 0 THEN @nomeCompleto ELSE LEFT(@nomeCompleto, CHARINDEX(' ', @nomeCompleto) - 1) END;
				SET @cognome = CASE WHEN CHARINDEX(' ', ISNULL(@nomeCompleto, '')) = 0 THEN NULL ELSE NULLIF(LTRIM(SUBSTRING(@nomeCompleto, CHARINDEX(' ', @nomeCompleto) + 1, 50)), '') END;

				-- Password: hash SHA-1 di 40 caratteri esadecimali (Strings.IsLegacySha1Hash vuole le maiuscole)
				SET @password = UPPER(LTRIM(RTRIM(@password)));
				SET @passwordValida = IIF(LEN(@password) = 40 AND @password NOT LIKE '%[^0-9A-F]%', 1, 0);

				SET @id = NULL;

				EXEC dbo.uspMigrazioniId_ins
					@Versione = '31',
					@IdDominioA = @IdDominioA,
					@Tabella = 'tblUtenti',
					@IdOrigine = @idUtente31,
					@IdMigrazione = @IdMigrazione,
					@DataInserimento = @dataInserimento,
					@Id = @id OUTPUT;

				INSERT INTO dbo.tblUtenti
					(Id, IdDominio, IdRuolo, IdStato, Email, Scadenza, PasswordScadenzaGiorni, PasswordPrecedenti, PasswordLunghezzaMinima, [Master], Lock, Nome, Cognome)
				VALUES
					(@id, @IdDominioA, @idRuolo, @idStato, @email, @scadenza, 0, 0, 8, 0, 0, @nome, @cognome);

				INSERT INTO dbo.tblUtentiDefault (Id)
				VALUES (@id);

				IF @passwordValida = 1
					INSERT INTO dbo.tblUtentiPassword (Id, [Data], [Password], Temporanea)
					VALUES (@id, ISNULL(@dataPassword, ISNULL(@dataInserimento, CONVERT(DATETIME2(0), GETDATE()))), @password, 0);

				INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				VALUES ('Utenti', IIF(@passwordValida = 1, 'I', 'W'), 'tblUtenti', @idUtente31, 1,
					CONCAT('Creato l''', IIF(@idRuolo = 'AD', 'amministratore ', 'utente '), @email, ' (', @id, ')',
						IIF(@passwordValida = 1, ' con la password della 3.1', ' senza password: la imposta con "Password dimenticata"'),
						IIF(@idRuolo = 'AD', '', ': funzioni da assegnare')));
			END

			FETCH cu INTO @idUtente31, @email, @nomeCompleto, @idRuolo, @idStato, @scadenza, @password, @dataPassword, @dataInserimento;
		END

		CLOSE cu;
		DEALLOCATE cu;

		-- 2) Sedi degli utenti standard: sedi 3.1 gia' migrate, interne al dominio 4.0, non ancora assegnate
		INSERT INTO dbo.tblUtentiSediInterne (Id, IdSede)
		SELECT DISTINCT mu.IdDestinazione, s.Id
		FROM
			dbo.syn31UtentiSedi us
			INNER JOIN dbo.tblMigrazioniId mu ON mu.Versione = '31'
				AND mu.IdDominioA = @IdDominioA
				AND mu.Tabella = 'tblUtenti'
				AND mu.IdOrigine = us.IDUtente COLLATE DATABASE_DEFAULT
			INNER JOIN dbo.tblUtenti u ON mu.IdDestinazione = u.Id
			INNER JOIN dbo.tblMigrazioniId ms ON ms.Versione = '31'
				AND ms.IdDominioA = @IdDominioA
				AND ms.Tabella = 'tblSedi'
				AND ms.IdOrigine = us.IDSede COLLATE DATABASE_DEFAULT
			INNER JOIN dbo.tblSedi s ON ms.IdDestinazione = s.Id
			INNER JOIN dbo.tblSediInterne si ON s.IdAziendaInterna = si.Id
		WHERE
			u.IdRuolo = 'US'
			AND u.Lock = 0
			AND s.Lock = 0
			AND si.IdDominio = @IdDominioA
			AND NOT EXISTS (SELECT 1 FROM dbo.tblUtentiSediInterne x WHERE x.Id = mu.IdDestinazione AND x.IdSede = s.Id);

		DECLARE @righe INT = @@ROWCOUNT;

		INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
		VALUES ('Utenti', 'I', 'tblUtentiSediInterne', NULL, NULLIF(@righe, 0), CONCAT(@righe, ' sedi assegnate agli utenti standard'));

		-- Utenti standard migrati ancora senza sedi: vedranno le sedi quando saranno migrate
		INSERT INTO #log (Fase, Livello, Tabella, IdOrigine, Messaggio)
		SELECT 'Utenti', 'I', 'tblUtentiSediInterne', mu.IdOrigine, CONCAT('L''utente ', u.Email, ' non ha ancora sedi migrate')
		FROM
			dbo.tblMigrazioniId mu
			INNER JOIN dbo.tblUtenti u ON mu.IdDestinazione = u.Id
		WHERE
			mu.Versione = '31'
			AND mu.IdDominioA = @IdDominioA
			AND mu.Tabella = 'tblUtenti'
			AND u.IdRuolo = 'US'
			AND u.Lock = 0
			AND NOT EXISTS (SELECT 1 FROM dbo.tblUtentiSediInterne x WHERE x.Id = u.Id);
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
