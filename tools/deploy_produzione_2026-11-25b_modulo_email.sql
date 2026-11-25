/*
	Deploy produzione 2026-11-25b - Modulo Email (EML), prima parte

	Contiene i commit del repo DB 5819a6f, 65002b2 e ee633bb (dopo questo bundle il tag deployed-prod puo' andare su
	ee633bb: ab42dab, il bundle dei formulari, e' gia' in produzione). Solo 4_0_ecomatico. Da eseguire da SSMS sul
	database 4_0_ecomatico. Si puo' rieseguire: la parte 0 crea solo quello che manca, il resto e' CREATE OR ALTER.

	Compatibile con l'app oggi in produzione: uspDomini_get restituisce colonne in piu' e uspDomini_upd ha parametri
	nuovi facoltativi (NULL = lascia il valore). La voce di menu Impostazioni > Registro email compare solo per i domini
	con il modulo Email, che oggi nessuno ha. Ordine consigliato: questo bundle, poi SUBITO l'app 8f79752 (comprende
	anche be25e49, targhe e conducenti), poi la configurazione del server (docs/configurazione.md, "Server: operazione
	pianificata dell'invio email"): chiave EmailSettings__CodaChiave nel web.config del SOLO sito 40 e
	tools/email_operazione_pianificata.ps1 (repo dell'app) lanciato sul server come amministratore.

	0. Struttura (tools/email_modulo.sql): modulo EML, funzione EMR (solo amministratori), pagina EMR, menu AZ6 in
	   Impostazioni prima di Domini, colonne tblDomini.EmailGiornoMax ed EmailMeseMax, tabelle tblEmail (coda e
	   registro) e tblEmailConsumi (email contate per dominio e giorno).
	1. ufnEmail_get_Consumi: quote e consumi del giorno e del mese di un dominio.
	2. uspDomini_get, uspDomini_upd: massimi del giorno e del mese nella scheda del dominio (solo Master).
	3. uspEmail_ins, uspEmail_ins_Prova: messa in coda (avvisi e comunicazioni; email di prova).
	4. uspEmail_upd_Prendi, uspEmail_upd_Esito: giro dell'invio a lotti, quote, esito, rilascio delle email non inviate.
	5. uspEmail_get_List, uspEmail_get, uspEmail_get_Consumi: Impostazioni > Registro email e finestra Email usate
	   (con l'attesa della piu' vecchia per il banner dell'invio in ritardo).
	6. uspEmail_del_Scadute: il registro tiene le email chiuse 30 giorni, i consumi 13 mesi.

	Dopo il bundle nessun dominio invia email: per attivarle il Master, in Impostazioni > Domini, attiva il modulo
	Email e scrive i massimi del giorno e del mese. L'email di prova (Registro email > Azioni) parte anche senza massimi.

	In fondo la verifica: struttura e 11 oggetti con data di modifica, QUOTED_IDENTIFIER e il controllo del testo.
*/

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO-- ===== 0. Struttura (tools/email_modulo.sql)
-- Modulo Email (EML), prima parte (decisioni dell'utente del 2026-11-24, docs/regole/email.md nella 4.0):
-- - modulo EML "Email", attivabile per dominio da Impostazioni > Domini;
-- - funzione EMR "Registro email" (Admin = 1: solo gli amministratori, non si assegna agli utenti standard), pagina
--   e voce di menu Impostazioni > Registro email, prima di Domini;
-- - quote del dominio tblDomini.EmailGiornoMax ed EmailMeseMax (NULL o 0 = email non attive): niente quota annuale,
--   il mese e' quello di calendario e le email non usate non passano al mese dopo;
-- - tblEmail: coda e registro delle email (una riga = un messaggio a un indirizzo);
-- - tblEmailConsumi: email contate nella quota, per dominio e giorno (il mese e' la somma dei suoi giorni).
-- Le email di sistema (password, primo accesso) restano fuori: partono subito e contengono password o link personali,
-- quindi non si scrivono nella coda.
-- Da installare prima delle SP uspEmail_* e delle nuove uspDomini_get / _upd. Si puo' rilanciare.
-- Eseguito su dev il 2026-11-24. NON ancora eseguito in produzione.

SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuli WHERE Id = 'EML')
	INSERT INTO dbo.tblModuli (Id, Nome, Attivo) VALUES ('EML', 'Email', 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'EMR')
	INSERT INTO dbo.tblFunzioni (Id, Nome, [Master], [Admin], Attiva) VALUES ('EMR', 'Registro email', 0, 1, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'EML' AND IdFunzione = 'EMR')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('EML', 'EMR');

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'EMR')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note, IdModulo) VALUES ('EMR', 'EMR', 'Registro email', 'registro-email', NULL, NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AZ6')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AZ6', 'AZ0', NULL, 'EMR', 4);

-- Menu Impostazioni: Aziende, Aree, Utenti, Report layout, Registro email, Domini
UPDATE dbo.tblMenu SET Pos = 4 WHERE Id = 'AZ6' AND Pos <> 4;
UPDATE dbo.tblMenu SET Pos = 5 WHERE Id = 'AZ2' AND Pos <> 5;
GO

IF COL_LENGTH('dbo.tblDomini', 'EmailGiornoMax') IS NULL
	ALTER TABLE dbo.tblDomini ADD EmailGiornoMax INT NULL;
IF COL_LENGTH('dbo.tblDomini', 'EmailMeseMax') IS NULL
	ALTER TABLE dbo.tblDomini ADD EmailMeseMax INT NULL;
GO

IF OBJECT_ID('dbo.tblEmail', 'U') IS NULL
BEGIN
	CREATE TABLE [dbo].[tblEmail](
		[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
		[IdDominio] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
		-- S di servizio (email di prova, avvisi sulla quota: fuori quota), U avviso a un utente, C comunicazione al cliente
		[Tipo] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
		[IdUtente] [char](16) COLLATE Latin1_General_CI_AS NULL,
		[Indirizzo] [varchar](250) COLLATE Latin1_General_CI_AS NOT NULL,
		[Mittente] [nvarchar](100) COLLATE Latin1_General_CI_AS NULL,
		[RispondiA] [varchar](250) COLLATE Latin1_General_CI_AS NULL,
		[Oggetto] [nvarchar](250) COLLATE Latin1_General_CI_AS NOT NULL,
		[Contenuto] [nvarchar](max) COLLATE Latin1_General_CI_AS NOT NULL,
		-- D da inviare, P in invio, I inviata, E non inviata
		[IdStato] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
		[Tentativi] [tinyint] NOT NULL CONSTRAINT [DF_tblEmail_Tentativi] DEFAULT (0),
		[Creazione] [datetime2](0) NOT NULL CONSTRAINT [DF_tblEmail_Creazione] DEFAULT (GETDATE()),
		[ProssimoTentativo] [datetime2](0) NOT NULL CONSTRAINT [DF_tblEmail_ProssimoTentativo] DEFAULT (GETDATE()),
		[Presa] [datetime2](0) NULL,
		[Invio] [datetime2](0) NULL,
		-- Perche' aspetta (massimo del giorno o del mese raggiunto) o perche' non e' partita
		[Nota] [nvarchar](500) COLLATE Latin1_General_CI_AS NULL,
		-- Giorno in cui e' contata nella quota (tblEmailConsumi): NULL se non conta o se il posto e' stato restituito
		[QuotaGiorno] [date] NULL,
	 CONSTRAINT [PK_tblEmail] PRIMARY KEY CLUSTERED ([Id] ASC)
	) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];

	CREATE NONCLUSTERED INDEX [IX_tblEmail_Coda] ON [dbo].[tblEmail] ([IdStato], [ProssimoTentativo]) INCLUDE ([Tipo], [IdDominio], [Creazione]);
	CREATE NONCLUSTERED INDEX [IX_tblEmail_Dominio] ON [dbo].[tblEmail] ([IdDominio], [Creazione]);
	-- Tetto globale del giorno (EmailSettings:GiornoMax nel web.config): email prese oggi da tutti i domini
	CREATE NONCLUSTERED INDEX [IX_tblEmail_Presa] ON [dbo].[tblEmail] ([Presa]);
END
GO

IF OBJECT_ID('dbo.tblEmailConsumi', 'U') IS NULL
	CREATE TABLE [dbo].[tblEmailConsumi](
		[IdDominio] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
		[Giorno] [date] NOT NULL,
		[Numero] [int] NOT NULL,
	 CONSTRAINT [PK_tblEmailConsumi] PRIMARY KEY CLUSTERED ([IdDominio] ASC, [Giorno] ASC)
	) ON [PRIMARY];
GO

SELECT
	Modulo = (SELECT COUNT(*) FROM dbo.tblModuli WHERE Id = 'EML'),
	Menu = (SELECT COUNT(*) FROM dbo.tblMenu WHERE Id = 'AZ6'),
	EmailGiornoMax = COL_LENGTH('dbo.tblDomini', 'EmailGiornoMax'),
	EmailMeseMax = COL_LENGTH('dbo.tblDomini', 'EmailMeseMax'),
	tblEmail = OBJECT_ID('dbo.tblEmail', 'U'),
	tblEmailConsumi = OBJECT_ID('dbo.tblEmailConsumi', 'U');
GO


GO
-- ===== 1. ufnEmail_get_Consumi (sql/functions/ufnEmail_get_Consumi.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Modulo Email (EML): quote e consumi del dominio. GiornoMax e MeseMax da tblDomini (0 se vuoti: con uno dei due a 0
-- le email agli utenti e ai clienti non partono), Giorno e Mese = email contate oggi e nel mese di calendario in corso
-- (tblEmailConsumi; le email di servizio non contano). Le email non usate non passano al mese dopo.
CREATE OR ALTER FUNCTION [dbo].[ufnEmail_get_Consumi] (
	@IdDominio CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		GiornoMax = ISNULL(d.EmailGiornoMax, 0),
		MeseMax = ISNULL(d.EmailMeseMax, 0),
		Giorno = ISNULL((
			SELECT c.Numero
			FROM dbo.tblEmailConsumi c
			WHERE
				c.IdDominio = d.Id
				AND c.Giorno = CAST(GETDATE() AS DATE)), 0),
		Mese = ISNULL((
			SELECT SUM(c.Numero)
			FROM dbo.tblEmailConsumi c
			WHERE
				c.IdDominio = d.Id
				AND c.Giorno >= DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
				AND c.Giorno <= CAST(GETDATE() AS DATE)), 0)
	FROM dbo.tblDomini d
	WHERE d.Id = @IdDominio
);
GO


GO
-- ===== 2. uspDomini_get (sql/procedures/uspDomini_get.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDomini_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
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

		-- Controllo permesso: solo Admin di dominio Master
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSessioni e
			INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
			INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
			WHERE
				e.Id = @IdSessione
				AND d.[Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Dominio non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			Id,
			Nome = ISNULL(Nome, ''),
			Riferimento = ISNULL(Riferimento, ''),
			Registrazione,
			Scadenza,
			ScadenzaAuto,
			UtentiMax,
			AziendeMax,
			SediMax,
			RegistriMax,
			MagazziniMax,
			ServiziMax,
			RentriMax,
			ConservazioniMax = ISNULL(ConservazioniMax, 0),
			ConservazioniXfirMax = ISNULL(ConservazioniXfirMax, 0),
			-- Spazio per i file allegati: massimo in MB (in tabella in byte), consumato in byte
			FileQuotaMaxMb = CAST(ISNULL(FileQuotaMax, 0) / 1048576 AS INT),
			FileQuotaConsumata = ISNULL(FileQuotaConsumata, 0),
			-- Modulo Email: massimi del giorno e del mese, email contate oggi e nel mese (ufnEmail_get_Consumi)
			EmailGiornoMax = c.GiornoMax,
			EmailMeseMax = c.MeseMax,
			EmailGiorno = c.Giorno,
			EmailMese = c.Mese,
			Demo,
			Logo,
			Codice = LOWER(ISNULL(Codice, RIGHT(CONVERT(VARCHAR(36), NEWID()), 5))),
			[Url] = ISNULL([Url], ''),
			Lock
		FROM
			dbo.tblDomini d
			CROSS APPLY dbo.ufnEmail_get_Consumi(d.Id) c
		WHERE d.Id = @Id;

	END TRY
	BEGIN CATCH
		THROW;
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


GO
-- ===== 2. uspDomini_upd (sql/procedures/uspDomini_upd.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDomini_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdStato CHAR(2) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Riferimento VARCHAR(50) = NULL,
	@Scadenza DATE = NULL,
	@ScadenzaAuto BIT = 1,
	@UtentiMax INT = 1,
	@AziendeMax INT = 1,
	@SediMax INT = 1,
	@RegistriMax INT = 0,
	@MagazziniMax INT = 0,
	@ServiziMax INT = 0,
	@RentriMax INT = 0,
	@ConservazioniMax INT = 0,
	@ConservazioniXfirMax INT = 0,
	-- Spazio per i file allegati in MB (tblDomini.FileQuotaMax in byte); NULL lascia il valore attuale
	@FileQuotaMaxMb INT = NULL,
	-- Modulo Email: massimo di email al giorno e al mese di calendario (NULL lascia il valore attuale, 0 = email non attive)
	@EmailGiornoMax INT = NULL,
	@EmailMeseMax INT = NULL,
	@Demo BIT = 0,
	@Codice CHAR(5) = NULL,
	@NoLogo BIT = 0,
	@Url VARCHAR(200) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	DECLARE @returnValue INT = 0;
	DECLARE @returnMessage NVARCHAR(200) = NULL;
	DECLARE @primaAttivazione BIT = 0;
	DECLARE @returnIdUtente CHAR(16) = NULL;
	DECLARE @returnIdSede CHAR(16) = NULL;
	DECLARE @returnIdIndirizzo CHAR(16) = NULL;

	BEGIN TRY

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdStato = NULLIF(LTRIM(RTRIM(@IdStato)), '');

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
		IF @IdStato IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdStato non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSessioni e
			INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
			INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
			WHERE
				e.Id = @IdSessione
				AND d.[Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblDominiStati
		WHERE Id = @IdStato)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Stato dominio non valido';
			GOTO BRANCH_END;
		END

		-- Ridurlo sotto lo spazio già consumato è ammesso: i file restano, i nuovi caricamenti vengono rifiutati
		IF @FileQuotaMaxMb < 0 OR @FileQuotaMaxMb > 1048576
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lo spazio per i file allegati deve essere compreso tra 0 e 1.048.576 MB';
			GOTO BRANCH_END;
		END

		IF @EmailGiornoMax < 0 OR @EmailGiornoMax > 100000 OR @EmailMeseMax < 0 OR @EmailMeseMax > 1000000
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le email al giorno devono essere tra 0 e 100.000, quelle al mese tra 0 e 1.000.000';
			GOTO BRANCH_END;
		END
		IF @EmailGiornoMax > 0 AND @EmailMeseMax > 0 AND @EmailGiornoMax > @EmailMeseMax
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le email al giorno non possono superare quelle al mese';
			GOTO BRANCH_END;
		END

		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Riferimento = dbo.ufnStringhe_get_SenzaSpazi(@Riferimento, 0, 1);
		SET @Url = dbo.ufnStringhe_get_SenzaSpazi(@Url, 0, 1);
		SET @Codice = NULLIF(LTRIM(RTRIM(@Codice)), '');

		IF @Nome IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblDomini
			WHERE
				Id <> @Id
				AND Nome = @Nome
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non possono esistere 2 domini con lo stesso nome';
			GOTO BRANCH_END;
		END

		IF @Codice IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblDomini
			WHERE
				Id <> @Id
				AND Codice = @Codice
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non possono esistere 2 domini con lo stesso codice';
			GOTO BRANCH_END;
		END

		IF EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE
			Id = @Id
			AND Lock = 2
		)
			SET @primaAttivazione = 1;

		IF @primaAttivazione = 1
		BEGIN
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnIdUtente OUTPUT;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnIdSede OUTPUT;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnIdIndirizzo OUTPUT;
		END

		BEGIN TRANSACTION;

			IF @primaAttivazione = 1
			BEGIN
				INSERT INTO dbo.tblUtenti
					(Id, IdDominio, IdRuolo, IdStato, Email, Scadenza, [Master],
					 PasswordScadenzaGiorni, PasswordLunghezzaMinima,
					 PasswordPrecedenti, Lock)
				VALUES
					(@returnIdUtente, @Id, 'AD', 'AT',
					 RTRIM(@Id) + '@ecomatico.it',
					 '20501231',
					 1, 0, 8, 0, 0);

				-- Solo la password corrente dell'utente collegato: lo storico (fino a 5 righe)
				-- avrebbe la stessa Data e violerebbe la chiave (Id, Data)
				INSERT INTO dbo.tblUtentiPassword (Id, [Password], [Data])
				SELECT TOP 1 @returnIdUtente, p.[Password], GETDATE()
				FROM dbo.tblUtentiPassword p
				INNER JOIN dbo.tblSessioni e ON p.Id = e.IdUtente
				WHERE e.Id = @IdSessione
				ORDER BY p.[Data] DESC;

				INSERT INTO dbo.tblUtentiDefault (Id)
				VALUES (@returnIdUtente);

				INSERT INTO dbo.tblOsepe (Id, Tipo)
				VALUES (@returnIdSede, 'S');

				INSERT INTO dbo.tblSedi
					(Id, IdParent, IdAziendaInterna, InternaEsterna, IdTipo,
					 Disabilitata, Nome, CodiceFiscale, PartitaIva,
					 NomeCompleto, Lock)
				VALUES
					(@returnIdSede, NULL, @returnIdSede, 'I', 'L',
					 0, '(Da indicare)', '00000000000', '00000000000',
					 '(Da indicare)', 0);

				INSERT INTO dbo.tblSediInterne (Id, IdDominio)
				VALUES (@returnIdSede, @Id);

				INSERT INTO dbo.tblIndirizzi
					(Id, Indirizzo, CAP, Localita, IdComune, IdNazione)
				VALUES
					(@returnIdIndirizzo,
					 '(Indicare la via e numero civico)',
					 '20100', NULL, '015146', '380');

				INSERT INTO dbo.tblSediIndirizzi (Id, IdIndirizzo)
				VALUES (@returnIdSede, @returnIdIndirizzo);

				INSERT INTO dbo.tblDominiModuli (Id, IdModulo)
				SELECT @Id, Id
				FROM dbo.tblModuli
				WHERE
					Id IN ('BAS', 'IMP')
					-- già aggiunti alla bozza dalla pagina (anche come dipendenza di un altro modulo)
					AND Id NOT IN ( SELECT IdModulo FROM dbo.tblDominiModuli WHERE Id = @Id );
			END

			DELETE f
			FROM dbo.tblUtentiFunzioni f
			INNER JOIN dbo.tblUtenti u ON f.Id = u.Id
			WHERE
				u.IdDominio = @Id
				AND f.IdFunzione NOT IN ( SELECT mf.IdFunzione FROM dbo.tblModuliFunzioni mf INNER JOIN dbo.tblDominiModuli dm ON mf.Id = dm.IdModulo WHERE dm.Id = @Id );

			UPDATE dbo.tblDomini
			SET
				Lock = 0,
				IdStato = @IdStato,
				Nome = ISNULL(@Nome, Nome),
				Riferimento = ISNULL(@Riferimento, Riferimento),
				Scadenza = ISNULL(@Scadenza, Scadenza),
				ScadenzaAuto = @ScadenzaAuto,
				UtentiMax = @UtentiMax,
				AziendeMax = @AziendeMax,
				SediMax = @SediMax,
				RegistriMax = @RegistriMax,
				MagazziniMax = @MagazziniMax,
				ServiziMax = @ServiziMax,
				RentriMax = @RentriMax,
				ConservazioniMax = @ConservazioniMax,
				ConservazioniXfirMax = @ConservazioniXfirMax,
				FileQuotaMax = IIF(@FileQuotaMaxMb IS NULL, FileQuotaMax, CAST(@FileQuotaMaxMb AS BIGINT) * 1048576),
				EmailGiornoMax = ISNULL(@EmailGiornoMax, EmailGiornoMax),
				EmailMeseMax = ISNULL(@EmailMeseMax, EmailMeseMax),
				Demo = @Demo,
				Codice = ISNULL(@Codice, Codice),
				Logo = IIF(@NoLogo = 1, NULL, Logo),
				[Url] = ISNULL(@Url, [Url])
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Dominio non trovato o già eliminato';
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
-- ===== 3. uspEmail_ins (sql/procedures/uspEmail_ins.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Modulo Email (EML): mette in coda un'email (tblEmail, stato D). Una riga = un messaggio a un indirizzo. Non controlla
-- permessi: la chiamano le SP che preparano le email (avvisi, comunicazioni al cliente, email di prova, avvisi sulla
-- quota), che hanno gia' fatto i loro controlli. L'invio e la quota li gestisce uspEmail_upd_Prendi.
-- @Tipo: S di servizio (fuori quota), U avviso a un utente, C comunicazione al cliente.
-- L'Id non passa da tblId (nessuna sessione: la coda si riempie anche dall'operazione pianificata); la chiave
-- primaria esclude comunque i doppioni.
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_ins]
	@IdDominio CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@IdUtente CHAR(16) = NULL,
	@Indirizzo VARCHAR(250) = NULL,
	@Mittente NVARCHAR(100) = NULL,
	@RispondiA VARCHAR(250) = NULL,
	@Oggetto NVARCHAR(250) = NULL,
	@Contenuto NVARCHAR(MAX) = NULL,
	@Id CHAR(16) = NULL OUTPUT
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdDominio = NULLIF(LTRIM(RTRIM(@IdDominio)), '');
		SET @Tipo = NULLIF(LTRIM(RTRIM(@Tipo)), '');
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		SET @Indirizzo = NULLIF(LOWER(LTRIM(RTRIM(@Indirizzo))), '');
		SET @Mittente = NULLIF(LTRIM(RTRIM(@Mittente)), '');
		SET @RispondiA = NULLIF(LOWER(LTRIM(RTRIM(@RispondiA))), '');
		SET @Oggetto = NULLIF(LTRIM(RTRIM(@Oggetto)), '');
		SET @Id = NULL;

		IF @IdDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdDominio non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('S', 'U', 'C')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere S, U o C';
			GOTO BRANCH_END;
		END
		-- Un solo indirizzo, con la forma minima nome@dominio.estensione: il servizio di invio fa il controllo completo
		IF @Indirizzo IS NULL OR @Indirizzo LIKE '%[ ;,]%' OR @Indirizzo NOT LIKE '_%@_%._%'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indirizzo email non valido';
			GOTO BRANCH_END;
		END
		IF @Oggetto IS NULL OR NULLIF(LTRIM(RTRIM(@Contenuto)), '') IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Oggetto e contenuto dell''email non possono essere vuoti';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblDomini WHERE Id = @IdDominio)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Dominio non trovato';
			GOTO BRANCH_END;
		END

		SET @Id = LOWER(LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 16));

		INSERT INTO dbo.tblEmail
			(Id, IdDominio, Tipo, IdUtente, Indirizzo, Mittente, RispondiA, Oggetto, Contenuto, IdStato)
		VALUES
			(@Id, @IdDominio, @Tipo, @IdUtente, @Indirizzo, @Mittente, @RispondiA, @Oggetto, @Contenuto, 'D');

	END TRY
	BEGIN CATCH
		THROW;
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


GO
-- ===== 3. uspEmail_ins_Prova (sql/procedures/uspEmail_ins_Prova.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Impostazioni > Registro email, Azioni > Invia email di prova (funzione EMR, solo amministratori): mette in coda
-- un'email di servizio all'indirizzo dell'utente collegato, per controllare che l'invio funzioni. Non conta nella quota
-- e parte al giro successivo dell'invio (entro 5 minuti). Una sola email di prova ancora da inviare per utente.
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_ins_Prova]
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EMR',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16), @idDominio CHAR(16), @indirizzo VARCHAR(250);
		SELECT
			@idUtente = u.Id,
			@idDominio = u.IdDominio,
			@indirizzo = u.Email
		FROM
			dbo.tblSessioni s
			INNER JOIN dbo.tblUtenti u ON s.IdUtente = u.Id
		WHERE s.Id = @IdSessione;

		IF EXISTS (
			SELECT 1
			FROM dbo.tblEmail
			WHERE
				IdUtente = @idUtente
				AND Tipo = 'S'
				AND IdStato IN ('D', 'P'))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'C''è già un''email di prova da inviare: parte entro 5 minuti';
			GOTO BRANCH_END;
		END

		DECLARE @contenuto NVARCHAR(MAX) = N'Gentile utente,<br /><br />'
			+ N'questa è un''email di prova richiesta il ' + FORMAT(GETDATE(), 'dd/MM/yyyy HH:mm') + N' da Impostazioni &gt; Registro email.<br />'
			+ N'Se la ricevi, l''invio delle email funziona.';

		DECLARE @id CHAR(16);
		EXEC dbo.uspEmail_ins
			@IdDominio = @idDominio,
			@Tipo = 'S',
			@IdUtente = @idUtente,
			@Indirizzo = @indirizzo,
			@Oggetto = N'Email di prova',
			@Contenuto = @contenuto,
			@Id = @id OUTPUT;

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
		THROW 50001, @returnMessage, 1
	END

END;
GO


GO
-- ===== 4. uspEmail_upd_Prendi (sql/procedures/uspEmail_upd_Prendi.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Modulo Email (EML): un lotto del giro dell'invio (operazione pianificata ogni 5 minuti, POST /api/email/elabora: il
-- giro prende lotti finche' la coda e' vuota o finisce il suo tempo). Prende fino a @Max email da inviare (stato D,
-- ProssimoTentativo passato), le segna in invio (P) e le restituisce; l'app le invia e scrive l'esito con
-- uspEmail_upd_Esito (anche per quelle che rimette in coda senza inviarle, @Rilascia = 1). Il blocco sp_getapplock fa
-- prendere un lotto alla volta: due chiamate sovrapposte non prendono mai la stessa email e non superano la quota.
-- Ordine: prima le email di servizio, poi gli avvisi agli utenti, poi le comunicazioni ai clienti, dalla piu' vecchia.
-- Avvisi e comunicazioni (Tipo U e C):
-- - senza il modulo Email sul dominio, o con il massimo del giorno o del mese vuoto o 0, non partono (stato E);
-- - con il massimo del mese raggiunto aspettano il primo del mese dopo, con quello del giorno il giorno dopo (restano
--   D con la Nota che lo spiega); le email non usate non passano al mese dopo;
-- - prese, contano nella quota del giorno (tblEmailConsumi, QuotaGiorno): se poi non partono il posto torna libero.
-- Le email di servizio (Tipo S: email di prova, avvisi sulla quota) non contano e non chiedono il modulo.
-- @GiornoMaxGlobale (EmailSettings:GiornoMax nel web.config, NULL o 0 = nessuno): tetto di sicurezza sulle email prese
-- oggi da tutti i domini, anche di servizio; raggiunto, il giro si ferma e le email aspettano.
-- Prima del lotto, le email in invio da oltre 15 minuti (app fermata a meta': un giro dura al massimo 4 minuti)
-- passano a E: non e' noto se siano partite e rimandarle potrebbe farle arrivare due volte.
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_upd_Prendi]
	@Max INT = 50,
	@GiornoMaxGlobale INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		IF @Max IS NULL OR @Max < 1
			SET @Max = 1;
		IF @Max > 200
			SET @Max = 200;

		DECLARE @ora DATETIME2(0) = GETDATE();
		DECLARE @oggi DATE = CAST(@ora AS DATE);
		DECLARE @inizioMese DATE = DATEFROMPARTS(YEAR(@oggi), MONTH(@oggi), 1);
		DECLARE @domani DATETIME2(0) = DATEADD(DAY, 1, CAST(@oggi AS DATETIME2(0)));
		DECLARE @meseDopo DATETIME2(0) = DATEADD(MONTH, 1, CAST(@inizioMese AS DATETIME2(0)));

		DECLARE @prese TABLE (Id CHAR(16) COLLATE Latin1_General_CI_AS PRIMARY KEY, Ordine INT);
		DECLARE @n INT = 0;

		BEGIN TRANSACTION;

			DECLARE @blocco INT;
			EXEC @blocco = sp_getapplock @Resource = 'tblEmail_Prendi', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 30000;

			IF @blocco >= 0
			BEGIN
				UPDATE dbo.tblEmail
				SET
					IdStato = 'E',
					Nota = N'Invio interrotto: non è noto se l''email sia partita, quindi non viene rimandata'
				WHERE
					IdStato = 'P'
					AND Presa < DATEADD(MINUTE, -15, @ora);

				DECLARE @globali INT = (SELECT COUNT(*) FROM dbo.tblEmail WHERE Presa >= @oggi);

				DECLARE @id CHAR(16), @idDominio CHAR(16), @tipo CHAR(1);
				DECLARE @giornoMax INT, @meseMax INT, @giorno INT, @mese INT, @modulo BIT;

				DECLARE coda CURSOR LOCAL FAST_FORWARD FOR
					SELECT TOP (500) Id, IdDominio, Tipo
					FROM dbo.tblEmail
					WHERE
						IdStato = 'D'
						AND ProssimoTentativo <= @ora
					ORDER BY
						CASE Tipo WHEN 'S' THEN 0 WHEN 'U' THEN 1 ELSE 2 END,
						Creazione,
						Id;

				OPEN coda;
				FETCH NEXT FROM coda INTO @id, @idDominio, @tipo;

				WHILE @@FETCH_STATUS = 0 AND @n < @Max
					AND (ISNULL(@GiornoMaxGlobale, 0) <= 0 OR @globali < @GiornoMaxGlobale)
				BEGIN
					IF @tipo = 'S'
					BEGIN
						UPDATE dbo.tblEmail
						SET IdStato = 'P', Presa = @ora, Nota = NULL
						WHERE Id = @id AND IdStato = 'D';

						INSERT INTO @prese (Id, Ordine) VALUES (@id, @n);
						SET @n += 1;
						SET @globali += 1;
					END
					ELSE
					BEGIN
						SET @modulo = IIF(EXISTS (SELECT 1 FROM dbo.tblDominiModuli WHERE Id = @idDominio AND IdModulo = 'EML'), 1, 0);
						SELECT @giornoMax = GiornoMax, @meseMax = MeseMax, @giorno = Giorno, @mese = Mese
						FROM dbo.ufnEmail_get_Consumi(@idDominio);

						IF @modulo = 0
							UPDATE dbo.tblEmail
							SET IdStato = 'E', Nota = N'Il modulo Email non è attivo'
							WHERE Id = @id;
						ELSE IF ISNULL(@giornoMax, 0) <= 0 OR ISNULL(@meseMax, 0) <= 0
							UPDATE dbo.tblEmail
							SET IdStato = 'E', Nota = N'Le email non sono attive: manca il numero massimo del giorno o del mese'
							WHERE Id = @id;
						ELSE IF @mese >= @meseMax
							UPDATE dbo.tblEmail
							SET ProssimoTentativo = @meseDopo, Nota = N'In attesa: raggiunto il numero massimo di email del mese'
							WHERE Id = @id;
						ELSE IF @giorno >= @giornoMax
							UPDATE dbo.tblEmail
							SET ProssimoTentativo = @domani, Nota = N'In attesa: raggiunto il numero massimo di email del giorno'
							WHERE Id = @id;
						ELSE
						BEGIN
							UPDATE dbo.tblEmailConsumi
							SET Numero += 1
							WHERE IdDominio = @idDominio AND Giorno = @oggi;
							IF @@ROWCOUNT = 0
								INSERT INTO dbo.tblEmailConsumi (IdDominio, Giorno, Numero) VALUES (@idDominio, @oggi, 1);

							UPDATE dbo.tblEmail
							SET IdStato = 'P', Presa = @ora, Nota = NULL, QuotaGiorno = @oggi
							WHERE Id = @id AND IdStato = 'D';

							INSERT INTO @prese (Id, Ordine) VALUES (@id, @n);
							SET @n += 1;
							SET @globali += 1;
						END
					END

					FETCH NEXT FROM coda INTO @id, @idDominio, @tipo;
				END

				CLOSE coda;
				DEALLOCATE coda;
			END

		COMMIT TRANSACTION;

		SELECT
			e.Id,
			e.Indirizzo,
			e.Mittente,
			e.RispondiA,
			e.Oggetto,
			e.Contenuto
		FROM
			dbo.tblEmail e
			INNER JOIN @prese p ON e.Id = p.Id
		ORDER BY p.Ordine;

	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION;
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO


GO
-- ===== 4. uspEmail_upd_Esito (sql/procedures/uspEmail_upd_Esito.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Modulo Email (EML): esito dell'invio di un'email presa da uspEmail_upd_Prendi (stato P).
-- @Inviata = 1: inviata (I).
-- @Inviata = 0: il posto nella quota torna libero (tblEmailConsumi del giorno in cui e' stata contata); con @Riprova = 1
-- (servizio di invio non raggiungibile, troppe richieste, errore interno) torna da inviare (D) e si riprova dopo 5, 10,
-- 20 e 40 minuti; al quinto tentativo, o con @Riprova = 0 (indirizzo rifiutato), non inviata (E). @Errore va nella Nota.
-- @Rilascia = 1 (il giro si e' fermato prima di inviarla: tempo finito o servizio di invio non disponibile): torna da
-- inviare (D) per il giro successivo, senza contare un tentativo e liberando il posto nella quota; ProssimoTentativo
-- resta quello di prima (gia' passato), cosi' l'attesa in Email usate (uspEmail_get_Consumi) continua a crescere.
-- Un'email che non e' piu' in invio (gia' chiusa da un altro giro) resta com'e'.
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_upd_Esito]
	@Id CHAR(16) = NULL,
	@Inviata BIT = 0,
	@Riprova BIT = 0,
	@Rilascia BIT = 0,
	@Errore NVARCHAR(500) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Errore = NULLIF(LTRIM(RTRIM(@Errore)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			IF @Inviata = 1
			BEGIN
				UPDATE dbo.tblEmail
				SET
					IdStato = 'I',
					Invio = GETDATE(),
					Tentativi = Tentativi + 1,
					Nota = NULL
				WHERE
					Id = @Id
					AND IdStato = 'P';
			END
			ELSE
			BEGIN
				UPDATE c
				SET Numero = c.Numero - 1
				FROM
					dbo.tblEmailConsumi c
					INNER JOIN dbo.tblEmail e ON c.IdDominio = e.IdDominio
											  AND c.Giorno = e.QuotaGiorno
				WHERE
					e.Id = @Id
					AND e.IdStato = 'P'
					AND c.Numero > 0;

				IF @Rilascia = 1
					UPDATE dbo.tblEmail
					SET
						IdStato = 'D',
						Presa = NULL,
						QuotaGiorno = NULL,
						Nota = N'In attesa: rimandata al giro successivo'
					WHERE
						Id = @Id
						AND IdStato = 'P';
				ELSE
					UPDATE dbo.tblEmail
					SET
						IdStato = IIF(@Riprova = 1 AND Tentativi + 1 < 5, 'D', 'E'),
						ProssimoTentativo = DATEADD(MINUTE, 5 * POWER(2, Tentativi), GETDATE()),
						Tentativi = Tentativi + 1,
						QuotaGiorno = NULL,
						Nota = ISNULL(@Errore, N'Invio non riuscito')
					WHERE
						Id = @Id
						AND IdStato = 'P';
			END

		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION;
		THROW;
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


GO
-- ===== 5. uspEmail_get_List (sql/procedures/uspEmail_get_List.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Impostazioni > Registro email (modulo EML, funzione EMR, solo amministratori): le email del dominio della sessione,
-- dalla piu' recente, a pagine. Ricerca per indirizzo o oggetto (@Search), stato (@Stato: D da inviare, comprese
-- quelle in invio; I inviate; E non inviate; vuoto tutte) e data di creazione (@DallaData, @AllaData).
-- StatoValore come _StatoPartial: 0 inviata (verde), 1 da inviare o in invio (arancione), 2 non inviata (rosso).
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Stato CHAR(1) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');
		SET @PageNumber = IIF(ISNULL(@PageNumber, 0) < 1, 1, @PageNumber);
		SET @RowsPerPage = IIF(ISNULL(@RowsPerPage, 0) < 1, 50, @RowsPerPage);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EMR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idDominio CHAR(16) = (
			SELECT u.IdDominio
			FROM
				dbo.tblSessioni s
				INNER JOIN dbo.tblUtenti u ON s.IdUtente = u.Id
			WHERE s.Id = @IdSessione);

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		SELECT
			e.Id,
			e.Creazione,
			e.Invio,
			e.Tipo,
			TipoNome = CASE e.Tipo WHEN 'S' THEN 'Di servizio' WHEN 'U' THEN 'Avviso' ELSE 'Al cliente' END,
			e.Indirizzo,
			e.Oggetto,
			e.IdStato,
			StatoValore = CASE e.IdStato WHEN 'I' THEN 0 WHEN 'E' THEN 2 ELSE 1 END,
			StatoDescrizione = CASE e.IdStato WHEN 'I' THEN 'Inviata' WHEN 'E' THEN 'Non inviata' WHEN 'P' THEN 'In invio' ELSE 'Da inviare' END,
			e.Tentativi,
			e.ProssimoTentativo,
			e.Nota,
			RowsCount = COUNT(*) OVER ()
		FROM dbo.tblEmail e
		WHERE
			e.IdDominio = @idDominio
			AND (@Search IS NULL OR e.Indirizzo LIKE '%' + @Search + '%' OR e.Oggetto LIKE '%' + @Search + '%')
			AND (@Stato IS NULL OR e.IdStato = @Stato OR (@Stato = 'D' AND e.IdStato = 'P'))
			AND (@DallaData IS NULL OR e.Creazione >= @DallaData)
			AND (@AllaData IS NULL OR e.Creazione < DATEADD(DAY, 1, CAST(@AllaData AS DATETIME2(0))))
		ORDER BY e.Creazione DESC, e.Id DESC
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY;

	END TRY
	BEGIN CATCH
		THROW;
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


GO
-- ===== 5. uspEmail_get (sql/procedures/uspEmail_get.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Impostazioni > Registro email: un'email del dominio della sessione con il testo, per la finestra che la mostra
-- (funzione EMR, solo amministratori).
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EMR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			e.Id,
			e.Creazione,
			e.Invio,
			e.Indirizzo,
			e.Mittente,
			e.RispondiA,
			e.Oggetto,
			e.Contenuto
		FROM
			dbo.tblEmail e
			INNER JOIN dbo.tblUtenti u ON e.IdDominio = u.IdDominio
			INNER JOIN dbo.tblSessioni s ON s.IdUtente = u.Id
		WHERE
			e.Id = @Id
			AND s.Id = @IdSessione;

	END TRY
	BEGIN CATCH
		THROW;
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


GO
-- ===== 5. uspEmail_get_Consumi (sql/procedures/uspEmail_get_Consumi.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Impostazioni > Registro email: quote e consumi del dominio della sessione (ufnEmail_get_Consumi), email da inviare e
-- attesa della piu' vecchia, per la finestra Azioni > Email usate. Funzione EMR, solo amministratori.
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_get_Consumi]
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EMR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			c.GiornoMax,
			c.MeseMax,
			c.Giorno,
			c.Mese,
			-- Email ancora da inviare del dominio, comprese quelle in attesa del giorno o del mese dopo
			DaInviare = (
				SELECT COUNT(*)
				FROM dbo.tblEmail e
				WHERE
					e.IdDominio = u.IdDominio
					AND e.IdStato IN ('D', 'P')),
			-- Minuti da cui aspetta l'email pronta per l'invio piu' vecchia (NULL se nessuna): le email in attesa del
			-- giorno o del mese dopo, o del prossimo tentativo, non sono pronte e non contano. Oltre 30 minuti l'invio e'
			-- in ritardo (operazione pianificata ferma o servizio di invio non disponibile)
			AttesaMinuti = (
				SELECT DATEDIFF(MINUTE, MIN(e.ProssimoTentativo), GETDATE())
				FROM dbo.tblEmail e
				WHERE
					e.IdDominio = u.IdDominio
					AND e.IdStato = 'D'
					AND e.ProssimoTentativo <= GETDATE())
		FROM
			dbo.tblSessioni s
			INNER JOIN dbo.tblUtenti u ON s.IdUtente = u.Id
			CROSS APPLY dbo.ufnEmail_get_Consumi(u.IdDominio) c
		WHERE s.Id = @IdSessione;

	END TRY
	BEGIN CATCH
		THROW;
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


GO
-- ===== 6. uspEmail_del_Scadute (sql/procedures/uspEmail_del_Scadute.sql)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Modulo Email (EML, docs/regole/email.md E3.8): pulizia del registro, chiamata alla fine di ogni giro dell'invio.
-- Cancella definitivamente le email chiuse (inviate I o non inviate E) da oltre @Giorni giorni (decisione dell'utente
-- del 2026-11-25: il registro serve solo per le verifiche recenti, e le email contengono dati personali). I giorni si
-- contano dall'invio, o dalla creazione per quelle non inviate. Le email ancora da inviare o in invio non si cancellano
-- mai (un'email in attesa del massimo del mese puo' aspettare un mese intero). Al massimo @Max email per volta, cosi'
-- una cancellazione grande non blocca la tabella: il resto lo fanno i giri successivi.
-- Toglie anche i consumi (tblEmailConsumi) di oltre 13 mesi prima: per le quote serve solo il mese in corso.
-- Restituisce il numero di email cancellate.
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_del_Scadute]
	@Giorni INT = 30,
	@Max INT = 500
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		IF @Giorni IS NULL OR @Giorni < 1
			SET @Giorni = 30;
		IF @Max IS NULL OR @Max < 1
			SET @Max = 500;

		DECLARE @limite DATETIME2(0) = DATEADD(DAY, -@Giorni, CAST(GETDATE() AS DATETIME2(0)));
		DECLARE @limiteConsumi DATE = DATEADD(MONTH, -13, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
		DECLARE @cancellate INT;

		-- Creazione < @limite (colonna inclusa in IX_tblEmail_Coda) riduce le righe da leggere a quelle vecchie;
		-- Invio decide per quelle inviate
		DELETE TOP (@Max)
		FROM dbo.tblEmail
		WHERE
			IdStato IN ('I', 'E')
			AND Creazione < @limite
			AND ISNULL(Invio, Creazione) < @limite;

		SET @cancellate = @@ROWCOUNT;

		DELETE FROM dbo.tblEmailConsumi
		WHERE Giorno < @limiteConsumi;

		SELECT @cancellate AS Cancellate;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO


GO
-- ===== Verifica: deve essere tutto "ok"
SELECT
	Modulo = IIF(EXISTS (SELECT 1 FROM dbo.tblModuli WHERE Id = 'EML'), 'ok', 'DA CONTROLLARE'),
	Funzione = IIF(EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'EML' AND IdFunzione = 'EMR'), 'ok', 'DA CONTROLLARE'),
	Menu = IIF(EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AZ6' AND IdPagina = 'EMR'), 'ok', 'DA CONTROLLARE'),
	Quote = IIF(COL_LENGTH('dbo.tblDomini', 'EmailGiornoMax') IS NOT NULL AND COL_LENGTH('dbo.tblDomini', 'EmailMeseMax') IS NOT NULL, 'ok', 'DA CONTROLLARE'),
	tblEmail = IIF(OBJECT_ID('dbo.tblEmail', 'U') IS NOT NULL, 'ok', 'DA CONTROLLARE'),
	tblEmailConsumi = IIF(OBJECT_ID('dbo.tblEmailConsumi', 'U') IS NOT NULL, 'ok', 'DA CONTROLLARE');

SELECT
	Oggetto = x.Nome,
	Modificato = o.modify_date,
	QuotedIdentifier = IIF(OBJECTPROPERTY(o.object_id, 'ExecIsQuotedIdentOn') = 1, 'ok', 'DA CONTROLLARE'),
	Modifica = IIF(CHARINDEX(x.Testo, m.definition) > 0, 'ok', 'DA CONTROLLARE')
FROM
	(VALUES
		('ufnEmail_get_Consumi', N'MeseMax = ISNULL(d.EmailMeseMax, 0)'),
		('uspDomini_get', N'EmailGiornoMax = c.GiornoMax'),
		('uspDomini_upd', N'@EmailGiornoMax INT = NULL'),
		('uspEmail_ins', N'@Tipo NOT IN (''S'', ''U'', ''C'')'),
		('uspEmail_ins_Prova', N'@Oggetto = N''Email di prova'''),
		('uspEmail_upd_Prendi', N'sp_getapplock'),
		('uspEmail_upd_Esito', N'@Rilascia BIT = 0'),
		('uspEmail_get_List', N'RowsCount = COUNT(*) OVER ()'),
		('uspEmail_get', N'e.Contenuto'),
		('uspEmail_get_Consumi', N'AttesaMinuti = ('),
		('uspEmail_del_Scadute', N'DATEADD(MONTH, -13')
	) x (Nome, Testo)
	LEFT JOIN sys.objects o ON o.name = x.Nome AND o.schema_id = SCHEMA_ID('dbo')
	LEFT JOIN sys.sql_modules m ON m.object_id = o.object_id
ORDER BY x.Nome;
GO