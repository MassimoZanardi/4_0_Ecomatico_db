-- =====================================================================================
-- Deploy produzione 2026-09-04: Modulo Firma remota xFIR (building block)
-- Repo: 4_0_ecomatico
--
-- Contenuto:
--   1) ALTER TABLE tblUtenti (CodiceFiscale, Nome, Cognome)
--   2) CREATE TABLE tblRentriFirmeCredenziali
--   3) CREATE TABLE tblRentriFirmeOperazioni
--   4) CREATE OR ALTER uspUtenti_get / uspUtenti_upd (estese + fix QUOTED_IDENTIFIER)
--   5) CREATE OR ALTER uspRentriFirmeCredenziali_get / _upd_Boarding / _del
--   6) CREATE OR ALTER uspRentriFirmeOperazioni_ins
--   7) Dati: nuova Funzione 'RFX' + collegamento modulo + voce di menu
--
-- ATTENZIONE PRIMA DI ESEGUIRE:
--   - Il blocco 7 usa Id fissi ('RFX' in tblFunzioni/tblPagine con Id 'RFM', 'AG5' in
--     tblMenu) verificati liberi sul DB di sviluppo il 2026-09-04. Verificare che non
--     collidano con codici aggiunti in produzione nel frattempo:
--       SELECT Id FROM dbo.tblFunzioni WHERE Id = 'RFX';
--       SELECT Id FROM dbo.tblPagine WHERE Id = 'RFM';
--       SELECT Id FROM dbo.tblMenu WHERE Id = 'AG5';
--     Devono restituire 0 righe. Se una collide, cambiare l'Id nel blocco 7 (coerente
--     ovunque compare) prima di eseguire.
--   - Il deploy dell'hub (repo 1_0_RentriApi) è SEPARATO da questo script: senza quello
--     nessuna chiamata reale a RENTRI funzionerà, ma lo schema qui è comunque sicuro da
--     applicare in anticipo (additivo, nessuna colonna/tabella esistente rimossa).
--   - Eseguire con: sqlcmd -S <server> -d 4_0_ecomatico -E -f 65001 -b -i <questo file>
-- =====================================================================================


-- 1) ALTER TABLE tblUtenti -----------------------------------------------------------
ALTER TABLE dbo.tblUtenti ADD
	CodiceFiscale VARCHAR(20) NULL,
	Nome VARCHAR(50) NULL,
	Cognome VARCHAR(50) NULL;
GO


-- 2) CREATE TABLE tblRentriFirmeCredenziali -------------------------------------------
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriFirmeCredenziali](
	[IdUtente] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[CredentialsId] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[DeviceIdentifier] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[DataBoarding] [datetime2](0) NULL,
	[Lock] [tinyint] NULL
 CONSTRAINT [PK_tblRentriFirmeCredenziali] PRIMARY KEY CLUSTERED
(
	[IdUtente] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriFirmeCredenziali]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriFirmeCredenziali_tblUtenti] FOREIGN KEY([IdUtente])
REFERENCES [dbo].[tblUtenti] ([Id])
GO

ALTER TABLE [dbo].[tblRentriFirmeCredenziali] CHECK CONSTRAINT [FK_tblRentriFirmeCredenziali_tblUtenti]
GO


-- 3) CREATE TABLE tblRentriFirmeOperazioni --------------------------------------------
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriFirmeOperazioni](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdUtente] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[DataOra] [datetime2](0) NOT NULL,
	[Handle] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Esito] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[Note] [varchar](200) COLLATE Latin1_General_CI_AS NULL
 CONSTRAINT [PK_tblRentriFirmeOperazioni] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

CREATE NONCLUSTERED INDEX [IX_RentriFirmeOperazioni_IdUtente] ON [dbo].[tblRentriFirmeOperazioni]
(
	[IdUtente] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblRentriFirmeOperazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriFirmeOperazioni_tblUtenti] FOREIGN KEY([IdUtente])
REFERENCES [dbo].[tblUtenti] ([Id])
GO

ALTER TABLE [dbo].[tblRentriFirmeOperazioni] CHECK CONSTRAINT [FK_tblRentriFirmeOperazioni_tblUtenti]
GO


-- 4a) uspUtenti_get (estesa con CodiceFiscale/Nome/Cognome + fix header QUOTED_IDENTIFIER) --
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
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
		-- Risolve l'utente della sessione corrente
		DECLARE @idUtente CHAR(16);
		SELECT @idUtente = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;
		IF @idUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida o scaduta';
			GOTO BRANCH_END;
		END
		-- Controllo permessi: l'utente richiedente deve essere Admin
		-- Scenario 1: Admin dello stesso dominio dell'utente target
		-- Scenario 2: Admin di un dominio Master (visibilità globale)
		-- Se NESSUNO dei due è verificato → accesso negato
		IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblUtenti u
				INNER JOIN dbo.tblUtenti a
						   ON u.IdDominio = a.IdDominio
				WHERE
					u.Id = @Id
					AND a.Id = @idUtente
					AND a.IdRuolo = 'AD' -- AD = Amministratore
					AND a.Lock = 0
					AND u.[Master] = 0
		)
		AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblUtenti u
				INNER JOIN dbo.tblUtenti a
						   ON a.Id = @idUtente
				INNER JOIN dbo.tblDomini d
						   ON a.IdDominio = d.Id
				WHERE
					u.Id = @Id
					AND a.IdRuolo = 'AD' -- AD = Amministratore
					AND a.Lock = 0
					AND d.[Master] = 1 -- dominio Master: visibilità globale
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblUtenti
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Utente non trovato';
			GOTO BRANCH_END;
		END
		-- Dati utente: tabelle base invece di viewUtenti
		SELECT
			u.Id,
			u.IdDominio,
			u.IdRuolo,
			u.IdStato,
			u.Email,
			u.Scadenza,
			PasswordPrecedenti = ISNULL(u.PasswordPrecedenti, 0),
			PasswordScadenzaGiorni = ISNULL(u.PasswordScadenzaGiorni, 0),
			PasswordLunghezzaMinima = ISNULL(u.PasswordLunghezzaMinima, 8),
			u.CodiceFiscale,
			u.Nome,
			u.Cognome,
			u.Lock
		FROM
			dbo.tblUtenti u
		WHERE
			u.Id = @Id
			AND u.Lock <= 2;
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


-- 4b) uspUtenti_upd (estesa con CodiceFiscale/Nome/Cognome + fix header QUOTED_IDENTIFIER) --
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
	@PasswordLunghezzaMinima INT = NULL,
	@CodiceFiscale VARCHAR(20) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Cognome VARCHAR(50) = NULL
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
		SET @CodiceFiscale = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@CodiceFiscale, 0, 1));
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Cognome = dbo.ufnStringhe_get_SenzaSpazi(@Cognome, 0, 1);

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
				CodiceFiscale = @CodiceFiscale,
				Nome = @Nome,
				Cognome = @Cognome,
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
GO


-- 5a) uspRentriFirmeCredenziali_get ---------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFirmeCredenziali_get]
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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
			@IdFunzione = 'RFX',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16);
		SELECT @idUtente = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida';
			GOTO BRANCH_END;
		END

		SELECT
			u.Id AS IdUtente,
			u.CodiceFiscale,
			u.Nome,
			u.Cognome,
			c.CredentialsId,
			c.DataBoarding,
			Collegata = CASE WHEN c.IdUtente IS NOT NULL AND c.Lock = 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END
		FROM
			dbo.tblUtenti u
			LEFT JOIN dbo.tblRentriFirmeCredenziali c ON c.IdUtente = u.Id AND c.Lock = 0
		WHERE u.Id = @idUtente;

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


-- 5b) uspRentriFirmeCredenziali_upd_Boarding ------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFirmeCredenziali_upd_Boarding]
	@IdSessione CHAR(16) = NULL,
	@CredentialsId VARCHAR(50) = NULL,
	@DeviceIdentifier VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @CredentialsId = NULLIF(LTRIM(RTRIM(@CredentialsId)), '');
		SET @DeviceIdentifier = NULLIF(LTRIM(RTRIM(@DeviceIdentifier)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @CredentialsId IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @CredentialsId non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
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

		DECLARE @idUtente CHAR(16);
		SELECT @idUtente = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida';
			GOTO BRANCH_END;
		END

		-- L'utente deve avere Codice Fiscale e Nome/Cognome impostati: sono richiesti dal boarding RENTRI
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblUtenti
			WHERE
				Id = @idUtente
				AND CodiceFiscale IS NOT NULL
				AND Nome IS NOT NULL
				AND Cognome IS NOT NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Impostare Codice Fiscale, Nome e Cognome prima di collegare la credenziale di firma';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			IF EXISTS (SELECT 1 FROM dbo.tblRentriFirmeCredenziali WHERE IdUtente = @idUtente)
			BEGIN
				UPDATE dbo.tblRentriFirmeCredenziali
				SET
					CredentialsId = @CredentialsId,
					DeviceIdentifier = @DeviceIdentifier,
					DataBoarding = SYSDATETIME(),
					Lock = 0
				WHERE IdUtente = @idUtente;
			END
			ELSE
			BEGIN
				INSERT dbo.tblRentriFirmeCredenziali (IdUtente, CredentialsId, DeviceIdentifier, DataBoarding, Lock)
				VALUES (@idUtente, @CredentialsId, @DeviceIdentifier, SYSDATETIME(), 0);
			END
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


-- 5c) uspRentriFirmeCredenziali_del ----------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFirmeCredenziali_del]
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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
			@IdFunzione = 'RFX',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16);
		SELECT @idUtente = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida';
			GOTO BRANCH_END;
		END

		UPDATE dbo.tblRentriFirmeCredenziali
		SET
			Lock = 4,
			CredentialsId = NULL,
			DeviceIdentifier = NULL
		WHERE
			IdUtente = @idUtente
			AND Lock = 0;

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


-- 6) uspRentriFirmeOperazioni_ins ------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFirmeOperazioni_ins]
	@IdSessione CHAR(16) = NULL,
	@Handle VARCHAR(50) = NULL,
	@Esito VARCHAR(20) = NULL,
	@Note VARCHAR(200) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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
			@IdFunzione = 'RFX',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16);
		SELECT @idUtente = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblRentriFirmeOperazioni (Id, IdUtente, DataOra, Handle, Esito, Note)
			VALUES (@returnId, @idUtente, SYSDATETIME(), @Handle, @Esito, @Note);
		COMMIT TRANSACTION;

		SELECT Id = @returnId;

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


-- 7) Dati: Funzione 'RFX' + collegamento modulo REN + voce di menu -------------------
-- Verificare PRIMA di eseguire che 'RFX' / 'RFM' / 'AG5' siano liberi in produzione
-- (vedi nota in testa al file). Se una di queste INSERT fallisce per violazione di
-- chiave primaria, il blocco 1-6 sopra resta comunque applicato correttamente: va solo
-- scelto un nuovo Id libero per la riga in conflitto e rieseguito solo questo blocco.
BEGIN TRANSACTION;
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('RFX', 'Firma remota xFIR', 0, 0, 1);
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('REN', 'RFX');
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('RFM', 'RFX', 'Firma remota', 'firma-remota', NULL);
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AG5', 'AG0', NULL, 'RFM', 4);
COMMIT TRANSACTION;
GO
