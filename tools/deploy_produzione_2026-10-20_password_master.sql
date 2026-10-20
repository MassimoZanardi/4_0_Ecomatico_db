/*
Deploy produzione 2026-10-20 - Password degli utenti Master allineata a quella dell'amministratore del dominio Master

Indipendente dagli altri script. Rieseguibile. Eseguire con sqlcmd -f 65001 -I (oppure da SSMS) sul DB
4_0_ecomatico. Nessuna modifica all'app, all'hub e al DB 1_0_rentri.

1. uspUtenti_upd_PasswordMaster (nuova): se l'utente indicato è l'amministratore del dominio Master copia la sua
   password corrente, solo se definitiva (non temporanea), sulla password corrente di tutti gli utenti Master degli
   altri domini; lo storico delle password resta com'è. Va installata per prima: la chiamano le SP seguenti.
2. uspUtenti_upd: salvataggio della scheda utente; sostituisce il vecchio allineamento, che sovrascriveva tutto lo
   storico delle password degli utenti Master.
3. uspUtenti_upd_Password: cambio della password al login (password scaduta o temporanea); ora allinea gli utenti
   Master, aggiornamento in transazione.
4. uspUtenti_upd_ConfermaReset: reset della password dal link via email; ora allinea gli utenti Master.
5. uspUtenti_ins_Password: nuova password da Impostazioni > Utenti; ora allinea gli utenti Master (con una password
   temporanea non fa nulla, si allinea quella scelta al primo accesso).
   Regola D1.5 di docs/regole/domini-aziende-sedi.md (repo app).
*/

-- ===== 1. uspUtenti_upd_PasswordMaster
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_upd_PasswordMaster]
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Allinea la password degli utenti Master di tutti i domini a quella dell'amministratore
		-- del dominio Master (regola D1.5). Chiamata da ogni SP che cambia una password:
		-- se @Id non è l'amministratore del dominio Master non fa nulla
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblUtenti u
			INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
			WHERE
				u.Id = @Id
				AND u.IdRuolo = 'AD'
				AND u.Lock = 0
				AND d.[Master] = 1
		)
			GOTO BRANCH_END;

		-- Solo la password corrente (la più recente) e solo se definitiva: una password
		-- temporanea va cambiata al primo accesso e uspUtenti_upd_Login la cancella, quindi
		-- si propaga la password che l'amministratore sceglie al cambio
		DECLARE @password NVARCHAR(200);
		DECLARE @temporanea BIT;
		SELECT TOP 1
			@password = [Password],
			@temporanea = ISNULL(Temporanea, 0)
		FROM dbo.tblUtentiPassword
		WHERE Id = @Id
		ORDER BY [Data] DESC;

		IF @password IS NULL OR @temporanea = 1
			GOTO BRANCH_END;

		BEGIN TRANSACTION;

			-- Sostituisce la password corrente di ogni utente Master: lo storico resta com'è
			UPDATE up
			SET
				[Password] = @password,
				Temporanea = 0
			FROM dbo.tblUtentiPassword up
			INNER JOIN dbo.tblUtenti u ON up.Id = u.Id
			WHERE
				u.[Master] = 1
				AND u.Id <> @Id
				AND up.[Data] = ( SELECT MAX([Data]) FROM dbo.tblUtentiPassword WHERE Id = up.Id );

			-- Utenti Master ancora senza password
			INSERT INTO dbo.tblUtentiPassword (Id, [Password], [Data], Temporanea)
			SELECT u.Id, @password, GETDATE(), 0
			FROM dbo.tblUtenti u
			WHERE
				u.[Master] = 1
				AND u.Id <> @Id
				AND NOT EXISTS (SELECT 1 FROM dbo.tblUtentiPassword WHERE Id = u.Id);

		COMMIT TRANSACTION;

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

-- ===== 2. uspUtenti_upd
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

			-- Se @Id è l'amministratore del dominio Master, allinea la password degli utenti Master
			EXEC dbo.uspUtenti_upd_PasswordMaster @Id = @Id;

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
GO

-- ===== 3. uspUtenti_upd_Password
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_upd_Password]
	@Id CHAR(16) = NULL,
	@Password NVARCHAR(200) = NULL,
	@Temporanea BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		-- Validazione parametri
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Password = NULLIF(LTRIM(RTRIM(@Password)), '');
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Password IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Password non può essere vuoto';
			GOTO BRANCH_END;
		END
		BEGIN TRANSACTION;
			-- Aggiorna solo l'ultima password inserita per questo utente
			UPDATE TOP (1) dbo.tblUtentiPassword
			SET
				[Password] = @Password,
				[Data] = GETDATE(),
				Temporanea = @Temporanea
			WHERE
				Id = @Id
				AND [Data] = ( SELECT MAX([Data]) FROM dbo.tblUtentiPassword WHERE Id = @Id );
			-- Verifica che l'UPDATE abbia effettivamente modificato una riga
			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Nessuna password trovata per l''utente specificato';
				GOTO BRANCH_END;
			END
			-- Se @Id è l'amministratore del dominio Master, allinea la password degli utenti Master
			EXEC dbo.uspUtenti_upd_PasswordMaster @Id = @Id;
		COMMIT TRANSACTION;
		-- Restituisce LoginResponse per login immediato post-cambio password
		-- Tabelle base invece di viewUtenti: evita OUTER APPLY su tblUtentiPassword
		SELECT
			u.Id,
			u.IdDominio,
			u.IdRuolo,
			u.Email,
			CAST(@Temporanea AS BIT) AS PasswordScaduta
		FROM dbo.tblUtenti u
		WHERE
			u.Id = @Id
			AND u.Lock <= 2;
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

-- ===== 4. uspUtenti_upd_ConfermaReset
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_upd_ConfermaReset]
	@Token NVARCHAR(32) = NULL,
	@Password NVARCHAR(200) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		-- Validazione parametri
		SET @Token = NULLIF(LTRIM(RTRIM(@Token)), '');
		SET @Password = NULLIF(LTRIM(RTRIM(@Password)), '');
		IF @Token IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Token non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Password IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Password non può essere vuoto';
			GOTO BRANCH_END;
		END
		DECLARE @StatoAttivo NVARCHAR(10) = 'AT'; -- AT = Attivo (tblUtentiStati)
		-- Risolve l'utente dal token:
		-- deve essere valido, non scaduto, utente attivo e non scaduto
		DECLARE @IdUtente CHAR(16);
		SELECT @IdUtente = Id
		FROM dbo.tblUtenti
		WHERE
			TokenReset = @Token COLLATE Latin1_General_CI_AS
			AND TokenResetScade > GETDATE()
			AND IdStato = @StatoAttivo
			AND Lock = 0
			AND
				(
				Scadenza IS NULL
				OR Scadenza >= CAST(GETDATE() AS DATE)
				);
		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Token non valido o scaduto';
			GOTO BRANCH_END;
		END
		BEGIN TRANSACTION;
			-- Inserisce la nuova password nello storico (tabella 1:N)
			-- Temporanea = 0: reset confermato → non richiede cambio immediato
			INSERT INTO dbo.tblUtentiPassword (Id, [Password], [Data], Temporanea)
			VALUES (@IdUtente, @Password, GETDATE(), 0);
			-- Mantiene solo le ultime 5 password per utente
			DELETE dbo.tblUtentiPassword
			WHERE
				Id = @IdUtente
				AND [Data] NOT IN ( SELECT TOP 5 [Data] FROM dbo.tblUtentiPassword WHERE Id = @IdUtente ORDER BY [Data] DESC );
			-- Invalida il token: non può essere riutilizzato
			UPDATE dbo.tblUtenti
			SET
				TokenReset = NULL,
				TokenResetScade = NULL
			WHERE
				Id = @IdUtente
				AND Lock <= 2;
			-- Se l'utente è l'amministratore del dominio Master, allinea la password degli utenti Master
			EXEC dbo.uspUtenti_upd_PasswordMaster @Id = @IdUtente;
		COMMIT TRANSACTION;
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

-- ===== 5. uspUtenti_ins_Password
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_ins_Password]
	@Id CHAR(16) = NULL,
	@Email NVARCHAR(255) = NULL,
	@Password NVARCHAR(200) = NULL,
	@Temporanea BIT = 1,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione: almeno uno tra @Id e @Email deve essere valorizzato
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Email = NULLIF(LTRIM(RTRIM(@Email)), '');
		SET @Password = NULLIF(LTRIM(RTRIM(@Password)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL AND @Email IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Specificare @Id oppure @Email';
			GOTO BRANCH_END;
		END

		IF @Password IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Password non può essere vuoto';
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

		-- Risolve @IdUtente da @Id oppure da @Email (forgot password)
		DECLARE @IdUtente CHAR(16);

		IF @Id IS NOT NULL
			SET @IdUtente = @Id;
		ELSE
			SELECT @IdUtente = Id
			FROM dbo.tblUtenti
			WHERE Email = @Email COLLATE Latin1_General_CI_AS;

		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Utente non trovato';
			GOTO BRANCH_END;
		END

		DECLARE @idDominioSessione CHAR(16);
		SELECT @idDominioSessione = a.IdDominio
		FROM dbo.tblSessioni s INNER JOIN dbo.tblUtenti a ON a.Id = s.IdUtente
		WHERE s.Id = @IdSessione;

		-- Titolarità: Admin dello stesso Dominio dell'utente target, oppure Admin di un Dominio Master.
		-- Aggiunto perché @Id arriva da un campo hidden del form (Utenti/Edit): un valore hidden è
		-- testo semplice manipolabile lato client, quindi va sempre validato lato server.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblUtenti
		WHERE
			Id = @IdUtente
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

		-- Determina se è la prima password dell'utente
		-- 0 = aveva già password → C# SendEmailForPasswordChange
		-- 1 = prima password     → C# SendEmailForStart
		DECLARE @GiaEsiste BIT = CASE
			WHEN EXISTS (
				SELECT 1
				FROM dbo.tblUtentiPassword
				WHERE Id = @IdUtente)
			THEN 1 ELSE 0
		END;

		BEGIN TRANSACTION;

			-- Aggiunge la nuova password in cima allo storico
			INSERT INTO dbo.tblUtentiPassword (Id, [Password], [Data], Temporanea)
			VALUES (@IdUtente, @Password, GETDATE(), @Temporanea);

			-- Mantiene solo le ultime 5 password per utente:
			-- elimina tutte le righe oltre la quinta più recente
			DELETE dbo.tblUtentiPassword
			WHERE
				Id = @IdUtente
				AND [Data] NOT IN ( SELECT TOP 5 [Data] FROM dbo.tblUtentiPassword WHERE Id = @IdUtente ORDER BY [Data] DESC );

			-- Se l'utente è l'amministratore del dominio Master, allinea la password degli utenti
			-- Master (con una password temporanea non fa nulla: si propaga quella scelta al cambio)
			EXEC dbo.uspUtenti_upd_PasswordMaster @Id = @IdUtente;

		COMMIT TRANSACTION;

		SET @returnValue = CASE @GiaEsiste
			WHEN 1 THEN 0 -- aveva già password → SendEmailForPasswordChange
			WHEN 0 THEN 1 -- prima password     → SendEmailForStart
		END;

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
