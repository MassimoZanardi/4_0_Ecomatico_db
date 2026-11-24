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
