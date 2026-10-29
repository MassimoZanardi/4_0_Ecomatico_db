/*
Deploy produzione 2026-10-29 - DIWASS: credenziale del dominio associata alle aziende interne (Diwass > Aziende),
Copia/incolla degli Allegati VII, spia "modifiche da inviare" solo se il salvataggio cambia i dati

Rieseguibile. Eseguire con sqlcmd -f 65001 -I -b (oppure da SSMS) sul DB 4_0_ecomatico, poi pubblicare subito l'app
e l'hub DIWASS: la struttura cambia (la credenziale non ha più l'azienda), quindi fra lo script e la pubblicazione
le pagine Diwass dell'app attuale danno errore.

1) Struttura (tools/diwass_credenziali_aziende_struttura.sql): tabella tblDiwassCredenzialiAziende, migrazione delle
   credenziali attive, eliminazione di tblDiwassCredenziali.IdAziendaInterna, pagina DWY e voce di menu AL4
   (Diwass > Aziende), eliminazione di uspDiwassCredenziali_get_AziendeInterne_SelectList.
2) SP uspDiwassCredenziali_* (credenziale senza azienda, colonna Aziende associate, cancellazione bloccata se usata).
3) SP nuove uspDiwassAziende_* (elenco, scheda, select delle credenziali con ricerca, salvataggio, esportazione).
4) uspDiwassOperatori_get_IdDiwassCredenziale e uspDiwassAllegatiVii_get_Invio: credenziale dell'azienda.
5) uspDiwassAllegatiVii_ins (@IdCopia, Copia/incolla) e uspDiwassAllegatiVii_upd (DaInviare solo se i dati cambiano).
6) uspSYS_del_SedeInternaCascade: cancella anche l'associazione della credenziale DIWASS dell'azienda.
*/
-- DIWASS: la credenziale diventa del dominio e si associa alle aziende interne in Diwass > Aziende, come le credenziali
-- RENTRI si associano alle sedi in Rentri > Sedi. La chiave DIWASS è dell'utente EU Login e vale per tutte le aziende
-- che rappresenta: una credenziale può servire più aziende, ogni azienda ne usa al massimo una.
-- 1) tabella di associazione tblDiwassCredenzialiAziende (una riga per azienda);
-- 2) migrazione delle credenziali attive da tblDiwassCredenziali.IdAziendaInterna;
-- 3) eliminazione di IdAziendaInterna da tblDiwassCredenziali (con indice unico e FK);
-- 4) pagina e voce di menu Diwass > Aziende (funzione DWC, dopo Credenziali);
-- 5) eliminazione di uspDiwassCredenziali_get_AziendeInterne_SelectList (la credenziale non sceglie più l'azienda).
-- Script idempotente: rieseguibile senza effetti su un DB già aggiornato.
SET NOCOUNT ON;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID('dbo.tblDiwassCredenzialiAziende', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblDiwassCredenzialiAziende (
		IdAziendaInterna CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdCredenziale CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		CONSTRAINT PK_tblDiwassCredenzialiAziende PRIMARY KEY CLUSTERED (IdAziendaInterna ASC)
	);

	ALTER TABLE dbo.tblDiwassCredenzialiAziende WITH CHECK ADD CONSTRAINT FK_tblDiwassCredenzialiAziende_tblSediInterne
		FOREIGN KEY (IdAziendaInterna) REFERENCES dbo.tblSediInterne (Id);
	ALTER TABLE dbo.tblDiwassCredenzialiAziende WITH CHECK ADD CONSTRAINT FK_tblDiwassCredenzialiAziende_tblDiwassCredenziali
		FOREIGN KEY (IdCredenziale) REFERENCES dbo.tblDiwassCredenziali (Id);

	CREATE NONCLUSTERED INDEX IX_DiwassCredenzialiAziende_IdCredenziale ON dbo.tblDiwassCredenzialiAziende (IdCredenziale ASC);
END
GO
IF COL_LENGTH('dbo.tblDiwassCredenziali', 'IdAziendaInterna') IS NOT NULL
BEGIN
	-- Le credenziali attive conservano la loro azienda; quelle cancellate (Lock = 4) e le bozze restano senza
	EXEC sp_executesql N'
		INSERT INTO dbo.tblDiwassCredenzialiAziende (IdAziendaInterna, IdCredenziale)
		SELECT c.IdAziendaInterna, c.Id
		FROM dbo.tblDiwassCredenziali c
		WHERE
			c.Lock = 0
			AND c.IdAziendaInterna IS NOT NULL
			AND NOT EXISTS (SELECT 1 FROM dbo.tblDiwassCredenzialiAziende a WHERE a.IdAziendaInterna = c.IdAziendaInterna);';

	IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_DiwassCredenziali_IdAziendaInterna' AND object_id = OBJECT_ID('dbo.tblDiwassCredenziali'))
		DROP INDEX UX_DiwassCredenziali_IdAziendaInterna ON dbo.tblDiwassCredenziali;
	IF OBJECT_ID('dbo.FK_tblDiwassCredenziali_tblSediInterne', 'F') IS NOT NULL
		ALTER TABLE dbo.tblDiwassCredenziali DROP CONSTRAINT FK_tblDiwassCredenziali_tblSediInterne;
	ALTER TABLE dbo.tblDiwassCredenziali DROP COLUMN IdAziendaInterna;
END
GO
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'DWY')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url) VALUES ('DWY', 'DWC', 'Aziende', NULL);
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AL4')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AL4', 'AL0', NULL, 'DWY', 3);
GO
DROP PROCEDURE IF EXISTS dbo.uspDiwassCredenziali_get_AziendeInterne_SelectList;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassCredenziali_get]
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblDiwassCredenziali c
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

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblDiwassCredenziali
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Credenziale non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			c.Id,
			Nome = ISNULL(c.Nome, ''),
			h.Username,
			h.AuthKey,
			h.ClientId,
			c.Lock
		FROM
			dbo.tblDiwassCredenziali c
			LEFT JOIN [1_0_diwass]..tblCredenziali h ON c.IdDiwass = h.Id
		WHERE c.Id = @Id;

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassCredenziali_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: dominio della sessione
		SELECT
			c.Id,
			c.Nome,
			h.Username,
			h.ClientId,
			AziendeCount = (SELECT COUNT(*)
			FROM dbo.tblDiwassCredenzialiAziende a
			WHERE a.IdCredenziale = c.Id),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblDiwassCredenziali c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
			LEFT JOIN [1_0_diwass]..tblCredenziali h ON c.IdDiwass = h.Id
		WHERE
			e.Id = @IdSessione
			AND c.Lock = 0
			AND
				(
				@Search IS NULL
				OR c.Nome LIKE '%' + @Search + '%'
				OR h.Username LIKE '%' + @Search + '%'
				)
		ORDER BY c.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Credenziali DIWASS (solo dati descrittivi, mai la chiave di autenticazione): righe per l'esportazione dell'elenco
-- in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspDiwassCredenziali_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspDiwassCredenziali_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

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
			@IdFunzione = 'DWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: dominio della sessione
		SELECT TOP (@MaxRighe + 1)
			[Nome] = c.Nome,
			[Utente EU Login] = h.Username,
			[Client id] = h.ClientId,
			[Aziende associate] = (
				SELECT STRING_AGG(CAST(s.NomeCompleto AS VARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY s.NomeCompleto)
				FROM
					dbo.tblDiwassCredenzialiAziende a
					INNER JOIN dbo.tblSedi s ON a.IdAziendaInterna = s.Id
				WHERE a.IdCredenziale = c.Id)
		FROM
			dbo.tblDiwassCredenziali c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
			LEFT JOIN [1_0_diwass]..tblCredenziali h ON c.IdDiwass = h.Id
		WHERE
			e.Id = @IdSessione
			AND c.Lock = 0
			AND
				(
				@Search IS NULL
				OR c.Nome LIKE '%' + @Search + '%'
				OR h.Username LIKE '%' + @Search + '%'
				)
		ORDER BY c.Nome
		OPTION (RECOMPILE);

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva la credenziale DIWASS del dominio, che si associa poi alle aziende interne in Diwass > Aziende
-- (uspDiwassAziende_upd). I dati di accesso (utente EU Login, chiave di autenticazione, client id) vanno nella riga
-- dell'hub [1_0_diwass]..tblCredenziali, creata al primo salvataggio, come per le credenziali RENTRI
-- (uspRentriCredenziali_upd)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassCredenziali_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Username VARCHAR(50) = NULL,
	@AuthKey VARCHAR(200) = NULL,
	@ClientId VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Username = NULLIF(LTRIM(RTRIM(@Username)), '');
		SET @AuthKey = NULLIF(LTRIM(RTRIM(@AuthKey)), '');
		SET @ClientId = NULLIF(LTRIM(RTRIM(@ClientId)), '');

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
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare un nome per la credenziale';
			GOTO BRANCH_END;
		END
		IF @Username IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il nome utente EU Login';
			GOTO BRANCH_END;
		END
		IF @AuthKey IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la chiave di autenticazione';
			GOTO BRANCH_END;
		END
		IF @ClientId IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il client id';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera IdDominio/IdDiwass correnti
		DECLARE @idDominio CHAR(16);
		DECLARE @idDiwass CHAR(16);
		SELECT
			@idDominio = c.IdDominio,
			@idDiwass = c.IdDiwass
		FROM
			dbo.tblDiwassCredenziali c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un'altra credenziale con lo stesso nome nel dominio
		IF EXISTS (
			SELECT 1
			FROM dbo.tblDiwassCredenziali
			WHERE
				Id <> @Id
				AND IdDominio = @idDominio
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra credenziale con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			-- Crea la riga hub al primo salvataggio, altrimenti la aggiorna
			IF @idDiwass IS NULL
			BEGIN
				SET @idDiwass = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));
				INSERT INTO [1_0_diwass]..tblCredenziali (Id, Username, AuthKey, ClientId)
				VALUES (@idDiwass, @Username, @AuthKey, @ClientId);
			END
			ELSE
			BEGIN
				UPDATE [1_0_diwass]..tblCredenziali
				SET
					Username = @Username,
					AuthKey = @AuthKey,
					ClientId = @ClientId
				WHERE Id = @idDiwass;
			END

			UPDATE dbo.tblDiwassCredenziali
			SET
				Lock = 0,
				IdDiwass = @idDiwass,
				Nome = @Nome
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Credenziale non trovata o già eliminata';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassCredenziali_del]
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
			@IdFunzione = 'DWC',
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
		FROM dbo.tblDiwassCredenziali
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
					dbo.tblDiwassCredenziali c
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

			DECLARE @lock INT = (SELECT Lock
			FROM dbo.tblDiwassCredenziali
			WHERE Id = @Id);

			-- Una credenziale usata da un'azienda non si cancella: va prima tolta in Diwass > Aziende
			IF EXISTS (SELECT 1
			FROM dbo.tblDiwassCredenzialiAziende
			WHERE IdCredenziale = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La credenziale è associata ad aziende: toglierla prima in Diwass > Aziende';
				GOTO BRANCH_END;
			END

			-- ── CASO 1: credenziale attiva (Lock = 0) → soft delete ────────────────
			-- La riga hub NON viene toccata, per non perdere dati in caso di Undo.
			IF @lock = 0
			BEGIN
				BEGIN TRANSACTION;
					UPDATE dbo.tblDiwassCredenziali
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
					DELETE dbo.tblDiwassCredenziali
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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassCredenziali_del_Undo]
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

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblDiwassCredenziali i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4;

			DELETE i
			FROM dbo.tblIdLog i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;
			DECLARE @ripristinate INT = @@ROWCOUNT;

		COMMIT TRANSACTION;

		SET @returnMessage = CASE @ripristinate
			WHEN 0 THEN 'Nessuna entità da ripristinare'
			WHEN 1 THEN 'Entità ripristinata'
			ELSE FORMAT(@ripristinate, 'N0', 'it-IT') + ' entità ripristinate'
		END;

		SELECT @returnMessage AS ReturnMessage;

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Diwass > Aziende: aziende interne del dominio visibili all'utente, con la credenziale DIWASS associata (come
-- Rentri > Sedi per le credenziali RENTRI). Pagina di configurazione: nessun contesto azienda/sede
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAziende_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			s.Id,
			Nome = s.NomeCompleto,
			s.IndirizzoCompleto,
			CredenzialeNome = c.Nome,
			h.Username,
			h.ClientId,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblSessioni e
			CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
			INNER JOIN dbo.tblSedi s ON i.Id = s.Id
			LEFT JOIN dbo.tblDiwassCredenzialiAziende a ON s.Id = a.IdAziendaInterna
			LEFT JOIN dbo.tblDiwassCredenziali c ON a.IdCredenziale = c.Id
			LEFT JOIN [1_0_diwass]..tblCredenziali h ON c.IdDiwass = h.Id
		WHERE
			e.Id = @IdSessione
			AND i.IdDominio = e.IdDominio
			AND
				(
				@Search IS NULL
				OR s.NomeCompleto LIKE '%' + @Search + '%'
				OR c.Nome LIKE '%' + @Search + '%'
				)
		ORDER BY s.NomeCompleto
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAziende_get]
	@IdAziendaInterna CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdAziendaInterna = NULLIF(LTRIM(RTRIM(@IdAziendaInterna)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdAziendaInterna IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdAziendaInterna non può essere vuoto';
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
			@IdFunzione = 'DWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda interna del dominio visibile all'utente
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
			WHERE
				e.Id = @IdSessione
				AND i.Id = @IdAziendaInterna
				AND i.IdDominio = e.IdDominio
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			s.Id,
			Nome = s.NomeCompleto,
			s.IndirizzoCompleto,
			a.IdCredenziale
		FROM
			dbo.tblSedi s
			LEFT JOIN dbo.tblDiwassCredenzialiAziende a ON s.Id = a.IdAziendaInterna
		WHERE s.Id = @IdAziendaInterna;

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Credenziali DIWASS attive del dominio della sessione, da associare a un'azienda in Diwass > Aziende. La prima voce
-- "(Nessuna)" toglie l'associazione; @Search filtra per nome o utente EU Login
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAziende_get_Credenziali_SelectList]
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
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
			@IdFunzione = 'DWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Nessuna)' AS VARCHAR(200)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- credenziale selezionata: sempre presente, anche se non combacia con @Search

			SELECT
				c.Id,
				[Text] = CAST(c.Nome + ISNULL(' (' + h.Username + ')', '') AS VARCHAR(200)),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM
				dbo.tblDiwassCredenziali c
				INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
				LEFT JOIN [1_0_diwass]..tblCredenziali h ON c.IdDiwass = h.Id
			WHERE
				e.Id = @IdSessione
				AND c.Id = @IdSelected
			UNION ALL -- altre credenziali attive del dominio, con l'utente EU Login per distinguerle

			SELECT
				c.Id,
				[Text] = CAST(c.Nome + ISNULL(' (' + h.Username + ')', '') AS VARCHAR(200)),
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblDiwassCredenziali c
				INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
				LEFT JOIN [1_0_diwass]..tblCredenziali h ON c.IdDiwass = h.Id
			WHERE
				e.Id = @IdSessione
				AND c.Lock = 0
				AND c.Id <> @IdSelected
				AND
					(
					@Search IS NULL
					OR c.Nome LIKE '%' + @Search + '%'
					OR h.Username COLLATE DATABASE_DEFAULT LIKE '%' + @Search + '%'
					)
		)
		SELECT TOP 20
			Id,
			[Text],
			Selected
		FROM cte
		ORDER BY Pos, [Text]
		OPTION (RECOMPILE);

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Diwass > Aziende: associa a un'azienda interna la credenziale DIWASS con cui lavora (una credenziale del dominio può
-- servire più aziende, un'azienda ne usa al massimo una). Senza credenziale (@IdCredenziale vuoto o sedici zeri)
-- l'associazione si toglie
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAziende_upd]
	@IdAziendaInterna CHAR(16) = NULL,
	@IdCredenziale CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdAziendaInterna = NULLIF(LTRIM(RTRIM(@IdAziendaInterna)), '');
		SET @IdCredenziale = NULLIF(NULLIF(LTRIM(RTRIM(@IdCredenziale)), ''), REPLICATE('0', 16));
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdAziendaInterna IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdAziendaInterna non può essere vuoto';
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
			@IdFunzione = 'DWC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda interna del dominio visibile all'utente
		DECLARE @idDominio CHAR(16);
		SELECT @idDominio = i.IdDominio
		FROM
			dbo.tblSessioni e
			CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
		WHERE
			e.Id = @IdSessione
			AND i.Id = @IdAziendaInterna
			AND i.IdDominio = e.IdDominio;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La credenziale deve essere dello stesso dominio, attiva e già salvata nell'hub
		IF @IdCredenziale IS NOT NULL
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblDiwassCredenziali
				WHERE
					Id = @IdCredenziale
					AND IdDominio = @idDominio
					AND Lock = 0
					AND IdDiwass IS NOT NULL
			)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La credenziale selezionata non è valida';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			IF @IdCredenziale IS NULL
				DELETE dbo.tblDiwassCredenzialiAziende
				WHERE IdAziendaInterna = @IdAziendaInterna;
			ELSE IF EXISTS (SELECT 1
			FROM dbo.tblDiwassCredenzialiAziende
			WHERE IdAziendaInterna = @IdAziendaInterna)
				UPDATE dbo.tblDiwassCredenzialiAziende
				SET IdCredenziale = @IdCredenziale
				WHERE IdAziendaInterna = @IdAziendaInterna;
			ELSE
				INSERT INTO dbo.tblDiwassCredenzialiAziende (IdAziendaInterna, IdCredenziale)
				VALUES (@IdAziendaInterna, @IdCredenziale);
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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Diwass > Aziende (mai la chiave di autenticazione): righe per l'esportazione dell'elenco in Excel e in CSV
-- (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspDiwassAziende_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspDiwassAziende_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

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
			@IdFunzione = 'DWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (@MaxRighe + 1)
			[Azienda] = s.NomeCompleto,
			[Indirizzo] = s.IndirizzoCompleto,
			[Credenziale] = c.Nome,
			[Utente EU Login] = h.Username,
			[Client id] = h.ClientId
		FROM
			dbo.tblSessioni e
			CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
			INNER JOIN dbo.tblSedi s ON i.Id = s.Id
			LEFT JOIN dbo.tblDiwassCredenzialiAziende a ON s.Id = a.IdAziendaInterna
			LEFT JOIN dbo.tblDiwassCredenziali c ON a.IdCredenziale = c.Id
			LEFT JOIN [1_0_diwass]..tblCredenziali h ON c.IdDiwass = h.Id
		WHERE
			e.Id = @IdSessione
			AND i.IdDominio = e.IdDominio
			AND
				(
				@Search IS NULL
				OR s.NomeCompleto LIKE '%' + @Search + '%'
				OR c.Nome LIKE '%' + @Search + '%'
				)
		ORDER BY s.NomeCompleto
		OPTION (RECOMPILE);

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Id dell'hub della credenziale DIWASS dell'azienda interna del contesto, usata dalle pagine operative per parlare
-- con DIWASS (ricerca e lettura degli operatori). Basta la funzione DWO: non serve DWC (configurazione)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassOperatori_get_IdDiwassCredenziale]
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
			@IdFunzione = 'DWO',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16) = (SELECT IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione);
		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		-- Credenziale associata all'azienda in Diwass > Aziende
		DECLARE @idDiwass CHAR(16) = (
			SELECT c.IdDiwass
			FROM
				dbo.tblDiwassCredenzialiAziende a
				INNER JOIN dbo.tblDiwassCredenziali c ON a.IdCredenziale = c.Id
			WHERE
				a.IdAziendaInterna = @idAzienda
				AND c.Lock = 0
		);
		IF @idDiwass IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''azienda non ha una credenziale DIWASS: chiedere all''amministratore di associarla in Diwass > Aziende';
			GOTO BRANCH_END;
		END

		SELECT rtn = @idDiwass;

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Dati dell'Allegato VII da mandare all'hub DIWASS (JSON) per @Operazione: I invio, A aggiornamento, N annullamento,
-- S lettura dello stato. Per I e A controlla che il documento sia completo e restituisce in un solo messaggio tutto
-- quello che manca. La firma di chi organizza è dell'utente della sessione (nome, email) con il ruolo della scheda.
-- Restituisce rtn = JSON (assegnato a variabile, così non viene spezzato in più righe)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Invio]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Operazione CHAR(1) = NULL,
	@Motivo VARCHAR(500) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(2000) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Operazione = NULLIF(LTRIM(RTRIM(@Operazione)), '');
		SET @Motivo = dbo.ufnStringhe_get_SenzaSpazi(@Motivo, 0, 1);

		IF @Id IS NULL OR @IdSessione IS NULL OR ISNULL(@Operazione, '') NOT IN ('I', 'A', 'N', 'S')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Parametri non validi';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF IIF(@Operazione = 'S', 1, 2) > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		DECLARE @idAzienda CHAR(16);
		DECLARE @idUtente CHAR(16);
		DECLARE @stato VARCHAR(20);
		DECLARE @numero VARCHAR(50);
		DECLARE @lock TINYINT;
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@idUtente = e.IdUtente,
			@stato = a.Stato,
			@numero = a.Numero,
			@lock = a.Lock
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL OR @lock <> 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto: salvarlo prima dell''invio';
			GOTO BRANCH_END;
		END

		-- Stato ammesso per l'operazione
		IF @Operazione = 'I' AND @stato IS NOT NULL
			SET @returnMessage = 'L''Allegato VII è già stato inviato a DIWASS';
		ELSE IF @Operazione IN ('A', 'N') AND ISNULL(@stato, '') <> 'ANNOUNCED'
			SET @returnMessage = IIF(@stato IS NULL,
				'L''Allegato VII non è ancora stato inviato a DIWASS',
				'L''Allegato VII è ' + LOWER(dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(@stato)) + ' su DIWASS: non si può più ' + IIF(@Operazione = 'A', 'modificare', 'annullare'));
		ELSE IF @Operazione = 'S' AND @numero IS NULL
			SET @returnMessage = 'L''Allegato VII non è ancora stato inviato a DIWASS';
		ELSE IF @Operazione = 'N' AND @Motivo IS NULL
			SET @returnMessage = 'Indicare il motivo dell''annullamento';
		IF @returnMessage IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			GOTO BRANCH_END;
		END

		-- Credenziale DIWASS associata all'azienda in Diwass > Aziende
		DECLARE @idCredenziale CHAR(16) = (
			SELECT c.IdDiwass
			FROM
				dbo.tblDiwassCredenzialiAziende a
				INNER JOIN dbo.tblDiwassCredenziali c ON a.IdCredenziale = c.Id
			WHERE
				a.IdAziendaInterna = @idAzienda
				AND c.Lock = 0
		);
		IF @idCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''azienda non ha una credenziale DIWASS: chiedere all''amministratore di associarla in Diwass > Aziende';
			GOTO BRANCH_END;
		END

		-- Firma: utente della sessione
		DECLARE @firmaNome VARCHAR(100);
		DECLARE @firmaEmail VARCHAR(100);
		SELECT
			@firmaNome = NULLIF(LTRIM(RTRIM(ISNULL(Nome, '') + ' ' + ISNULL(Cognome, ''))), ''),
			@firmaEmail = Email
		FROM dbo.tblUtenti
		WHERE Id = @idUtente;

		-- Completezza (invio e aggiornamento)
		IF @Operazione IN ('I', 'A')
		BEGIN
			DECLARE @mancanti TABLE (Pos INT IDENTITY(1, 1), Testo NVARCHAR(200));

			INSERT INTO @mancanti (Testo)
			SELECT x.Testo
			FROM
				dbo.tblDiwassAllegatiVii a
				CROSS APPLY (
					VALUES
						(IIF(a.DataSpedizione IS NULL, N'data della spedizione', NULL)),
						(IIF(ISNULL(a.Quantita, 0) <= 0, N'quantità', NULL)),
						(IIF(a.LuogoPartenza IS NULL, N'luogo di partenza', NULL)),
						(IIF(a.ResponsabileNome IS NULL OR a.ResponsabileTelefono IS NULL OR a.ResponsabileEmail IS NULL, N'nome, telefono ed email del responsabile del luogo di partenza', NULL)),
						(IIF(a.IdEer IS NULL, N'codice EER', NULL)),
						(IIF(a.Codice IS NULL, N'codice internazionale del rifiuto (Basel, OCSE)', NULL)),
						(IIF(a.Descrizione IS NULL, N'descrizione usuale del rifiuto', NULL)),
						(IIF(a.IdAttivita IS NULL, N'operazione di recupero', NULL)),
						(IIF(a.IdNazioneSpedizione IS NULL OR a.IdNazioneDestinazione IS NULL, N'paesi di spedizione e di destinazione', NULL)),
						(IIF(a.FirmaRuolo IS NULL, N'ruolo di chi firma', NULL)),
						(IIF(@firmaNome IS NULL OR @firmaEmail IS NULL, N'nome ed email dell''utente che firma (Impostazioni > Utenti)', NULL))
				) x (Testo)
			WHERE
				a.Id = @Id
				AND x.Testo IS NOT NULL;

			-- Operazione di recupero: deve essere una R (spedizioni della lista verde)
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblDiwassAllegatiVii a
					INNER JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento r ON a.IdAttivita = r.Id
				WHERE
					a.Id = @Id
					AND r.Codice NOT LIKE 'R%'
			)
				INSERT INTO @mancanti (Testo) VALUES (N'operazione di recupero (R1-R13), non di smaltimento');

			-- Soggetti obbligatori
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassOperatori
			WHERE
				Id = @idAzienda
				AND Stato IN ('NEW', 'VALID')
			)
				INSERT INTO @mancanti (Testo) VALUES (N'collegamento a DIWASS dell''azienda che organizza (Diwass > Operatori)');
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassAllegatiViiSoggetti
			WHERE
				Id = @Id
				AND Ruolo = 'D'
			)
				INSERT INTO @mancanti (Testo) VALUES (N'destinatario');
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassAllegatiViiSoggetti
			WHERE
				Id = @Id
				AND Ruolo = 'I'
			)
				INSERT INTO @mancanti (Testo) VALUES (N'impianto di recupero o laboratorio');
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassAllegatiViiSoggetti
			WHERE
				Id = @Id
				AND Ruolo = 'T'
			)
				INSERT INTO @mancanti (Testo) VALUES (N'almeno un trasportatore');

			INSERT INTO @mancanti (Testo)
			SELECT N'contatto (nome, telefono ed email) di ' + s.NomeCompleto
			FROM
				dbo.tblDiwassAllegatiViiSoggetti x
				INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
			WHERE
				x.Id = @Id
				AND
					(
					x.ContattoNome IS NULL
					OR x.ContattoTelefono IS NULL
					OR x.ContattoEmail IS NULL
					);

			INSERT INTO @mancanti (Testo)
			SELECT N'collegamento a DIWASS di ' + s.NomeCompleto
			FROM
				dbo.tblDiwassAllegatiViiSoggetti x
				INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
				LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id AND o.Stato IN ('NEW', 'VALID')
			WHERE
				x.Id = @Id
				AND x.Ruolo <> 'O'
				AND o.Id IS NULL;

			IF EXISTS (SELECT 1
			FROM dbo.tblDiwassAllegatiViiSoggetti
			WHERE
				Id = @Id
				AND Ruolo = 'P'
			)
				AND EXISTS (
					SELECT 1
					FROM dbo.tblDiwassAllegatiVii
					WHERE
						Id = @Id
						AND
							(
							ProduttoreFirmaNome IS NULL
							OR ProduttoreFirmaRuolo IS NULL
							OR ProduttoreFirmaData IS NULL
							)
				)
				INSERT INTO @mancanti (Testo) VALUES (N'conferma del produttore (nome, ruolo e data)');

			IF EXISTS (SELECT 1
			FROM @mancanti)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = LEFT(N'Per inviare l''Allegato VII a DIWASS completare: '
					+ STUFF((SELECT N'; ' + Testo
					FROM @mancanti ORDER BY Pos FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N''), 2000);
				GOTO BRANCH_END;
			END
		END

		DECLARE @json NVARCHAR(MAX) = (
			SELECT
				idCredenziale = @idCredenziale,
				numero = a.Numero,
				arrangerIsProducer = CAST(IIF(EXISTS (SELECT 1
				FROM dbo.tblDiwassAllegatiViiSoggetti p
				WHERE
					p.Id = a.Id
					AND p.Ruolo = 'P'
				), 0, 1) AS BIT),
				tipoDestinazione = a.TipoDestinazione,
				dataSpedizione = a.DataSpedizione,
				quantita = a.Quantita,
				unitaQuantita = a.UnitaQuantita,
				contenitore = a.Contenitore,
				luogoPartenza = a.LuogoPartenza,
				responsabileNome = a.ResponsabileNome,
				responsabileTelefono = a.ResponsabileTelefono,
				responsabileEmail = a.ResponsabileEmail,
				-- Elenco europeo dei rifiuti nel formato DIWASS ("15 01 01", con l'asterisco se pericoloso)
				eer = LEFT(a.IdEer, 2) + ' ' + SUBSTRING(a.IdEer, 3, 2) + ' ' + RIGHT(a.IdEer, 2) + IIF(e.Pericoloso = 1, '*', ''),
				listaCodice = a.ListaCodice,
				codice = a.Codice,
				descrizione = a.Descrizione,
				operazione = r.Codice,
				codiceDoganale = a.CodiceDoganale,
				paeseSpedizione = a.IdNazioneSpedizione,
				paeseDestinazione = a.IdNazioneDestinazione,
				paeseTransito1 = a.IdNazioneTransito1,
				paeseTransito2 = a.IdNazioneTransito2,
				firmaNome = @firmaNome,
				firmaRuolo = a.FirmaRuolo,
				firmaEmail = @firmaEmail,
				produttoreFirmaNome = a.ProduttoreFirmaNome,
				produttoreFirmaRuolo = a.ProduttoreFirmaRuolo,
				produttoreFirmaData = a.ProduttoreFirmaData,
				motivo = @Motivo,
				soggetti = (
					SELECT
						ruolo = x.Ruolo,
						pos = x.Pos,
						operatorInternalId = o.OperatorInternalId,
						partyUuid = x.PartyUuid,
						contattoNome = x.ContattoNome,
						contattoTelefono = x.ContattoTelefono,
						contattoEmail = x.ContattoEmail,
						mezzoTrasporto = x.MezzoTrasporto,
						impiantoIntermedio = ISNULL(x.ImpiantoIntermedio, 0),
						nomeRiservato = ISNULL(x.NomeRiservato, 0),
						motivoRiservatezza = x.MotivoRiservatezza
					FROM
						dbo.tblDiwassAllegatiViiSoggetti x
						LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id
					WHERE x.Id = a.Id
					ORDER BY x.Ruolo, x.Pos
					FOR JSON PATH
				)
			FROM
				dbo.tblDiwassAllegatiVii a
				LEFT JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
				LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento r ON a.IdAttivita = r.Id
			WHERE a.Id = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

		SELECT rtn = @json;

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Nuovo Allegato VII (bozza, Lock = 2 finché non si salva) dell'azienda del contesto, che è chi organizza la
-- spedizione. Con @IdRegistrazione (Trasporto transfrontaliero = Allegato VII) lo compila dalla registrazione e dal
-- suo movimento: soggetti collegati a DIWASS (la sede o, se non collegata, la sua azienda), quantità in tonnellate o
-- m³, data, EER, operazione R, codice internazionale (ultimo usato dall'azienda per l'EER o il primo suggerito),
-- paesi e luogo di partenza. Con @IdCopia (Copia/incolla) copia un Allegato VII salvato della stessa azienda, senza
-- registrazione, data di spedizione, dati dell'invio, firma e data della conferma del produttore.
-- Restituisce Id e gli avvisi da mostrare (sedi sostituite o non collegate)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_ins]
	@IdSessione CHAR(16) = NULL,
	@IdRegistrazione CHAR(16) = NULL,
	@IdCopia CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');
		SET @IdCopia = NULLIF(LTRIM(RTRIM(@IdCopia)), '');

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
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		DECLARE @idUtente CHAR(16);
		SELECT
			@idAzienda = IdAzienda,
			@idUtente = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda che organizza la spedizione';
			GOTO BRANCH_END;
		END

		-- Copia/incolla: solo un Allegato VII salvato dell'azienda del contesto, anche inviato o annullato
		IF @IdCopia IS NOT NULL
		BEGIN
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassAllegatiVii
			WHERE
				Id = @IdCopia
				AND IdAziendaInterna = @idAzienda
				AND Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Allegato VII da copiare non trovato nell''azienda del contesto';
				GOTO BRANCH_END;
			END

			-- uspId_get FUORI dalla transazione
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

			BEGIN TRANSACTION;
				INSERT INTO dbo.tblDiwassAllegatiVii (
					Id, IdAziendaInterna, TipoDestinazione, Quantita, UnitaQuantita, Contenitore, LuogoPartenza,
					ResponsabileNome, ResponsabileTelefono, ResponsabileEmail, IdEer, Descrizione, CodiceDoganale,
					IdNazioneSpedizione, IdNazioneDestinazione, IdNazioneTransito1, IdNazioneTransito2, IdAttivita,
					ListaCodice, Codice, FirmaRuolo, ProduttoreFirmaNome, ProduttoreFirmaRuolo, Note, Lock)
				SELECT
					@returnId, a.IdAziendaInterna, a.TipoDestinazione, a.Quantita, a.UnitaQuantita, a.Contenitore, a.LuogoPartenza,
					a.ResponsabileNome, a.ResponsabileTelefono, a.ResponsabileEmail, a.IdEer, a.Descrizione, a.CodiceDoganale,
					a.IdNazioneSpedizione, a.IdNazioneDestinazione, a.IdNazioneTransito1, a.IdNazioneTransito2, a.IdAttivita,
					a.ListaCodice, a.Codice, ISNULL(f.Ruolo, a.FirmaRuolo), a.ProduttoreFirmaNome, a.ProduttoreFirmaRuolo, a.Note, 2
				FROM
					dbo.tblDiwassAllegatiVii a
					LEFT JOIN dbo.tblDiwassFirmeRuoli f ON f.IdUtente = @idUtente AND f.IdAziendaInterna = a.IdAziendaInterna
				WHERE a.Id = @IdCopia;

				-- Soggetti con un PartyUuid nuovo (default della colonna)
				INSERT INTO dbo.tblDiwassAllegatiViiSoggetti (Id, Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail, MezzoTrasporto, ImpiantoIntermedio, NomeRiservato, MotivoRiservatezza)
				SELECT @returnId, Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail, MezzoTrasporto, ImpiantoIntermedio, NomeRiservato, MotivoRiservatezza
				FROM dbo.tblDiwassAllegatiViiSoggetti
				WHERE Id = @IdCopia;
			COMMIT TRANSACTION;

			SELECT
				Id = @returnId,
				Avvisi = CAST(NULL AS NVARCHAR(MAX));
			GOTO BRANCH_END;
		END

		-- Dati della registrazione e del suo movimento (solo dell'azienda del contesto e con Allegato VII)
		DECLARE @idMovimento CHAR(16);
		DECLARE @idProduttore CHAR(16);
		DECLARE @idDestinatario CHAR(16);
		DECLARE @quantita DECIMAL(18, 5);
		DECLARE @unitaQuantita CHAR(1);
		DECLARE @dataSpedizione DATE;
		DECLARE @idEer CHAR(6);
		DECLARE @descrizione VARCHAR(500);
		DECLARE @idAttivita CHAR(2);

		IF @IdRegistrazione IS NOT NULL
		BEGIN
			DECLARE @tipoTransfrontaliero CHAR(1);
			SELECT
				@idMovimento = m.Id,
				@tipoTransfrontaliero = r.IdTrasportoTransfrontalieroTipo,
				@idProduttore = m.IdSedeProduttoreDetentore,
				@idDestinatario = m.IdSedeDestinatario,
				@quantita = CASE m.IdUnitaMisura
					WHEN 'KG' THEN m.Quantita / 1000
					WHEN 'TN' THEN m.Quantita
					WHEN 'LT' THEN m.Quantita / 1000
					WHEN 'MC' THEN m.Quantita
				END,
				@unitaQuantita = CASE m.IdUnitaMisura
					WHEN 'LT' THEN 'M'
					WHEN 'MC' THEN 'M'
					ELSE 'T'
				END,
				@dataSpedizione = ISNULL(CAST(m.DataInizioTrasporto AS DATE), r.Data),
				@idEer = m.IdEer,
				@descrizione = ISNULL(m.EerDescrizione, e.Descrizione),
				@idAttivita = IIF(a.Codice LIKE 'R%', m.IdAttivita, NULL)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
				LEFT JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				LEFT JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento a ON m.IdAttivita = a.Id
			WHERE
				r.Id = @IdRegistrazione
				AND r.Lock < 2
				AND s.IdAziendaInterna = @idAzienda;

			IF @idMovimento IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Registrazione non trovata nell''azienda del contesto';
				GOTO BRANCH_END;
			END
			IF ISNULL(@tipoTransfrontaliero, '') <> 'D'
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione non ha il trasporto transfrontaliero con Allegato VII';
				GOTO BRANCH_END;
			END
		END

		-- Una registrazione ha un solo Allegato VII non annullato: se c'è già, si apre quello
		DECLARE @esistente CHAR(16) = (
			SELECT TOP 1 Id
			FROM dbo.tblDiwassAllegatiVii
			WHERE
				IdRegistrazione = @IdRegistrazione
				AND Lock = 0
				AND ISNULL(Stato, '') <> 'CANCELLED'
		);
		IF @esistente IS NOT NULL
		BEGIN
			SELECT
				Id = @esistente,
				Avvisi = N'La registrazione ha già un Allegato VII: è stato aperto quello';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		DECLARE @avvisi NVARCHAR(MAX) = N'';

		-- Soggetti da indicare: sede collegata a DIWASS o, se non collegata, la sua azienda
		DECLARE @soggetti TABLE (Ruolo CHAR(1), Pos TINYINT, IdSedeOrigine CHAR(16), Mezzo CHAR(1));
		IF @idMovimento IS NOT NULL
		BEGIN
			INSERT INTO @soggetti (Ruolo, Pos, IdSedeOrigine, Mezzo)
			VALUES ('P', 1, @idProduttore, NULL), ('D', 1, @idDestinatario, NULL), ('I', 1, @idDestinatario, NULL);

			INSERT INTO @soggetti (Ruolo, Pos, IdSedeOrigine, Mezzo)
			SELECT
				'T',
				t.Pos + 1,
				z.IdSede,
				CASE t.IdTipo
					WHEN 'T' THEN 'T'
					WHEN 'N' THEN 'S'
					ELSE 'R'
				END
			FROM
				dbo.tblRifiutiMovimentiTrasportatori t
				INNER JOIN dbo.tblRifiutiAutorizzazioni z ON t.IdAutorizzazione = z.Id
			WHERE
				t.Id = @idMovimento
				AND t.Pos BETWEEN 0 AND 2;
		END

		DECLARE @collegati TABLE (Ruolo CHAR(1), Pos TINYINT, IdSede CHAR(16), Sostituita BIT, IdSedeOrigine CHAR(16), Mezzo CHAR(1));
		INSERT INTO @collegati (Ruolo, Pos, IdSede, Sostituita, IdSedeOrigine, Mezzo)
		SELECT x.Ruolo, x.Pos, c.IdSede, c.Sostituita, x.IdSedeOrigine, x.Mezzo
		FROM
			@soggetti x
			OUTER APPLY dbo.ufnDiwassAllegatiVii_get_SedeCollegata(x.IdSedeOrigine) c
		WHERE x.IdSedeOrigine IS NOT NULL;

		-- Il produttore che coincide con chi organizza non si indica (arrangerIsProducer)
		DELETE @collegati
		WHERE
			Ruolo = 'P'
			AND IdSede = @idAzienda;

		SELECT @avvisi = @avvisi + CASE x.Ruolo
				WHEN 'P' THEN N'Produttore'
				WHEN 'D' THEN N'Destinatario'
				WHEN 'I' THEN N'Impianto'
				ELSE N'Trasportatore ' + CAST(x.Pos AS NVARCHAR(1))
			END + N': ' + s.NomeCompleto + IIF(x.IdSede IS NULL,
				N' non è collegato a DIWASS (Diwass > Operatori), indicarlo prima dell''invio. ',
				N' non è collegato a DIWASS, è indicata la sua azienda. ')
		FROM
			@collegati x
			INNER JOIN dbo.tblSedi s ON x.IdSedeOrigine = s.Id
		WHERE
			x.IdSede IS NULL
			OR x.Sostituita = 1;

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblDiwassOperatori
		WHERE
			Id = @idAzienda
			AND Stato IN ('NEW', 'VALID')
		)
			SET @avvisi = @avvisi + N'L''azienda che organizza la spedizione non è collegata a DIWASS (Diwass > Operatori). ';

		-- Codice internazionale: ultimo usato dall'azienda per l'EER, altrimenti il primo suggerito
		DECLARE @listaCodice VARCHAR(10);
		DECLARE @codice NVARCHAR(20);
		SELECT
			@listaCodice = Lista,
			@codice = Codice
		FROM dbo.tblDiwassCodiciRifiutiUsati
		WHERE
			IdAziendaInterna = @idAzienda
			AND IdEer = @idEer;
		IF @codice IS NULL
			SELECT TOP 1
				@listaCodice = Lista,
				@codice = Codice
			FROM dbo.tblDiwassCodiciRifiutiEer
			WHERE IdEer = @idEer
			ORDER BY Pos;

		-- Paesi e luogo di partenza dalle sedi del produttore (o dell'azienda) e del destinatario
		DECLARE @idSedePartenza CHAR(16) = ISNULL(@idProduttore, @idAzienda);
		DECLARE @luogoPartenza VARCHAR(300) = (SELECT LEFT(IndirizzoCompleto, 300)
		FROM dbo.tblSedi
		WHERE Id = @idSedePartenza);
		DECLARE @idNazioneSpedizione CHAR(3) = (
			SELECT TOP 1 i.IdNazione
			FROM
				dbo.tblSediIndirizzi si
				INNER JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
			WHERE si.Id = @idSedePartenza);
		DECLARE @idNazioneDestinazione CHAR(3) = (
			SELECT TOP 1 i.IdNazione
			FROM
				dbo.tblSediIndirizzi si
				INNER JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
			WHERE si.Id = @idDestinatario);
		DECLARE @interim BIT = IIF(EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiAttivitaRecuperoSmaltimento
			WHERE
				Id = @idAttivita
				AND Codice IN ('R12', 'R13')
		), 1, 0);

		BEGIN TRANSACTION;
			INSERT INTO dbo.tblDiwassAllegatiVii (
				Id, IdAziendaInterna, IdRegistrazione, TipoDestinazione, DataSpedizione, Quantita, UnitaQuantita,
				LuogoPartenza, IdEer, Descrizione, IdNazioneSpedizione, IdNazioneDestinazione, IdAttivita,
				ListaCodice, Codice, FirmaRuolo, Lock)
			SELECT
				@returnId, @idAzienda, @IdRegistrazione, 'R', @dataSpedizione, @quantita, ISNULL(@unitaQuantita, 'T'),
				@luogoPartenza, @idEer, LEFT(@descrizione, 500), @idNazioneSpedizione, @idNazioneDestinazione, @idAttivita,
				@listaCodice, @codice, f.Ruolo, 2
			FROM (SELECT x = 1) d
			LEFT JOIN dbo.tblDiwassFirmeRuoli f ON f.IdUtente = @idUtente AND f.IdAziendaInterna = @idAzienda;

			-- Chi organizza: l'azienda, con il contatto dell'utente che compila
			INSERT INTO dbo.tblDiwassAllegatiViiSoggetti (Id, Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail)
			SELECT
				@returnId,
				'O',
				1,
				@idAzienda,
			LEFT(LTRIM(RTRIM(ISNULL(u.Nome, '') + ' ' + ISNULL(u.Cognome, ''))), 100),
				c.Telefono,
				u.Email
			FROM
				dbo.tblUtenti u
				OUTER APPLY dbo.ufnDiwassAllegatiVii_get_Contatto(@idAzienda) c
			WHERE u.Id = @idUtente;

			INSERT INTO dbo.tblDiwassAllegatiViiSoggetti (Id, Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail, MezzoTrasporto, ImpiantoIntermedio, NomeRiservato)
			SELECT
				@returnId,
				x.Ruolo,
				x.Pos,
				x.IdSede,
				c.Nome,
				c.Telefono,
				c.Email,
				x.Mezzo,
				IIF(x.Ruolo = 'I', @interim, NULL),
				IIF(x.Ruolo = 'I', 0, NULL)
			FROM
				@collegati x
				OUTER APPLY dbo.ufnDiwassAllegatiVii_get_Contatto(x.IdSede) c
			WHERE x.IdSede IS NOT NULL;
		COMMIT TRANSACTION;

		SELECT
			Id = @returnId,
			Avvisi = NULLIF(LTRIM(RTRIM(@avvisi)), N'');

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva l'Allegato VII (bozza o già annunciato su DIWASS: in quel caso, se i dati cambiano, le modifiche restano da
-- inviare, DaInviare = 1; un salvataggio senza modifiche lascia DaInviare com'era).
-- @Soggetti è l'elenco JSON dei soggetti ([{ruolo, pos, idSede, contattoNome, contattoTelefono, contattoEmail,
-- mezzoTrasporto, impiantoIntermedio, nomeRiservato, motivoRiservatezza}]): sostituisce quelli salvati. I controlli di
-- completezza sono all'invio (uspDiwassAllegatiVii_get_Invio): qui solo quelli che rendono il dato incoerente
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@TipoDestinazione CHAR(1) = NULL,
	@DataSpedizione DATE = NULL,
	@Quantita DECIMAL(18, 5) = NULL,
	@UnitaQuantita CHAR(1) = NULL,
	@Contenitore VARCHAR(100) = NULL,
	@LuogoPartenza VARCHAR(300) = NULL,
	@ResponsabileNome VARCHAR(100) = NULL,
	@ResponsabileTelefono VARCHAR(50) = NULL,
	@ResponsabileEmail VARCHAR(100) = NULL,
	@IdEer CHAR(6) = NULL,
	@Descrizione VARCHAR(500) = NULL,
	@CodiceDoganale VARCHAR(50) = NULL,
	@IdNazioneSpedizione CHAR(3) = NULL,
	@IdNazioneDestinazione CHAR(3) = NULL,
	@IdNazioneTransito1 CHAR(3) = NULL,
	@IdNazioneTransito2 CHAR(3) = NULL,
	@IdAttivita CHAR(2) = NULL,
	@Codice NVARCHAR(40) = NULL,
	@FirmaRuolo VARCHAR(100) = NULL,
	@ProduttoreFirmaNome VARCHAR(100) = NULL,
	@ProduttoreFirmaRuolo VARCHAR(100) = NULL,
	@ProduttoreFirmaData DATETIME2(0) = NULL,
	@Note VARCHAR(500) = NULL,
	@Soggetti NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(400) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @TipoDestinazione = ISNULL(NULLIF(LTRIM(RTRIM(@TipoDestinazione)), ''), 'R');
		SET @UnitaQuantita = ISNULL(NULLIF(LTRIM(RTRIM(@UnitaQuantita)), ''), 'T');
		SET @Contenitore = dbo.ufnStringhe_get_SenzaSpazi(@Contenitore, 0, 1);
		SET @LuogoPartenza = dbo.ufnStringhe_get_SenzaSpazi(@LuogoPartenza, 0, 1);
		SET @ResponsabileNome = dbo.ufnStringhe_get_SenzaSpazi(@ResponsabileNome, 0, 1);
		SET @ResponsabileTelefono = dbo.ufnStringhe_get_SenzaSpazi(@ResponsabileTelefono, 0, 1);
		SET @ResponsabileEmail = dbo.ufnStringhe_get_SenzaSpazi(@ResponsabileEmail, 0, 1);
		SET @IdEer = NULLIF(NULLIF(LTRIM(RTRIM(@IdEer)), ''), '000000');
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);
		SET @CodiceDoganale = dbo.ufnStringhe_get_SenzaSpazi(@CodiceDoganale, 0, 1);
		SET @IdNazioneSpedizione = NULLIF(NULLIF(LTRIM(RTRIM(@IdNazioneSpedizione)), ''), '000');
		SET @IdNazioneDestinazione = NULLIF(NULLIF(LTRIM(RTRIM(@IdNazioneDestinazione)), ''), '000');
		SET @IdNazioneTransito1 = NULLIF(NULLIF(LTRIM(RTRIM(@IdNazioneTransito1)), ''), '000');
		SET @IdNazioneTransito2 = NULLIF(NULLIF(LTRIM(RTRIM(@IdNazioneTransito2)), ''), '000');
		SET @IdAttivita = NULLIF(NULLIF(LTRIM(RTRIM(@IdAttivita)), ''), '00');
		SET @Codice = NULLIF(LTRIM(RTRIM(@Codice)), '');
		SET @FirmaRuolo = dbo.ufnStringhe_get_SenzaSpazi(@FirmaRuolo, 0, 1);
		SET @ProduttoreFirmaNome = dbo.ufnStringhe_get_SenzaSpazi(@ProduttoreFirmaNome, 0, 1);
		SET @ProduttoreFirmaRuolo = dbo.ufnStringhe_get_SenzaSpazi(@ProduttoreFirmaRuolo, 0, 1);
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END
		IF @TipoDestinazione NOT IN ('R', 'L') OR @UnitaQuantita NOT IN ('T', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Tipo di destinazione o unità della quantità non validi';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NOT NULL AND @Quantita <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		DECLARE @idAzienda CHAR(16);
		DECLARE @stato VARCHAR(20);
		DECLARE @nazioneSpedizioneAttuale CHAR(3);
		DECLARE @nazioneDestinazioneAttuale CHAR(3);
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@stato = a.Stato,
			@nazioneSpedizioneAttuale = a.IdNazioneSpedizione,
			@nazioneDestinazioneAttuale = a.IdNazioneDestinazione
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND a.Lock <= 2
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END
		IF @stato IS NOT NULL AND @stato <> 'ANNOUNCED'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''Allegato VII è ' + LOWER(dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(@stato)) + ' su DIWASS: non si può più modificare';
			GOTO BRANCH_END;
		END
		-- Su DIWASS i paesi coinvolti non si cambiano dopo l'annuncio
		IF @stato = 'ANNOUNCED'
			AND (ISNULL(@IdNazioneSpedizione, '') <> ISNULL(@nazioneSpedizioneAttuale, '')
				OR ISNULL(@IdNazioneDestinazione, '') <> ISNULL(@nazioneDestinazioneAttuale, ''))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Dopo l''invio a DIWASS i paesi di spedizione e di destinazione non si possono cambiare';
			GOTO BRANCH_END;
		END

		-- Codice internazionale nel formato "lista|codice" della select
		DECLARE @listaCodice VARCHAR(10) = NULL;
		DECLARE @codiceRifiuto NVARCHAR(20) = NULL;
		IF @Codice IS NOT NULL
		BEGIN
			SET @listaCodice = LEFT(@Codice, CHARINDEX('|', @Codice + '|') - 1);
			SET @codiceRifiuto = NULLIF(SUBSTRING(@Codice, CHARINDEX('|', @Codice + '|') + 1, 20), '');
			IF NOT EXISTS (SELECT 1
			FROM dbo.tblDiwassCodiciRifiuti
			WHERE
				Lista = @listaCodice
				AND Codice = @codiceRifiuto
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Codice internazionale del rifiuto non valido';
				GOTO BRANCH_END;
			END
		END

		-- Soggetti
		DECLARE @elenco TABLE (
			Ruolo CHAR(1) NOT NULL,
			Pos TINYINT NOT NULL,
			IdSede CHAR(16) NULL,
			ContattoNome VARCHAR(100) NULL,
			ContattoTelefono VARCHAR(50) NULL,
			ContattoEmail VARCHAR(100) NULL,
			MezzoTrasporto CHAR(1) NULL,
			ImpiantoIntermedio BIT NULL,
			NomeRiservato BIT NULL,
			MotivoRiservatezza VARCHAR(500) NULL,
			PRIMARY KEY (Ruolo, Pos)
		);
		INSERT INTO @elenco (Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail, MezzoTrasporto, ImpiantoIntermedio, NomeRiservato, MotivoRiservatezza)
		SELECT
			j.ruolo,
			j.pos,
			NULLIF(NULLIF(LTRIM(RTRIM(j.idSede)), ''), REPLICATE('0', 16)),
			NULLIF(LTRIM(RTRIM(j.contattoNome)), ''),
			NULLIF(LTRIM(RTRIM(j.contattoTelefono)), ''),
			NULLIF(LTRIM(RTRIM(j.contattoEmail)), ''),
			NULLIF(LTRIM(RTRIM(j.mezzoTrasporto)), ''),
			j.impiantoIntermedio,
			j.nomeRiservato,
			NULLIF(LTRIM(RTRIM(j.motivoRiservatezza)), '')
		FROM OPENJSON(ISNULL(@Soggetti, N'[]'))
		WITH (
			ruolo CHAR(1),
			pos TINYINT,
			idSede CHAR(16),
			contattoNome VARCHAR(100),
			contattoTelefono VARCHAR(50),
			contattoEmail VARCHAR(100),
			mezzoTrasporto CHAR(1),
			impiantoIntermedio BIT,
			nomeRiservato BIT,
			motivoRiservatezza VARCHAR(500)
		) j;

		-- Le righe senza sede (casella lasciata su "Selezionare") non si salvano
		DELETE @elenco
		WHERE IdSede IS NULL;

		IF EXISTS (SELECT 1
		FROM @elenco
		WHERE
			Ruolo NOT IN ('O', 'P', 'D', 'I', 'T')
			OR Pos NOT BETWEEN 1 AND 3
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ruolo o posizione dei soggetti non validi';
			GOTO BRANCH_END;
		END
		IF EXISTS (SELECT 1
		FROM @elenco
		WHERE
			Ruolo = 'T'
			AND ISNULL(MezzoTrasporto, '') NOT IN ('R', 'T', 'S', 'A', 'W')
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il mezzo di trasporto di ogni trasportatore';
			GOTO BRANCH_END;
		END

		-- Chi organizza è sempre l'azienda dell'Allegato VII
		DELETE @elenco
		WHERE
			Ruolo = 'O'
			AND IdSede <> @idAzienda;
		IF NOT EXISTS (SELECT 1
		FROM @elenco
		WHERE Ruolo = 'O')
			INSERT INTO @elenco (Ruolo, Pos, IdSede)
			VALUES ('O', 1, @idAzienda);

		-- Ogni soggetto deve essere visibile nel contesto e collegato a DIWASS con il ruolo WSR nuovo o valido
		DECLARE @nonCollegato VARCHAR(200) = (
			SELECT TOP 1 s.NomeCompleto
			FROM
				@elenco x
				INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
				LEFT JOIN dbo.tblDiwassOperatori o ON x.IdSede = o.Id AND o.Stato IN ('NEW', 'VALID')
				LEFT JOIN dbo.ufnDiwassOperatori_get_SediBySessione_List(@IdSessione) v ON x.IdSede = v.Id
			WHERE
				x.Ruolo <> 'O'
				AND
					(
					o.Id IS NULL
					OR v.Id IS NULL
					)
		);
		IF @nonCollegato IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il soggetto ' + @nonCollegato + ' non è collegato a DIWASS (Diwass > Operatori)';
			GOTO BRANCH_END;
		END
		IF EXISTS (SELECT 1
		FROM @elenco
		WHERE
			Ruolo = 'I'
			AND NomeRiservato = 1
			AND MotivoRiservatezza IS NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare perché il nome dell''impianto è riservato';
			GOTO BRANCH_END;
		END

		-- Dati prima del salvataggio: su un documento annunciato le modifiche restano da inviare solo se qualcosa cambia
		DECLARE @prima NVARCHAR(MAX) = (
			SELECT
				a.TipoDestinazione, a.DataSpedizione, a.Quantita, a.UnitaQuantita, a.Contenitore, a.LuogoPartenza,
				a.ResponsabileNome, a.ResponsabileTelefono, a.ResponsabileEmail, a.IdEer, a.Descrizione, a.CodiceDoganale,
				a.IdNazioneSpedizione, a.IdNazioneDestinazione, a.IdNazioneTransito1, a.IdNazioneTransito2, a.IdAttivita,
				a.ListaCodice, a.Codice, a.FirmaRuolo, a.ProduttoreFirmaNome, a.ProduttoreFirmaRuolo, a.ProduttoreFirmaData, a.Note,
				Soggetti = (
					SELECT x.Ruolo, x.Pos, x.IdSede, x.ContattoNome, x.ContattoTelefono, x.ContattoEmail, x.MezzoTrasporto, x.ImpiantoIntermedio, x.NomeRiservato, x.MotivoRiservatezza
					FROM dbo.tblDiwassAllegatiViiSoggetti x
					WHERE x.Id = a.Id
					ORDER BY x.Ruolo, x.Pos
					FOR JSON PATH)
			FROM dbo.tblDiwassAllegatiVii a
			WHERE a.Id = @Id FOR JSON PATH, INCLUDE_NULL_VALUES);

		BEGIN TRANSACTION;
			UPDATE dbo.tblDiwassAllegatiVii
			SET
				TipoDestinazione = @TipoDestinazione,
				DataSpedizione = @DataSpedizione,
				Quantita = @Quantita,
				UnitaQuantita = @UnitaQuantita,
				Contenitore = @Contenitore,
				LuogoPartenza = @LuogoPartenza,
				ResponsabileNome = @ResponsabileNome,
				ResponsabileTelefono = @ResponsabileTelefono,
				ResponsabileEmail = @ResponsabileEmail,
				IdEer = @IdEer,
				Descrizione = @Descrizione,
				CodiceDoganale = @CodiceDoganale,
				IdNazioneSpedizione = @IdNazioneSpedizione,
				IdNazioneDestinazione = @IdNazioneDestinazione,
				IdNazioneTransito1 = @IdNazioneTransito1,
				IdNazioneTransito2 = @IdNazioneTransito2,
				IdAttivita = @IdAttivita,
				ListaCodice = @listaCodice,
				Codice = @codiceRifiuto,
				FirmaRuolo = @FirmaRuolo,
				ProduttoreFirmaNome = @ProduttoreFirmaNome,
				ProduttoreFirmaRuolo = @ProduttoreFirmaRuolo,
				ProduttoreFirmaData = @ProduttoreFirmaData,
				Note = @Note,
				DaInviare = IIF(@stato = 'ANNOUNCED', DaInviare, NULL),
				Lock = 0
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Allegato VII non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			-- Soggetti: l'identificativo del soggetto nel documento (PartyUuid) resta finché non cambia la sede
			DELETE x
			FROM dbo.tblDiwassAllegatiViiSoggetti x
			WHERE
				x.Id = @Id
				AND NOT EXISTS ( SELECT 1 FROM @elenco n WHERE n.Ruolo = x.Ruolo AND n.Pos = x.Pos AND n.IdSede = x.IdSede );

			UPDATE x
			SET
				ContattoNome = n.ContattoNome,
				ContattoTelefono = n.ContattoTelefono,
				ContattoEmail = n.ContattoEmail,
				MezzoTrasporto = n.MezzoTrasporto,
				ImpiantoIntermedio = n.ImpiantoIntermedio,
				NomeRiservato = n.NomeRiservato,
				MotivoRiservatezza = n.MotivoRiservatezza
			FROM
				dbo.tblDiwassAllegatiViiSoggetti x
				INNER JOIN @elenco n ON x.Ruolo = n.Ruolo AND x.Pos = n.Pos AND x.IdSede = n.IdSede
			WHERE x.Id = @Id;

			INSERT INTO dbo.tblDiwassAllegatiViiSoggetti (Id, Ruolo, Pos, IdSede, ContattoNome, ContattoTelefono, ContattoEmail, MezzoTrasporto, ImpiantoIntermedio, NomeRiservato, MotivoRiservatezza)
			SELECT @Id, n.Ruolo, n.Pos, n.IdSede, n.ContattoNome, n.ContattoTelefono, n.ContattoEmail, n.MezzoTrasporto, n.ImpiantoIntermedio, n.NomeRiservato, n.MotivoRiservatezza
			FROM @elenco n
			WHERE NOT EXISTS ( SELECT 1 FROM dbo.tblDiwassAllegatiViiSoggetti x WHERE x.Id = @Id AND x.Ruolo = n.Ruolo AND x.Pos = n.Pos );

			IF @stato = 'ANNOUNCED'
			BEGIN
				DECLARE @dopo NVARCHAR(MAX) = (
					SELECT
						a.TipoDestinazione, a.DataSpedizione, a.Quantita, a.UnitaQuantita, a.Contenitore, a.LuogoPartenza,
						a.ResponsabileNome, a.ResponsabileTelefono, a.ResponsabileEmail, a.IdEer, a.Descrizione, a.CodiceDoganale,
						a.IdNazioneSpedizione, a.IdNazioneDestinazione, a.IdNazioneTransito1, a.IdNazioneTransito2, a.IdAttivita,
						a.ListaCodice, a.Codice, a.FirmaRuolo, a.ProduttoreFirmaNome, a.ProduttoreFirmaRuolo, a.ProduttoreFirmaData, a.Note,
						Soggetti = (
							SELECT x.Ruolo, x.Pos, x.IdSede, x.ContattoNome, x.ContattoTelefono, x.ContattoEmail, x.MezzoTrasporto, x.ImpiantoIntermedio, x.NomeRiservato, x.MotivoRiservatezza
							FROM dbo.tblDiwassAllegatiViiSoggetti x
							WHERE x.Id = a.Id
							ORDER BY x.Ruolo, x.Pos
							FOR JSON PATH)
					FROM dbo.tblDiwassAllegatiVii a
					WHERE a.Id = @Id FOR JSON PATH, INCLUDE_NULL_VALUES);

				-- Confronto esatto (anche maiuscole e minuscole)
				IF @dopo COLLATE Latin1_General_BIN2 <> @prima COLLATE Latin1_General_BIN2
					UPDATE dbo.tblDiwassAllegatiVii
					SET DaInviare = 1
					WHERE Id = @Id;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_SedeInternaCascade
    @IdSede   CHAR(16)    = NULL,
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSede   = NULLIF(LTRIM(RTRIM(@IdSede)),   '');
        SET @Conferma = NULLIF(LTRIM(RTRIM(@Conferma)), '');

        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @IdSede AND InternaEsterna = 'I')
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La sede indicata non esiste o non è una sede interna';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- Sede di partenza + tutte le sotto-sedi collegate (tblSedi.IdParent, tblSedi.IdAziendaInterna,
        -- tblSediEsterne.IdSedeInterna), a qualunque profondità. Ciclo con deduplica esplicita anziché
        -- CTE ricorsiva: le tre relazioni unite possono formare cicli sui dati reali, e una CTE
        -- ricorsiva pura non deduplica tra un livello e l'altro, rischiando MAXRECURSION anche in
        -- assenza di un vero ciclo logico.
        -- COLLATE DATABASE_DEFAULT esplicito: senza, la colonna erediterebbe la collation di tempdb
        -- (non convertita insieme al DB, vedi project_collation_conversion), in conflitto con le
        -- colonne CHAR(16) del database nei confronti/JOIN sottostanti.
        CREATE TABLE #Sedi (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
        INSERT INTO #Sedi (Id) VALUES (@IdSede);

        DECLARE @nuoveRighe INT = 1;
        WHILE @nuoveRighe > 0
        BEGIN
            INSERT INTO #Sedi (Id)
            SELECT DISTINCT x.Id
            FROM (
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdParent = c.Id
                UNION
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdAziendaInterna = c.Id
                UNION
                SELECT se.Id FROM dbo.tblSediEsterne se INNER JOIN #Sedi c ON se.IdSedeInterna = c.Id
            ) x
            WHERE NOT EXISTS (SELECT 1 FROM #Sedi t WHERE t.Id = x.Id);

            SET @nuoveRighe = @@ROWCOUNT;
        END

        DECLARE @totaleSedi INT = (SELECT COUNT(*) FROM #Sedi);

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui)
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #Etichette FROM dbo.tblEtichette WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Calendari FROM dbo.tblCalendari WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Eventi FROM dbo.tblEventi WHERE IdCalendario IN (SELECT Id FROM #Calendari);
        SELECT Id INTO #Tipi FROM dbo.tblTipi WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #TipiProprieta FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #Tipi);
        SELECT Id INTO #Persone FROM dbo.tblPersone WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Oggetti FROM dbo.tblOggetti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Gestione EoW: lotti/allocazioni/magazzini specifici EoW di proprietà della sede (solo sedi
        -- interne, IdSede diretto su tutte e tre le tabelle) - vedi project_eow_module_design in
        -- memoria persistente.
        SELECT Id INTO #EoWLotti FROM dbo.tblEoWLotti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #EoWAllocazioni FROM dbo.tblEoWAllocazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #EoWMagazzini FROM dbo.tblEoWMagazzini WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Modulo Magazzino: Articoli/Movimenti hanno IdSede = Azienda; Lotti hanno IdSede = sede
        -- operativa (può essere una sede figlia diversa dall'Azienda) - vedi project_magazzino
        -- in memoria persistente.
        SELECT Id INTO #MagArticoli FROM dbo.tblMagazziniArticoli WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #MagLotti FROM dbo.tblMagazziniLotti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #MagMovimenti FROM dbo.tblMagazziniMovimenti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Anagrafica estesa e Fatturazione: schede dell'azienda (o sul soggetto, se nella cascata),
        -- banche/casse e aliquote IVA proprie dell'azienda
        SELECT Id INTO #ClientiFornitori FROM dbo.tblClientiFornitori
        WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi) OR IdSede IN (SELECT Id FROM #Sedi);
        -- Schede amministratore dell'azienda (o su un soggetto della cascata)
        SELECT Id INTO #Amministratori FROM dbo.tblAmministratori
        WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi) OR IdSede IN (SELECT Id FROM #Sedi);
        -- Fatture dell'azienda (o di una scheda della cascata) e conti dell'azienda
        SELECT Id INTO #Fatture FROM dbo.tblFatture
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);
        SELECT Id INTO #FattureConti FROM dbo.tblFattureConti WHERE IdSede IN (SELECT Id FROM #Sedi);        SELECT Id INTO #BancheCasse FROM dbo.tblBancheCasse WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #AliquoteIva FROM dbo.tblAliquoteIva WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Dichiarazioni MUD dell'azienda o che citano una sede della cascata
        SELECT Id INTO #RifiutiMud FROM dbo.tblRifiutiMud
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdSedeLegale IN (SELECT Id FROM #Sedi) OR IdSedeUnitaLocale IN (SELECT Id FROM #Sedi);

        -- tblSedi/tblPersone/tblOggetti sono sottotipi a chiave condivisa di tblOsepe (stesso Id)
        SELECT Id INTO #OsepeIds FROM (
            SELECT Id FROM #Sedi
            UNION
            SELECT Id FROM #Persone
            UNION
            SELECT Id FROM #Oggetti
        ) x;

        SELECT Id INTO #RifiutiRegistri FROM dbo.tblRifiutiRegistri WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiAutorizzazioni FROM dbo.tblRifiutiAutorizzazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblRifiutiLimiti.IdSede è NOT NULL (proprietà della sede) e IdRegistro è nullable (scoping
        -- opzionale a un registro specifico della stessa sede) - entrambi i rami coperti per sicurezza.
        SELECT Id INTO #RifiutiLimiti FROM dbo.tblRifiutiLimiti
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);


        SELECT Id INTO #RifiutiMovimenti
        FROM dbo.tblRifiutiMovimenti
        WHERE IdSedeProduttoreDetentore IN (SELECT Id FROM #Sedi)
           OR IdSedeDestinatario        IN (SELECT Id FROM #Sedi)
           OR IdSedeTrasportatore1      IN (SELECT Id FROM #Sedi)
           OR IdSedeIntermediario1      IN (SELECT Id FROM #Sedi)
           OR IdRegistro                IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        SELECT Id INTO #Scadenze
        FROM dbo.tblScadenze
        WHERE IdEvento IN (SELECT Id FROM #Eventi)
           OR IdTipo   IN (SELECT Id FROM #Tipi);

        SELECT Id INTO #Servizi
        FROM dbo.tblServizi
        WHERE IdEvento      IN (SELECT Id FROM #Eventi)
           OR IdRichiedente IN (SELECT Id FROM #Sedi)
           OR IdTipo        IN (SELECT Id FROM #Tipi);

        -- tblAreeSediInterne/tblAreeOsepe/tblUtentiSediInterne sono giunzioni a chiave composita
        -- verso risorse condivise a livello di Dominio (tblAree, tblUtenti), non di proprietà della
        -- sede: si cancellano solo le righe di giunzione, mai tblAree/tblUtenti stesse.
        SELECT Id, IdSede  INTO #AreeSediInterne FROM dbo.tblAreeSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id, IdOsepe INTO #AreeOsepe       FROM dbo.tblAreeOsepe       WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

        -- Fatturazione: righe e rate delle fatture della cascata e pagamenti che potrebbero essere
        -- cancellati (quelli dell'azienda o delle sue banche e casse, e quelli che coprono rate di
        -- queste fatture), raccolti qui per la pulizia finale degli Id. Un pagamento che copre anche
        -- rate di altre fatture non viene cancellato: la pulizia toglie solo gli Id dei pagamenti
        -- che alla fine non esistono più
        SELECT Id INTO #FattureRighe FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #FattureRate FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #PagamentiCandidati FROM (
            SELECT Id FROM dbo.tblPagamenti
            WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi)
            UNION
            SELECT rp.IdPagamento FROM dbo.tblFattureRatePagamenti rp
            WHERE rp.IdRata IN (SELECT Id FROM #FattureRate)
        ) x;

        -- Offerte e contratti: importi (con le righe) e offerte o contratti dell'azienda, o di una
        -- scheda cliente della cascata
        SELECT Id INTO #Importi FROM dbo.tblImporti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #ImportiRighe FROM dbo.tblImportiRighe WHERE IdImporto IN (SELECT Id FROM #Importi);
        SELECT Id INTO #OfferteContratti FROM dbo.tblOfferteContratti
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            -- Offerte e contratti, per primi: referenziano fatture, schede cliente, conti, aliquote,
            -- etichette, tipi e sedi cancellati più sotto. I documenti fatturabili (registrazioni,
            -- movimenti di magazzino, servizi) hanno lo stesso Id del documento
            DELETE FROM dbo.tblFattureDocumenti
            WHERE
                Id IN (SELECT Id FROM #RifiutiRegistrazioni)
                OR Id IN (SELECT Id FROM #MagMovimenti)
                OR Id IN (SELECT Id FROM #Servizi)
                OR IdFattura IN (SELECT Id FROM #Fatture)
                OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori)
                OR IdImporto IN (SELECT Id FROM #Importi)
                OR IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContrattiImporti
            WHERE IdOffertaContratto IN (SELECT Id FROM #OfferteContratti) OR IdImporto IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblOfferteContratti WHERE Id IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblImportiRigheDettagli WHERE Id IN (SELECT Id FROM #ImportiRighe);
            DELETE FROM dbo.tblImportiRighe WHERE Id IN (SELECT Id FROM #ImportiRighe);
            DELETE FROM dbo.tblImportiRifiuti WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImportiMagazzino WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImportiServizi WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImporti WHERE Id IN (SELECT Id FROM #Importi);
            -- Importi di ALTRE aziende che citano una sede, un'etichetta, un tipo, un conto o
            -- un'aliquota della cascata (non previsto dalle regole): perdono solo il collegamento
            UPDATE dbo.tblImportiRifiuti SET IdProduttoreParent = NULL WHERE IdProduttoreParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdProduttore = NULL WHERE IdProduttore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdTrasportatore = NULL WHERE IdTrasportatore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdIntermediario = NULL WHERE IdIntermediario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiMagazzino SET IdSedePartenza = NULL WHERE IdSedePartenza IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatarioParent = NULL WHERE IdDestinatarioParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdRichiedenteParent = NULL WHERE IdRichiedenteParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdRichiedente = NULL WHERE IdRichiedente IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdSedeInterna = NULL WHERE IdSedeInterna IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdTipo = NULL WHERE IdTipo IN (SELECT Id FROM #Tipi);
            -- Righe di listino di ALTRE aziende su un articolo della cascata (non previsto): perdono l'articolo
            DELETE FROM dbo.tblImportiRigheMagazzino WHERE IdArticolo IN (SELECT Id FROM #MagArticoli);
            -- Righe di listino di ALTRE aziende su una persona o un oggetto della cascata (condivisi): perdono la risorsa
            DELETE FROM dbo.tblImportiRigheServizi WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);
            UPDATE dbo.tblImportiRigheDettagli SET IdConto = NULL WHERE IdConto IN (SELECT Id FROM #FattureConti);
            UPDATE dbo.tblImportiRigheDettagli SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);

            DELETE FROM dbo.tblRifiutiAutorizzazioniAttivita         WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniConducenti       WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniEer              WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTarghe           WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            -- FK NO_ACTION verso tblRifiutiModelli: righe della generazione automatica dei carichi
            -- (IdModello NOT NULL, si cancellano) e movimenti creati dal modello (IdModello nullable,
            -- perdono solo il collegamento)
            DELETE ae
            FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette ae
            INNER JOIN dbo.tblRifiutiModelliRegistrazioniAuto a ON ae.Id = a.Id
            WHERE a.IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAuto WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            UPDATE dbo.tblRifiutiMovimenti SET IdModello = NULL WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            DELETE FROM dbo.tblRifiutiFormulariEtichette             WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti     WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                      WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Modulo Magazzino: cascata figlio->genitore (FK NO_ACTION, nessun ON DELETE CASCADE).
            -- Va fatta prima della Gestione EoW: le righe EoW di scarico referenziano tblEoWLotti.
            -- Relazioni carico/scarico in entrambi i versi (righe della sede, dei suoi movimenti o
            -- dei suoi lotti): FK NO_ACTION su Id e IdParent verso tblMagazziniMovimentiRighe.
            DELETE rel
            FROM dbo.tblMagazziniMovimentiRigheRelazioni rel
            INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rel.Id = r.Id OR rel.IdParent = r.Id
            WHERE r.IdSede IN (SELECT Id FROM #Sedi) OR r.IdMovimento IN (SELECT Id FROM #MagMovimenti) OR r.IdLotto IN (SELECT Id FROM #MagLotti);

            DELETE rel
            FROM dbo.tblMagazziniMovimentiRigheEoWLotti rel
            INNER JOIN dbo.tblMagazziniMovimentiRigheEoW re ON rel.Id = re.Id
            WHERE
                re.IdSede IN (SELECT Id FROM #Sedi)
                OR re.IdMovimento IN (SELECT Id FROM #MagMovimenti)
                OR re.IdLotto IN (SELECT Id FROM #EoWLotti)
                OR rel.IdLotto IN (SELECT Id FROM #EoWLotti);

            DELETE FROM dbo.tblMagazziniDdt
            WHERE
                IdSede IN (SELECT Id FROM #Sedi)
                OR IdMittente IN (SELECT Id FROM #Sedi)
                OR IdDestinatario IN (SELECT Id FROM #Sedi)
                OR IdDestinazione IN (SELECT Id FROM #Sedi)
                OR IdTrasportatore IN (SELECT Id FROM #Sedi)
                OR IdMovimento IN (SELECT Id FROM #MagMovimenti);

            DELETE FROM dbo.tblMagazziniMovimentiRighe
            WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdMovimento IN (SELECT Id FROM #MagMovimenti) OR IdLotto IN (SELECT Id FROM #MagLotti);
            DELETE FROM dbo.tblMagazziniMovimentiRigheEoW
            WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdMovimento IN (SELECT Id FROM #MagMovimenti) OR IdLotto IN (SELECT Id FROM #EoWLotti);

            DELETE FROM dbo.tblMagazziniMovimenti WHERE Id IN (SELECT Id FROM #MagMovimenti);
            DELETE FROM dbo.tblMagazziniLotti WHERE Id IN (SELECT Id FROM #MagLotti);
            DELETE FROM dbo.tblMagazziniArticoli WHERE Id IN (SELECT Id FROM #MagArticoli);

            -- Gestione EoW: va fatta prima di cancellare Registrazioni sottostanti, per rispettare
            -- la FK di tblEoWLottiRifiutiRegistrazioni.IdRegistrazione (NOT NULL, parte della PK
            -- composta con IdLotto - non azzerabile, la riga di collegamento va sempre rimossa,
            -- anche quando referenzia una Registrazione di questa sede legata a un Lotto di un'altra:
            -- stesso motivo dell'OR su #RifiutiRegistrazioni). I lotti/allocazioni EoW di questa sede
            -- vengono invece cancellati per intero (non azzerati) perché sono risorse di proprietà
            -- esclusiva della sede stessa, non condivise con altre sedi.
            DELETE FROM dbo.tblEoWLottiRifiutiRegistrazioni
            WHERE IdLotto        IN (SELECT Id FROM #EoWLotti)
               OR IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblEoWLottiAllocazioni
            WHERE IdLotto      IN (SELECT Id FROM #EoWLotti)
               OR IdAllocazione IN (SELECT Id FROM #EoWAllocazioni);
            DELETE FROM dbo.tblEoWLotti       WHERE Id IN (SELECT Id FROM #EoWLotti);
            DELETE FROM dbo.tblEoWAllocazioni WHERE Id IN (SELECT Id FROM #EoWAllocazioni);

            -- tblEoWLotti.IdMagazzino (nullable, nessun vincolo strutturale che lo leghi allo stesso
            -- IdSede del Lotto) può referenziare un Magazzino di questa sede anche da un Lotto esterno
            -- alla cascata - i Lotti di questa sede sono già stati cancellati sopra, quindi qui restano
            -- solo eventuali riferimenti esterni: azzerati, non cancellati (stessa logica "UPDATE=NULL
            -- dove possibile" delle risorse condivise più sotto).
            DECLARE @eoWLottiScollegati INT;
            UPDATE dbo.tblEoWLotti SET IdMagazzino = NULL WHERE IdMagazzino IN (SELECT Id FROM #EoWMagazzini);
            SET @eoWLottiScollegati = @@ROWCOUNT;
            DELETE FROM dbo.tblEoWMagazzini WHERE Id IN (SELECT Id FROM #EoWMagazzini);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va rimossa prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se una registrazione in cancellazione è coinvolta in una rettifica.
            DELETE FROM dbo.tblRentriRegistrazioniRettifiche
            WHERE Id          IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdRettifica IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);
            -- tblDiwassAllegatiVii.IdRegistrazione: l'Allegato VII resta, perde solo la registrazione di partenza
            UPDATE dbo.tblDiwassAllegatiVii SET IdRegistrazione = NULL WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            -- Allegati VII DIWASS delle aziende cancellate (con i soggetti), soggetti delle sedi cancellate negli altri
            -- Allegati VII, codici e ruoli di firma ricordati per le aziende
            SELECT Id INTO #DiwassAllegatiVii FROM dbo.tblDiwassAllegatiVii WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblDiwassAllegatiViiSoggetti WHERE Id IN (SELECT Id FROM #DiwassAllegatiVii) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblDiwassAllegatiVii WHERE Id IN (SELECT Id FROM #DiwassAllegatiVii);
            DELETE FROM dbo.tblDiwassCodiciRifiutiUsati WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblDiwassFirmeRuoli WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRifiutiLimiti* va rimosso prima di tblRifiutiRegistri: FK NO_ACTION su IdRegistro
            -- bloccherebbe altrimenti la cancellazione del registro sottostante.
            DELETE FROM dbo.tblRifiutiLimitiEer        WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiEtichette  WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiOperazioni WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimiti           WHERE Id IN (SELECT Id FROM #RifiutiLimiti);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL, nessun
            -- ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante fallisce per FK.
            DELETE FROM dbo.tblRentriRegistri  WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            -- Dichiarazioni MUD: registri della dichiarazione (FK su tblRifiutiMud e su
            -- tblRifiutiRegistri), poi la dichiarazione
            DELETE FROM dbo.tblRifiutiMudRegistri
            WHERE Id IN (SELECT Id FROM #RifiutiMud) OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblRifiutiMud WHERE Id IN (SELECT Id FROM #RifiutiMud);

            DELETE FROM dbo.tblRifiutiRegistri WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            DELETE FROM dbo.tblScadenzeOsepe
            WHERE Id      IN (SELECT Id FROM #Scadenze)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblScadenze WHERE Id IN (SELECT Id FROM #Scadenze);

            DELETE FROM dbo.tblServiziOsepe
            WHERE Id      IN (SELECT Id FROM #Servizi)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblServizi WHERE Id IN (SELECT Id FROM #Servizi);

            DELETE FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipi          WHERE Id IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblEventiFirme      WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiProprieta  WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiUtenti     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenzeEccezioni
            WHERE Id       IN (SELECT Id FROM #Eventi)
               OR IdEvento IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenze WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventi     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblCalendari  WHERE Id IN (SELECT Id FROM #Calendari);

            -- Risorse riutilizzabili di proprietà della sede: prima di cancellarle si liberano da
            -- eventuali riferimenti di ALTRE sedi non coinvolte nella cascata. Dove la colonna è
            -- nullable si azzera il riferimento (la riga esterna resta, perde solo il collegamento);
            -- dove è NOT NULL non è possibile azzerarla, quindi si cancella la riga di giunzione
            -- esterna stessa. Scelta esplicita dell'utente: tocca dati di altre sedi pur di
            -- garantire che Etichette/Autorizzazioni di questa sede vengano sempre rimosse.
            DECLARE @rifEsterniRimossi INT = 0;

            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneDestinatario = NULL         WHERE IdAutorizzazioneDestinatario         IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneIntermediario1 = NULL       WHERE IdAutorizzazioneIntermediario1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneProduttoreDetentore = NULL  WHERE IdAutorizzazioneProduttoreDetentore  IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore1 = NULL       WHERE IdAutorizzazioneTrasportatore1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore2 = NULL       WHERE IdAutorizzazioneTrasportatore2       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiMovimentiDestinatari   WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari  WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiProduttori    WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiFormulariEtichette     WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblEtichette             WHERE Id IN (SELECT Id FROM #Etichette);
            DELETE FROM dbo.tblRifiutiAutorizzazioni WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblPersoneRuoli WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblPersone      WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblOggetti      WHERE Id IN (SELECT Id FROM #Oggetti);

            -- Anagrafica estesa e Fatturazione: prima le schede, che referenziano banche/casse e
            -- aliquote; le schede di ALTRE aziende che usano un'aliquota o una banca di questa
            -- (non previsto dalle regole) perdono solo il collegamento
            -- Fatturazione: fatture con righe, rate e pagamenti (prima delle schede, delle banche e
            -- delle aliquote, che le fatture referenziano)
            DELETE FROM dbo.tblFattureRigheImporti WHERE Id IN (SELECT Id FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
            SELECT DISTINCT rp.IdPagamento AS Id INTO #Pagamenti
            FROM dbo.tblFattureRatePagamenti rp INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
            WHERE r.IdFattura IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFattureRatePagamenti WHERE IdRata IN (SELECT Id FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblPagamenti
            WHERE Id IN (SELECT Id FROM #Pagamenti) AND Id NOT IN (SELECT IdPagamento FROM dbo.tblFattureRatePagamenti);
            DELETE FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
            UPDATE dbo.tblFatture SET IdFatturaRiferimento = NULL WHERE IdFatturaRiferimento IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFatture WHERE Id IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblClientiFornitori WHERE Id IN (SELECT Id FROM #ClientiFornitori);
            DELETE FROM dbo.tblAmministratoriSedi
            WHERE Id IN (SELECT Id FROM #Amministratori) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblAmministratori WHERE Id IN (SELECT Id FROM #Amministratori);
            UPDATE dbo.tblClientiFornitori SET IdBancaCassa = NULL WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse);
            UPDATE dbo.tblClientiFornitori SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);
            -- Conti: le righe di ALTRE aziende che li usano (non previsto dalle regole) perdono solo il
            -- collegamento, come per banche/casse e aliquote
            UPDATE dbo.tblFattureRigheImporti SET IdConto = NULL WHERE IdConto IN (SELECT Id FROM #FattureConti);
            DELETE FROM dbo.tblFattureConti WHERE Id IN (SELECT Id FROM #FattureConti);
            DELETE FROM dbo.tblFattureDatiFiscali WHERE Id IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblFattureRigheImporti SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);
            UPDATE dbo.tblFatture SET IdBancaCassa = NULL WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse);
            DELETE FROM dbo.tblFattureRatePagamenti
            WHERE IdPagamento IN (SELECT Id FROM dbo.tblPagamenti WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi));
            DELETE FROM dbo.tblPagamenti WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi);            DELETE FROM dbo.tblBancheCasse WHERE Id IN (SELECT Id FROM #BancheCasse);
            DELETE FROM dbo.tblAliquoteIva WHERE Id IN (SELECT Id FROM #AliquoteIva);

            -- Giunzioni a chiave composita verso risorse condivise (tblAree/tblUtenti non toccate)
            DELETE asi FROM dbo.tblAreeSediInterne asi INNER JOIN #AreeSediInterne t ON t.Id = asi.Id AND t.IdSede  = asi.IdSede;
            DELETE ao  FROM dbo.tblAreeOsepe       ao  INNER JOIN #AreeOsepe       t ON t.Id = ao.Id  AND t.IdOsepe = ao.IdOsepe;
            DELETE FROM dbo.tblUtentiSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL (nessuna
            -- colonna da azzerare) - si cancella la riga di associazione, mai tblRentriCredenziali stessa.
            DELETE FROM dbo.tblRentriCredenzialiSedi WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblDiwassOperatori: collegamento della sede all'operatore DIWASS (FK su tblSedi)
            DELETE FROM dbo.tblDiwassOperatori WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediDatiEstesi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediReport WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediRecapiti  WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediEsterne   WHERE Id IN (SELECT Id FROM #Sedi);
            -- Associazione alla credenziale DIWASS prima di tblSediInterne (FK su IdAziendaInterna): la credenziale
            -- è del dominio e resta
            DELETE FROM dbo.tblDiwassCredenzialiAziende WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediInterne   WHERE Id IN (SELECT Id FROM #Sedi);

            -- Radice e sotto-sedi cancellate in un'unica istruzione set-based: i vincoli
            -- auto-referenziati IdParent/IdAziendaInterna sono verificati a fine istruzione (non
            -- riga per riga), quindi non si bloccano a vicenda anche su gerarchie a più livelli.
            DELETE FROM dbo.tblSedi WHERE Id IN (SELECT Id FROM #Sedi);

            -- tblOsepe: supertipo condiviso di Sedi/Persone/Oggetti, cancellato per ultimo
            DELETE FROM dbo.tblOsepe WHERE Id IN (SELECT Id FROM #OsepeIds);

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get), solo per le entità con Id
            -- proprio (non per le tabelle a chiave condivisa/giunzione, già coperte a monte)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #OsepeIds
                UNION SELECT Id FROM #Calendari
                UNION SELECT Id FROM #Etichette
                UNION SELECT Id FROM #Eventi
                UNION SELECT Id FROM #MagArticoli
                UNION SELECT Id FROM #MagLotti
                UNION SELECT Id FROM #MagMovimenti
                UNION SELECT Id FROM #ClientiFornitori
                UNION SELECT Id FROM #Fatture
                UNION SELECT Id FROM #FattureRighe
                UNION SELECT Id FROM #FattureRate
                UNION SELECT Id FROM #FattureConti
                UNION SELECT Id FROM #PagamentiCandidati WHERE Id NOT IN (SELECT Id FROM dbo.tblPagamenti)
                UNION SELECT Id FROM #Importi
                UNION SELECT Id FROM #ImportiRighe
                UNION SELECT Id FROM #OfferteContratti
                UNION SELECT Id FROM #Amministratori
                UNION SELECT Id FROM #BancheCasse
                UNION SELECT Id FROM #AliquoteIva
                UNION SELECT Id FROM #RifiutiMud
                UNION SELECT Id FROM #EoWLotti
                UNION SELECT Id FROM #EoWAllocazioni
                UNION SELECT Id FROM #EoWMagazzini
                UNION SELECT Id FROM #RifiutiAutorizzazioni
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiRegistri
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT Id FROM #RifiutiLimiti
                UNION SELECT Id FROM #DiwassAllegatiVii
                UNION SELECT Id FROM #Scadenze
                UNION SELECT Id FROM #Servizi
                UNION SELECT Id FROM #Tipi
                UNION SELECT Id FROM #TipiProprieta
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT('Cancellazione completata. Sedi rimosse: ', @totaleSedi, '. Riferimenti esterni azzerati/rimossi su Etichette/Autorizzazioni condivise: ', @rifEsterniRimossi, '. Lotti EoW rimossi: ', (SELECT COUNT(*) FROM #EoWLotti), ', Allocazioni EoW rimosse: ', (SELECT COUNT(*) FROM #EoWAllocazioni), ', Magazzini EoW rimossi: ', (SELECT COUNT(*) FROM #EoWMagazzini), ' (Lotti esterni scollegati: ', @eoWLottiScollegati, ')', ', Limiti rifiuti rimossi: ', (SELECT COUNT(*) FROM #RifiutiLimiti), '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
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
