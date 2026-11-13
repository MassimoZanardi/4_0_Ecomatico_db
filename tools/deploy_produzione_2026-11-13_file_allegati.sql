/*
	Deploy produzione - 2026-11-13 - File allegati a registrazioni e autorizzazioni

	Repo DB: commit dbd98e1 + ed0c09a (deployed-prod..HEAD).

	Contenuto (in quest'ordine, prima la struttura e poi le SP):
	1) tblDomini ricostruita con FileQuotaMax e FileQuotaConsumata BIGINT NULL tra Url e Lock (solo se le colonne
	   mancano). Nella stessa transazione: drop delle 4 funzioni schema-bound che leggono tblDomini, drop e
	   ricreazione di tutte le FK in entrata che esistono in questo DB (lette da sys.foreign_keys, non da un elenco
	   fisso) e di FK_tblDomini_tblDominiStati, PK_tblDomini. Se qualcosa va storto la transazione torna indietro
	   per intero, funzioni comprese.
	2) Funzioni schema-bound ricreate (prima le 3 di livello 1, poi ufnFunzioni_get_PermessoBySessione).
	3) tblFiles con PK_tblFiles, IX_tblFiles_IdRecord e FK_tblFiles_tblDomini (solo cio' che manca).
	4) SP: uspDomini_get, uspDomini_upd, uspFiles_get_Permesso, uspFiles_get_Stato, uspFiles_get_List, uspFiles_get,
	   uspFiles_ins, uspFiles_del, uspFiles_get_Orfani_List, uspFiles_del_Orfano, uspFiles_get_Esistenti_List;
	   DROP di uspDomini_get_FileQuota se esiste.
	5) Verifiche finali (ordine colonne, righe, FK, funzioni schema-bound).

	Rilanciabile: la ricostruzione avviene solo se FileQuotaMax manca, tblFiles e indice solo se mancano.

	Eseguire con sqlcmd (serve per :on error exit, che ferma lo script al primo errore):
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-11-13_file_allegati.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/
:on error exit
GO

--------------------------------------------------------------------------------
-- 1) Ricostruzione di tblDomini con FileQuotaMax e FileQuotaConsumata
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET XACT_ABORT ON;

IF COL_LENGTH('dbo.tblDomini', 'FileQuotaMax') IS NULL
BEGIN

	-- Le colonne attuali devono essere esattamente quelle attese, nell'ordine atteso
	DECLARE @colonne NVARCHAR(MAX) = (
		SELECT name + ','
		FROM sys.columns
		WHERE object_id = OBJECT_ID('dbo.tblDomini')
		ORDER BY column_id
		FOR XML PATH('')
	);
	IF @colonne <> N'Id,IdStato,Nome,Riferimento,Registrazione,Scadenza,ScadenzaAuto,Master,UtentiMax,AziendeMax,SediMax,RegistriMax,MagazziniMax,ServiziMax,RentriMax,ConservazioniMax,ConservazioniXfirMax,Demo,Codice,Logo,Url,Lock,'
		THROW 50001, 'tblDomini: le colonne non sono quelle attese, ricostruzione annullata', 1;

	DECLARE @righe INT = (SELECT COUNT(*) FROM dbo.tblDomini);

	-- FK in entrata che esistono in questo DB
	DECLARE @fk TABLE (
		Nome SYSNAME,
		Tabella NVARCHAR(300),
		Colonne NVARCHAR(MAX),
		ColonneRif NVARCHAR(MAX),
		OnDelete NVARCHAR(60),
		OnUpdate NVARCHAR(60),
		NonAffidabile BIT,
		Disabilitata BIT
	);
	INSERT INTO @fk (Nome, Tabella, Colonne, ColonneRif, OnDelete, OnUpdate, NonAffidabile, Disabilitata)
	SELECT
		fk.name,
		QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id)) + '.' + QUOTENAME(OBJECT_NAME(fk.parent_object_id)),
		STUFF((
			SELECT ',' + QUOTENAME(COL_NAME(c.parent_object_id, c.parent_column_id))
			FROM sys.foreign_key_columns c
			WHERE c.constraint_object_id = fk.object_id
			ORDER BY c.constraint_column_id
			FOR XML PATH('')
		), 1, 1, ''),
		STUFF((
			SELECT ',' + QUOTENAME(COL_NAME(c.referenced_object_id, c.referenced_column_id))
			FROM sys.foreign_key_columns c
			WHERE c.constraint_object_id = fk.object_id
			ORDER BY c.constraint_column_id
			FOR XML PATH('')
		), 1, 1, ''),
		REPLACE(fk.delete_referential_action_desc, '_', ' '),
		REPLACE(fk.update_referential_action_desc, '_', ' '),
		fk.is_not_trusted,
		fk.is_disabled
	FROM sys.foreign_keys fk
	WHERE
		fk.referenced_object_id = OBJECT_ID('dbo.tblDomini')
		AND fk.parent_object_id <> fk.referenced_object_id;

	DECLARE @sql NVARCHAR(MAX) = N'';

	BEGIN TRANSACTION;

		-- Funzioni schema-bound (prima quella di livello 2)
		DROP FUNCTION IF EXISTS dbo.ufnFunzioni_get_PermessoBySessione;
		DROP FUNCTION IF EXISTS dbo.ufnFunzioni_get_PermessoByUtente;
		DROP FUNCTION IF EXISTS dbo.ufnFunzioni_get_ByUtente_List;
		DROP FUNCTION IF EXISTS dbo.ufnUtenti_get_IsAdmin;

		SELECT @sql += N'ALTER TABLE ' + Tabella + N' DROP CONSTRAINT ' + QUOTENAME(Nome) + N';' + CHAR(13) + CHAR(10)
		FROM @fk;
		EXEC sys.sp_executesql @sql;

		IF OBJECT_ID('dbo.FK_tblDomini_tblDominiStati', 'F') IS NOT NULL
			ALTER TABLE dbo.tblDomini DROP CONSTRAINT FK_tblDomini_tblDominiStati;

		CREATE TABLE dbo.tblDomini_nuova(
			[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
			[IdStato] [char](2) COLLATE Latin1_General_CI_AS NULL,
			[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
			[Riferimento] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
			[Registrazione] [smalldatetime] NULL,
			[Scadenza] [date] NULL,
			[ScadenzaAuto] [bit] NULL,
			[Master] [bit] NULL,
			[UtentiMax] [int] NULL,
			[AziendeMax] [int] NULL,
			[SediMax] [int] NULL,
			[RegistriMax] [int] NULL,
			[MagazziniMax] [int] NULL,
			[ServiziMax] [int] NULL,
			[RentriMax] [int] NULL,
			[ConservazioniMax] [int] NULL,
			[ConservazioniXfirMax] [int] NULL,
			[Demo] [bit] NULL,
			[Codice] [char](5) COLLATE Latin1_General_CI_AS NULL,
			[Logo] [varbinary](max) NULL,
			[Url] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
			[FileQuotaMax] [bigint] NULL,
			[FileQuotaConsumata] [bigint] NULL,
			[Lock] [tinyint] NULL
		) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];

		EXEC sys.sp_executesql N'
		INSERT INTO dbo.tblDomini_nuova
			(Id, IdStato, Nome, Riferimento, Registrazione, Scadenza, ScadenzaAuto, [Master], UtentiMax, AziendeMax,
			 SediMax, RegistriMax, MagazziniMax, ServiziMax, RentriMax, ConservazioniMax, ConservazioniXfirMax, Demo,
			 Codice, Logo, [Url], Lock)
		SELECT
			Id, IdStato, Nome, Riferimento, Registrazione, Scadenza, ScadenzaAuto, [Master], UtentiMax, AziendeMax,
			SediMax, RegistriMax, MagazziniMax, ServiziMax, RentriMax, ConservazioniMax, ConservazioniXfirMax, Demo,
			Codice, Logo, [Url], Lock
		FROM dbo.tblDomini;';

		IF (SELECT COUNT(*) FROM dbo.tblDomini_nuova) <> @righe
			THROW 50001, 'tblDomini: numero di righe diverso dopo la copia, ricostruzione annullata', 1;

		DROP TABLE dbo.tblDomini;
		EXEC sys.sp_rename N'dbo.tblDomini_nuova', N'tblDomini', N'OBJECT';

		EXEC sys.sp_executesql N'
		ALTER TABLE dbo.tblDomini ADD CONSTRAINT [PK_tblDomini] PRIMARY KEY CLUSTERED ([Id] ASC)
		WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON,
			ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];

		ALTER TABLE dbo.tblDomini WITH CHECK ADD CONSTRAINT [FK_tblDomini_tblDominiStati] FOREIGN KEY ([IdStato])
		REFERENCES dbo.tblDominiStati ([Id]);';

		-- FK in entrata, come erano (WITH CHECK se affidabili, NOCHECK se no)
		SET @sql = N'';
		SELECT @sql += N'ALTER TABLE ' + Tabella
			+ IIF(NonAffidabile = 1, N' WITH NOCHECK', N' WITH CHECK')
			+ N' ADD CONSTRAINT ' + QUOTENAME(Nome) + N' FOREIGN KEY (' + Colonne + N') REFERENCES dbo.tblDomini (' + ColonneRif + N')'
			+ N' ON DELETE ' + OnDelete + N' ON UPDATE ' + OnUpdate + N';' + CHAR(13) + CHAR(10)
			+ IIF(Disabilitata = 1, N'ALTER TABLE ' + Tabella + N' NOCHECK CONSTRAINT ' + QUOTENAME(Nome) + N';' + CHAR(13) + CHAR(10), N'')
		FROM @fk;
		EXEC sys.sp_executesql @sql;

	COMMIT TRANSACTION;

	DECLARE @messaggio VARCHAR(200) = 'tblDomini ricostruita: ' + CONVERT(VARCHAR(10), @righe) + ' righe, '
		+ CONVERT(VARCHAR(10), (SELECT COUNT(*) FROM @fk)) + ' FK in entrata ricreate';
	PRINT @messaggio;
END
ELSE
	PRINT 'tblDomini ha già FileQuotaMax: ricostruzione saltata';

SET XACT_ABORT OFF;
GO

--------------------------------------------------------------------------------
-- 2) Funzioni schema-bound (la funzione di livello 2 va tolta prima e ricreata per ultima)
--------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS dbo.ufnFunzioni_get_PermessoBySessione;
GO

-- dbo.ufnFunzioni_get_PermessoByUtente

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnFunzioni_get_PermessoByUtente]
(
	@IdFunzione CHAR(3),
	@IdUtente CHAR(16)
)
RETURNS TINYINT
WITH SCHEMABINDING
AS
BEGIN
	IF @IdFunzione IS NULL OR @IdUtente IS NULL
		RETURN 0;

	-- Aree (ARE): servono solo con almeno 2 aziende interne attive nel dominio dell'utente (le aree
	-- condividono anagrafiche tra aziende interne); l'amministratore del dominio Master le vede sempre.
	-- Stessa regola di ufnFunzioni_get_ByUtente_List (menu)
	IF @IdFunzione = 'ARE'
		AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblUtenti AS u
				INNER JOIN dbo.tblDomini AS d ON u.IdDominio = d.Id
			WHERE
				u.Id = @IdUtente
				AND u.IdRuolo = 'AD'
				AND d.[Master] = 1
		)
		AND (
			SELECT COUNT(*)
			FROM
				dbo.tblUtenti AS u
				INNER JOIN dbo.tblSediInterne AS si ON u.IdDominio = si.IdDominio
				INNER JOIN dbo.tblSedi AS s ON si.Id = s.Id
			WHERE
				u.Id = @IdUtente
				AND s.Lock = 0
		) < 2
		RETURN 0;

	RETURN
	(
		SELECT TOP (1)
			Permesso
		FROM
		(
			-- Utenti non amministratori
			SELECT Permesso = uf.IdPermesso
			FROM dbo.tblUtenti AS u
			INNER JOIN dbo.tblUtentiFunzioni AS uf
				ON u.Id = uf.Id
			INNER JOIN dbo.tblFunzioni AS f
				ON uf.IdFunzione = f.Id
			WHERE
				u.Id = @IdUtente
				AND u.IdRuolo <> 'AD'
				AND uf.IdFunzione = @IdFunzione
				AND f.Attiva = 1
			UNION ALL

			-- Amministratori
			SELECT Permesso = CONVERT(TINYINT, 2)
			FROM dbo.tblUtenti AS u
			INNER JOIN dbo.tblDominiModuli AS dm
				ON u.IdDominio = dm.Id
			INNER JOIN dbo.tblModuliFunzioni AS mf
				ON dm.IdModulo = mf.Id
			INNER JOIN dbo.tblFunzioni AS f
				ON mf.IdFunzione = f.Id
			WHERE
				u.Id = @IdUtente
				AND u.IdRuolo = 'AD'
				AND f.Id = @IdFunzione
				AND f.[Master] = 0
				AND f.Attiva = 1
			UNION ALL

			-- Amministratori Master
			SELECT Permesso = CONVERT(TINYINT, 2)
			FROM dbo.tblUtenti AS u
			INNER JOIN dbo.tblDomini AS d
				ON u.IdDominio = d.Id
			INNER JOIN dbo.tblFunzioni AS f
				ON f.Id = @IdFunzione
			WHERE
				u.Id = @IdUtente
				AND u.IdRuolo = 'AD'
				AND d.[Master] = 1
				AND f.Attiva = 1
			UNION ALL

			SELECT Permesso = CONVERT(TINYINT, 0)
		) AS t
		ORDER BY Permesso DESC
	);
END;
GO

-- dbo.ufnFunzioni_get_ByUtente_List

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnFunzioni_get_ByUtente_List] (
	@IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- ── RAMO 1: Amministratori ───────────────────────────────────────────
	-- Admin dominio normale (Master=0):
	--   accede alle funzioni (f.Master=0) dei moduli attivi abilitati sul dominio
	-- Admin Master (Master=1):
	--   accede a tutte le funzioni attive del sistema incluse quelle Master
	SELECT
		f.Id,
		Permesso = 2
	FROM
		dbo.tblUtenti u
		INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
		INNER JOIN dbo.tblFunzioni f ON f.Attiva = 1
	WHERE
		u.Id = @IdUtente
		AND u.IdRuolo = 'AD'
		AND
			(
			d.[Master] = 1
			OR f.[Master] = 0
			)
		AND EXISTS ( SELECT 1 FROM dbo.tblModuliFunzioni mf INNER JOIN dbo.tblModuli m ON mf.Id = m.Id WHERE mf.IdFunzione = f.Id AND m.Attivo = 1 AND ( d.[Master] = 1 OR EXISTS ( SELECT 1 FROM dbo.tblDominiModuli dm WHERE dm.Id = d.Id AND dm.IdModulo = mf.Id ) ) )
		-- Aree (ARE): solo con almeno 2 aziende interne attive nel dominio; l'Admin Master le vede sempre
		-- (stessa regola di ufnFunzioni_get_PermessoByUtente)
		AND
			(
			f.Id <> 'ARE'
			OR d.[Master] = 1
			OR ( SELECT COUNT(*) FROM dbo.tblSediInterne si INNER JOIN dbo.tblSedi s ON si.Id = s.Id WHERE si.IdDominio = d.Id AND s.Lock = 0 ) >= 2
			)
	UNION ALL

	-- ── RAMO 2: Utenti Standard ──────────────────────────────────────────
	-- Accede alle funzioni (f.Master=0) se almeno una delle due condizioni è vera:
	--   A) La funzione appartiene al modulo Base (BAS): Permesso = 2
	--   B) La funzione ha un permesso esplicito in tblUtentiFunzioni
	--      su un modulo attivo abilitato sul dominio: Permesso = IdPermesso
	-- Il LEFT JOIN su tblUtentiFunzioni garantisce al massimo una riga
	-- per combinazione (utente, funzione) grazie alla PK (Id, IdFunzione)
	SELECT
		f.Id,
		Permesso = CASE
			WHEN EXISTS (
				SELECT 1
				FROM dbo.tblModuliFunzioni mf
				WHERE
					mf.IdFunzione = f.Id
					AND mf.Id = 'BAS'
			) THEN 2
			ELSE uf.IdPermesso
		END
	FROM
		dbo.tblUtenti u
		INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
		INNER JOIN dbo.tblFunzioni f ON f.Attiva = 1
										   AND f.[Master] = 0
		LEFT JOIN dbo.tblUtentiFunzioni uf ON u.Id = uf.Id
										   AND uf.IdFunzione = f.Id
	WHERE
		u.Id = @IdUtente
		AND u.IdRuolo = 'US'
		AND d.[Master] = 0
		AND
			(
			f.Id <> 'ARE'
			OR ( SELECT COUNT(*) FROM dbo.tblSediInterne si INNER JOIN dbo.tblSedi s ON si.Id = s.Id WHERE si.IdDominio = d.Id AND s.Lock = 0 ) >= 2
			)
		AND
			(
			EXISTS ( SELECT 1 FROM dbo.tblModuliFunzioni mf WHERE mf.IdFunzione = f.Id AND mf.Id = 'BAS' )
			OR
				(
				uf.Id IS NOT NULL
				AND EXISTS ( SELECT 1 FROM dbo.tblDominiModuli dm INNER JOIN dbo.tblModuliFunzioni mf ON dm.IdModulo = mf.Id INNER JOIN dbo.tblModuli m ON mf.Id = m.Id WHERE dm.Id = d.Id AND mf.IdFunzione = f.Id AND m.Attivo = 1 )
				)
			)
);
GO

-- dbo.ufnUtenti_get_IsAdmin

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnUtenti_get_IsAdmin]
(
	@IdSessione CHAR(16))
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
	DECLARE @rtn INT
	IF EXISTS (SELECT 1
		FROM
			dbo.tblUtenti u
			INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
			INNER JOIN dbo.tblSessioni s ON u.Id = s.IdUtente
		WHERE
			s.Id = @IdSessione
			AND d.[Master] = 1
			AND u.Lock = 0
	)
		SET @rtn = 2
	ELSE IF EXISTS (SELECT 1
		FROM
			dbo.tblUtenti u INNER JOIN
			dbo.tblSessioni s ON u.Id = s.IdUtente
		WHERE
			s.Id = @IdSessione
			AND u.IdRuolo = 'AD'
			AND u.Lock = 0
	)
		SET @rtn = 1
	ELSE
		SET @rtn = 0

	RETURN @rtn
END
GO

-- dbo.ufnFunzioni_get_PermessoBySessione

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnFunzioni_get_PermessoBySessione]
(
	@IdFunzione CHAR(3),
	@IdSessione CHAR(16)
)
RETURNS TINYINT
WITH SCHEMABINDING
AS
BEGIN
	IF @IdFunzione IS NULL OR @IdSessione IS NULL
		RETURN 0;

	RETURN ISNULL(
		(
			SELECT dbo.ufnFunzioni_get_PermessoByUtente(@IdFunzione, s.IdUtente)
			FROM dbo.tblSessioni AS s
			WHERE s.Id = @IdSessione),
		0
	);
END;
GO

--------------------------------------------------------------------------------
-- 3) tblFiles (solo ciò che manca)
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
IF OBJECT_ID('dbo.tblFiles', 'U') IS NULL
BEGIN
	CREATE TABLE [dbo].[tblFiles](
		[Id] [uniqueidentifier] NOT NULL,
		[IdRecord] [char](16) COLLATE Latin1_General_CI_AS NULL,
		[IdDominio] [char](16) COLLATE Latin1_General_CI_AS NULL,
		[Nome] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
		[Quota] [int] NULL,
	 CONSTRAINT [PK_tblFiles] PRIMARY KEY CLUSTERED
	(
		[Id] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
	) ON [PRIMARY];
	PRINT 'tblFiles creata';
END
ELSE
	PRINT 'tblFiles esiste già';
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.tblFiles') AND name = 'IX_tblFiles_IdRecord')
BEGIN
	CREATE NONCLUSTERED INDEX [IX_tblFiles_IdRecord] ON [dbo].[tblFiles]
	(
		[IdRecord] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
	PRINT 'IX_tblFiles_IdRecord creato';
END
GO
IF OBJECT_ID('dbo.FK_tblFiles_tblDomini', 'F') IS NULL
BEGIN
	ALTER TABLE [dbo].[tblFiles] WITH CHECK ADD CONSTRAINT [FK_tblFiles_tblDomini] FOREIGN KEY([IdDominio])
	REFERENCES [dbo].[tblDomini] ([Id]);
	PRINT 'FK_tblFiles_tblDomini creata';
END
GO

--------------------------------------------------------------------------------
-- 4) Stored procedure
--------------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS dbo.uspDomini_get_FileQuota;
GO

-- dbo.uspDomini_get

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
			Demo,
			Logo,
			Codice = LOWER(ISNULL(Codice, RIGHT(CONVERT(VARCHAR(36), NEWID()), 5))),
			[Url] = ISNULL([Url], ''),
			Lock
		FROM
			dbo.tblDomini
		WHERE Id = @Id;

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

-- dbo.uspDomini_upd

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

-- dbo.uspFiles_get_Permesso

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- File allegati (tblFiles): permesso della sessione sul record a cui sono allegati, usato da tutte le uspFiles_*.
-- @Permesso: 0 nessun accesso, 1 lettura (elenco e download), 2 modifica (carica e cancella).
-- Record ammessi: registrazioni e autorizzazioni attive (Lock < 2): le bozze non hanno allegati e quelle cancellate
-- (Lock = 4) li tengono per un eventuale ripristino, senza mostrarli.
-- Registrazione: sede interna dell'utente sul registro, permesso della funzione RRG.
-- Autorizzazione: dell'azienda del contesto, permesso della funzione RAT; condivisa da un'altra azienda (sede interna
-- dell'utente o azienda esterna condivisa, come uspRifiutiAutorizzazioni_get): al massimo lettura, come la modifica.
-- Fail-safe come uspSessione_get_FunzionePermesso: su parametri vuoti o record non trovato restituisce 0
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_get_Permesso]
	@IdRecord CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Permesso INT = NULL OUTPUT
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		SET @Permesso = 0;

		SET @IdRecord = NULLIF(LTRIM(RTRIM(@IdRecord)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRecord IS NULL OR @IdSessione IS NULL
			GOTO BRANCH_END;

		DECLARE @permessoFunzione INT;

		-- Registrazione
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE
				r.Id = @IdRecord
				AND r.Lock < 2
		)
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'RRG',
				@Permesso = @permessoFunzione OUTPUT;

			SET @permessoFunzione = ISNULL(@permessoFunzione, 0);
			SET @Permesso = IIF(@permessoFunzione > 2, 2, @permessoFunzione);
			GOTO BRANCH_END;
		END

		-- Autorizzazione
		DECLARE @idUtente CHAR(16);
		DECLARE @idAzienda CHAR(16);
		SELECT
			@idUtente = IdUtente,
			@idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		DECLARE @isProprietaria BIT = 0;
		DECLARE @isVisibile BIT = 0;

		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
			WHERE
				a.Id = @IdRecord
				AND a.Lock < 2
				AND s.IdAziendaInterna = @idAzienda
		)
			SET @isProprietaria = 1;
		ELSE IF EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON s.IdAziendaInterna = i.Id
			WHERE
				a.Id = @IdRecord
				AND a.Lock < 2
		)
		OR EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				INNER JOIN dbo.ufnSedi_get_AziendeEsterneCondiviseByUtente_List(@idUtente) x ON s.Id = x.Id
			WHERE
				a.Id = @IdRecord
				AND a.Lock < 2
				AND x.IdAziendaInterna <> @idAzienda
		)
			SET @isVisibile = 1;

		IF @isProprietaria = 1 OR @isVisibile = 1
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'RAT',
				@Permesso = @permessoFunzione OUTPUT;

			SET @permessoFunzione = ISNULL(@permessoFunzione, 0);
			SET @Permesso = IIF(@permessoFunzione > IIF(@isProprietaria = 1, 2, 1), IIF(@isProprietaria = 1, 2, 1), @permessoFunzione);
		END

	END TRY
	BEGIN CATCH
		-- Fail-safe: nega l'accesso senza far saltare la SP chiamante
		SET @Permesso = 0;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;

END;
GO

-- dbo.uspFiles_get_Stato

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Sezione "Allegati" della scheda di una registrazione o di un'autorizzazione (@IdRecord): spazio del dominio della
-- sessione (byte) e permesso sul record (uspFiles_get_Permesso: 0 nessuno, 1 lettura, 2 modifica). La sezione si mostra
-- con IsAttivo = 1 (FileQuotaMax > 0) e Permesso >= 1; senza permesso non è un errore, la sezione resta nascosta
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_get_Stato]
	@IdRecord CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRecord = NULLIF(LTRIM(RTRIM(@IdRecord)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRecord IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @IdRecord e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		DECLARE @permesso INT;
		EXEC dbo.uspFiles_get_Permesso
			@IdRecord = @IdRecord,
			@IdSessione = @IdSessione,
			@Permesso = @permesso OUTPUT;

		SELECT
			IdRecord = @IdRecord,
			IsAttivo = CAST(IIF(ISNULL(d.FileQuotaMax, 0) > 0, 1, 0) AS BIT),
			Permesso = ISNULL(@permesso, 0),
			FileQuotaMax = ISNULL(d.FileQuotaMax, 0),
			FileQuotaConsumata = ISNULL(d.FileQuotaConsumata, 0),
			FileQuotaResidua = IIF(ISNULL(d.FileQuotaMax, 0) - ISNULL(d.FileQuotaConsumata, 0) < 0, 0, ISNULL(d.FileQuotaMax, 0) - ISNULL(d.FileQuotaConsumata, 0))
		FROM
			dbo.tblSessioni e
			INNER JOIN dbo.tblDomini d ON e.IdDominio = d.Id
		WHERE e.Id = @IdSessione;

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

-- dbo.uspFiles_get_List

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- File allegati di una registrazione o di un'autorizzazione (@IdRecord). Permesso e titolarità in uspFiles_get_Permesso;
-- IsModificabile dice se la sessione può caricare e cancellare
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_get_List]
	@IdRecord CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRecord = NULLIF(LTRIM(RTRIM(@IdRecord)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRecord IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @IdRecord e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		DECLARE @permesso INT;
		EXEC dbo.uspFiles_get_Permesso
			@IdRecord = @IdRecord,
			@IdSessione = @IdSessione,
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			f.Id,
			f.IdRecord,
			f.Nome,
			Quota = ISNULL(f.Quota, 0),
			IsModificabile = CAST(IIF(@permesso >= 2, 1, 0) AS BIT)
		FROM dbo.tblFiles f
		WHERE f.IdRecord = @IdRecord
		ORDER BY f.Nome;

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

-- dbo.uspFiles_get

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Un file allegato, per il download: l'app legge il contenuto dall'Object Storage (<Prefisso>/<Id>) solo dopo questa SP.
-- Basta il permesso di lettura sul record (uspFiles_get_Permesso)
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_get]
	@Id UNIQUEIDENTIFIER = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		DECLARE @idRecord CHAR(16) = (SELECT IdRecord
		FROM dbo.tblFiles
		WHERE Id = @Id);

		IF @idRecord IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'File non trovato';
			GOTO BRANCH_END;
		END

		DECLARE @permesso INT;
		EXEC dbo.uspFiles_get_Permesso
			@IdRecord = @idRecord,
			@IdSessione = @IdSessione,
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			f.Id,
			f.IdRecord,
			f.Nome,
			Quota = ISNULL(f.Quota, 0),
			IsModificabile = CAST(IIF(@permesso >= 2, 1, 0) AS BIT)
		FROM dbo.tblFiles f
		WHERE f.Id = @Id;

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

-- dbo.uspFiles_ins

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Nuovo file allegato a una registrazione o a un'autorizzazione (@IdRecord). Controlla nome, tipo, dimensione, permesso di
-- modifica (uspFiles_get_Permesso) e spazio del dominio; prenota lo spazio (tblDomini.FileQuotaConsumata) e restituisce
-- l'Id del file. L'app carica poi il contenuto sull'Object Storage (<Prefisso>/<Id>); se il caricamento fallisce chiama
-- uspFiles_del, che toglie la riga e libera lo spazio.
-- Spazio: FileQuotaMax e FileQuotaConsumata in byte; senza FileQuotaMax (NULL o 0) gli allegati non sono attivi
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_ins]
	@IdRecord CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(500) = NULL,
	@Quota INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		DECLARE @quotaMaxFile INT = 10485760; -- 10 MB

		SET @IdRecord = NULLIF(LTRIM(RTRIM(@IdRecord)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = NULLIF(LTRIM(RTRIM(@Nome)), '');

		IF @IdRecord IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @IdRecord e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il nome del file non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF LEN(@Nome) > 200
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il nome del file può avere al massimo 200 caratteri';
			GOTO BRANCH_END;
		END

		DECLARE @estensione VARCHAR(500) = IIF(CHARINDEX('.', @Nome) > 0, LOWER(RIGHT(@Nome, CHARINDEX('.', REVERSE(@Nome)) - 1)), '');
		IF @estensione NOT IN ('pdf', 'png', 'jpg', 'jpeg', 'gif')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Tipo di file non ammesso: selezionare un file PDF, PNG, JPG, JPEG o GIF';
			GOTO BRANCH_END;
		END

		IF ISNULL(@Quota, 0) <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il file è vuoto';
			GOTO BRANCH_END;
		END
		IF @Quota > @quotaMaxFile
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La dimensione massima del file è 10 MB';
			GOTO BRANCH_END;
		END

		DECLARE @permesso INT;
		EXEC dbo.uspFiles_get_Permesso
			@IdRecord = @IdRecord,
			@IdSessione = @IdSessione,
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idDominio CHAR(16) = (SELECT IdDominio
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione);

		DECLARE @id UNIQUEIDENTIFIER = NEWID();

		BEGIN TRANSACTION;

			-- Prenota lo spazio in un'unica istruzione: due caricamenti contemporanei non superano insieme il massimo
			UPDATE dbo.tblDomini
			SET FileQuotaConsumata = ISNULL(FileQuotaConsumata, 0) + @Quota
			WHERE
				Id = @idDominio
				AND ISNULL(FileQuotaMax, 0) > 0
				AND ISNULL(FileQuotaConsumata, 0) + @Quota <= FileQuotaMax;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = IIF(EXISTS (SELECT 1
				FROM dbo.tblDomini
				WHERE
					Id = @idDominio
					AND ISNULL(FileQuotaMax, 0) > 0
				), 'Spazio per i file allegati insufficiente', 'Lo spazio per i file allegati non è attivo');
				GOTO BRANCH_END;
			END

			INSERT dbo.tblFiles (Id, IdRecord, IdDominio, Nome, Quota)
			VALUES (@id, @IdRecord, @idDominio, @Nome, @Quota);

		COMMIT TRANSACTION;

		EXEC dbo.uspId_upd @Id = @IdRecord, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT Id = @id;

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

-- dbo.uspFiles_del

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Cancella un file allegato: toglie la riga e libera lo spazio del dominio che l'ha caricato (tblFiles.IdDominio).
-- Serve il permesso di modifica sul record (uspFiles_get_Permesso). L'app cancella il contenuto dall'Object Storage
-- (<Prefisso>/<Id>) dopo questa SP; un file già cancellato non è un errore (doppio clic, caricamento fallito)
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_del]
	@Id UNIQUEIDENTIFIER = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		DECLARE @idRecord CHAR(16);
		DECLARE @idDominio CHAR(16);
		DECLARE @quota INT;
		SELECT
			@idRecord = IdRecord,
			@idDominio = IdDominio,
			@quota = ISNULL(Quota, 0)
		FROM dbo.tblFiles
		WHERE Id = @Id;

		IF @idRecord IS NOT NULL
		BEGIN

			DECLARE @permesso INT;
			EXEC dbo.uspFiles_get_Permesso
				@IdRecord = @idRecord,
				@IdSessione = @IdSessione,
				@Permesso = @permesso OUTPUT;

			IF 2 > @permesso
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;

				DELETE dbo.tblFiles
				WHERE Id = @Id;

				-- Una cancellazione contemporanea dello stesso file libera lo spazio una volta sola
				IF @@ROWCOUNT > 0
					UPDATE dbo.tblDomini
					SET FileQuotaConsumata = IIF(ISNULL(FileQuotaConsumata, 0) - @quota < 0, 0, ISNULL(FileQuotaConsumata, 0) - @quota)
					WHERE Id = @idDominio;

			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @idRecord, @IdSessione = @IdSessione, @Operazione = 'U';

		END

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

-- dbo.uspFiles_get_Orfani_List

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Pulizia dei file allegati (docs/regole/allegati.md, A7): righe di tblFiles il cui record non esiste più, per esempio
-- una rettifica non inviata cancellata fisicamente. Un record cancellato con Lock = 4 esiste ancora e tiene i suoi
-- file per il ripristino. Usata dal servizio di pulizia dell'app, senza sessione.
-- ATTENZIONE: quando gli allegati si estendono a un'altra tabella, va aggiunta qui, altrimenti i suoi file risultano
-- orfani e vengono cancellati
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_get_Orfani_List]
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		SELECT
			f.Id,
			f.IdRecord,
			f.IdDominio,
			f.Nome,
			Quota = ISNULL(f.Quota, 0)
		FROM dbo.tblFiles f
		WHERE
			NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioni r WHERE r.Id = f.IdRecord)
			AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioni a WHERE a.Id = f.IdRecord);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;

END;
GO

-- dbo.uspFiles_del_Orfano

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Pulizia dei file allegati (docs/regole/allegati.md, A7): cancella la riga di un file orfano e ne libera lo spazio sul
-- dominio che l'aveva caricato. Ricontrolla che il record non esista, nella stessa istruzione della cancellazione:
-- una riga tornata valida nel frattempo resta. Il servizio di pulizia la chiama dopo aver cancellato il file
-- dall'archivio. Restituisce 1 se la riga è stata cancellata, 0 se non c'era o non è orfana
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_del_Orfano]
	@Id UNIQUEIDENTIFIER = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @cancellato TABLE (IdDominio CHAR(16), Quota INT);

		BEGIN TRANSACTION;

			DELETE f
			OUTPUT
				deleted.IdDominio,
				ISNULL(deleted.Quota, 0)
			INTO @cancellato (IdDominio, Quota)
			FROM dbo.tblFiles f
			WHERE
				f.Id = @Id
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioni r WHERE r.Id = f.IdRecord)
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioni a WHERE a.Id = f.IdRecord);

			UPDATE d
			SET FileQuotaConsumata = IIF(ISNULL(d.FileQuotaConsumata, 0) - c.Quota < 0, 0, ISNULL(d.FileQuotaConsumata, 0) - c.Quota)
			FROM
				dbo.tblDomini d
				INNER JOIN @cancellato c ON d.Id = c.IdDominio;

		COMMIT TRANSACTION;

		SELECT Cancellato = CAST(IIF(EXISTS (SELECT 1
		FROM @cancellato), 1, 0) AS INT);

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

-- dbo.uspFiles_get_Esistenti_List

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Pulizia dei file allegati (docs/regole/allegati.md, A7): tra gli Id dei file trovati nell'archivio (@Ids, separati da
-- virgola), quelli che hanno ancora la riga in tblFiles. Gli altri sono file rimasti nell'archivio dopo una
-- cancellazione non completata e il servizio di pulizia li cancella. Un valore che non è un Id viene ignorato
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_get_Esistenti_List]
	@Ids VARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		SELECT f.Id
		FROM
			dbo.tblFiles f
			INNER JOIN (
				SELECT DISTINCT Id = TRY_CAST(LTRIM(RTRIM(s.value)) AS UNIQUEIDENTIFIER)
				FROM STRING_SPLIT(ISNULL(@Ids, ''), ',') s
			) i ON f.Id = i.Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;

END;
GO

--------------------------------------------------------------------------------
-- 5) Verifiche
--------------------------------------------------------------------------------
SET NOCOUNT ON;

SELECT Verifica = 'Colonne tblDomini (FileQuotaMax 22, FileQuotaConsumata 23, Lock 24)', name, column_id
FROM sys.columns
WHERE object_id = OBJECT_ID('dbo.tblDomini') AND name IN ('Url', 'FileQuotaMax', 'FileQuotaConsumata', 'Lock')
ORDER BY column_id;

SELECT Verifica = 'Righe tblDomini', Righe = COUNT(*) FROM dbo.tblDomini;

SELECT Verifica = 'FK su tblDomini', fk.name, Tabella = OBJECT_NAME(fk.parent_object_id), fk.is_not_trusted, fk.is_disabled
FROM sys.foreign_keys fk
WHERE fk.referenced_object_id = OBJECT_ID('dbo.tblDomini') OR fk.parent_object_id = OBJECT_ID('dbo.tblDomini')
ORDER BY fk.name;

SELECT Verifica = 'PK e indici', Tabella = OBJECT_NAME(object_id), name, type_desc
FROM sys.indexes
WHERE object_id IN (OBJECT_ID('dbo.tblDomini'), OBJECT_ID('dbo.tblFiles')) AND name IS NOT NULL;

SELECT
	Verifica = 'Funzioni (schema_bound 1) e SP: ansi_nulls e quoted_id 1, bare_lf 0',
	o.name,
	schema_bound = m.is_schema_bound,
	ansi_nulls = OBJECTPROPERTY(o.object_id, 'ExecIsAnsiNullsOn'),
	quoted_id = OBJECTPROPERTY(o.object_id, 'ExecIsQuotedIdentOn'),
	bare_lf = LEN(REPLACE(m.definition, CHAR(13) + CHAR(10), '')) - LEN(REPLACE(REPLACE(m.definition, CHAR(13) + CHAR(10), ''), CHAR(10), ''))
FROM sys.objects o
INNER JOIN sys.sql_modules m ON o.object_id = m.object_id
WHERE o.name IN (
	'ufnFunzioni_get_ByUtente_List', 'ufnFunzioni_get_PermessoByUtente', 'ufnUtenti_get_IsAdmin',
	'ufnFunzioni_get_PermessoBySessione', 'uspDomini_get', 'uspDomini_upd', 'uspFiles_get_Permesso',
	'uspFiles_get_Stato', 'uspFiles_get_List', 'uspFiles_get', 'uspFiles_ins', 'uspFiles_del',
	'uspFiles_get_Orfani_List', 'uspFiles_del_Orfano', 'uspFiles_get_Esistenti_List')
ORDER BY o.name;

SELECT Verifica = 'uspDomini_get_FileQuota tolta (0)', Esiste = COUNT(*) FROM sys.objects WHERE name = 'uspDomini_get_FileQuota';
GO
