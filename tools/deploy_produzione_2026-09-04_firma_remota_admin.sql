-- =====================================================================================
-- Deploy produzione 2026-09-04 (parte 3): Firma remota gestita dall'Amministratore
-- Repo: 4_0_ecomatico
--
-- Contesto: come tutte le altre funzionalità RENTRI, la firma remota va gestita
-- dall'Amministratore per conto degli utenti del dominio (non più dall'utente loggato
-- tramite il contesto registro/sede) - selezione Utente poi SedeInterna (unità locale RENTRI).
-- La chiave (IdUtente, IdCredenziale) su tblRentriFirmeCredenziali resta invariata: cambia
-- solo CHI puo' operare su quella riga (Amministratore del dominio del target, oppure
-- l'utente stesso - predisposto per un futuro self-service).
--
-- Contenuto:
--   1) DROP uspRentriRegistri_get_IdCredenziale (superata: non si passa più dal registro)
--   2) CREATE OR ALTER uspUtenti_get_ListByDominio (+Email/Nome/Cognome, per la select Utente)
--   3) CREATE OR ALTER uspRentriFirmeCredenziali_get_List (nuova: elenco SediInterne del
--      target con relativa credenziale primaria e stato firma remota)
--   4) CREATE OR ALTER uspRentriFirmeCredenziali_get / _upd_Boarding / _del (ora con
--      @IdUtente esplicito invece di risolverlo sempre dalla sessione)
--   5) CREATE OR ALTER uspRentriFirmeOperazioni_ins (idem, @IdUtente esplicito)
--
-- Eseguire con: sqlcmd -S <server> -d 4_0_ecomatico -E -f 65001 -b -i <questo file>
-- =====================================================================================


-- 1) Drop SP superata --------------------------------------------------------------
IF OBJECT_ID('dbo.uspRentriRegistri_get_IdCredenziale') IS NOT NULL
	DROP PROCEDURE dbo.uspRentriRegistri_get_IdCredenziale;
GO


-- 2) uspUtenti_get_ListByDominio ------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_get_ListByDominio]
	@IdDominio CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdDominio = NULLIF(LTRIM(RTRIM(@IdDominio)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdDominio non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @idDominioSessione CHAR(16);
		SELECT @idDominioSessione = a.IdDominio
		FROM dbo.tblSessioni s INNER JOIN dbo.tblUtenti a ON a.Id = s.IdUtente
		WHERE s.Id = @IdSessione;

		IF @IdDominio <> @idDominioSessione
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

		SELECT
			Id,
			IdRuolo,
			IdStato,
			Email,
			Nome,
			Cognome
		FROM dbo.tblUtenti
		WHERE
			IdDominio = @IdDominio
			AND Lock = 0;

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


-- 3) uspRentriFirmeCredenziali_get_List -----------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFirmeCredenziali_get_List]
	@IdSessione CHAR(16) = NULL,
	@IdUtente CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');

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

		IF NOT EXISTS (SELECT 1 FROM dbo.tblUtenti WHERE Id = @IdUtente AND Lock <= 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Utente non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			s.Id AS IdSede,
			s.NomeCompleto AS SedeNome,
			cs.IdCredenziale,
			Collegata = CASE WHEN f.IdUtente IS NOT NULL AND f.Lock = 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
			DataBoarding = CASE WHEN f.Lock = 0 THEN f.DataBoarding ELSE NULL END
		FROM
			dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) su
			INNER JOIN dbo.tblSedi s ON s.Id = su.Id
			INNER JOIN dbo.tblRentriCredenzialiSedi cs ON cs.IdSede = s.Id AND cs.Pos = 0
			INNER JOIN dbo.tblRentriCredenziali c ON c.Id = cs.IdCredenziale AND c.Lock <= 2
			LEFT JOIN dbo.tblRentriFirmeCredenziali f ON f.IdCredenziale = cs.IdCredenziale AND f.IdUtente = @IdUtente
		ORDER BY s.NomeCompleto;

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


-- 4a) uspRentriFirmeCredenziali_get ----------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFirmeCredenziali_get]
	@IdSessione CHAR(16) = NULL,
	@IdUtente CHAR(16) = NULL,
	@IdCredenziale CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		SET @IdCredenziale = NULLIF(LTRIM(RTRIM(@IdCredenziale)), '');

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
		IF @IdCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdCredenziale non può essere vuoto';
			GOTO BRANCH_END;
		END

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

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRentriCredenziali rc
			INNER JOIN dbo.tblUtenti u ON u.IdDominio = rc.IdDominio
			WHERE rc.Id = @IdCredenziale AND u.Id = @IdUtente
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			u.Id AS IdUtente,
			u.CodiceFiscale,
			u.Nome,
			u.Cognome,
			CredentialsId = CASE WHEN c.Lock = 0 THEN c.CredentialsId ELSE NULL END,
			c.DeviceIdentifier,
			DataBoarding = CASE WHEN c.Lock = 0 THEN c.DataBoarding ELSE NULL END,
			Collegata = CASE WHEN c.IdUtente IS NOT NULL AND c.Lock = 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END
		FROM
			dbo.tblUtenti u
			LEFT JOIN dbo.tblRentriFirmeCredenziali c ON c.IdUtente = u.Id AND c.IdCredenziale = @IdCredenziale
		WHERE u.Id = @IdUtente;

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


-- 4b) uspRentriFirmeCredenziali_upd_Boarding -------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFirmeCredenziali_upd_Boarding]
	@IdSessione CHAR(16) = NULL,
	@IdUtente CHAR(16) = NULL,
	@IdCredenziale CHAR(16) = NULL,
	@CredentialsId VARCHAR(50) = NULL,
	@DeviceIdentifier VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		SET @IdCredenziale = NULLIF(LTRIM(RTRIM(@IdCredenziale)), '');
		SET @CredentialsId = NULLIF(LTRIM(RTRIM(@CredentialsId)), '');
		SET @DeviceIdentifier = NULLIF(LTRIM(RTRIM(@DeviceIdentifier)), '');

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
		IF @IdCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdCredenziale non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @CredentialsId IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @CredentialsId non può essere vuoto';
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

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRentriCredenziali rc
			INNER JOIN dbo.tblUtenti u ON u.IdDominio = rc.IdDominio
			WHERE rc.Id = @IdCredenziale AND u.Id = @IdUtente
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblUtenti
			WHERE
				Id = @IdUtente
				AND CodiceFiscale IS NOT NULL
				AND Nome IS NOT NULL
				AND Cognome IS NOT NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Impostare Codice Fiscale, Nome e Cognome dell''utente prima di collegare la credenziale di firma';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			IF EXISTS (SELECT 1 FROM dbo.tblRentriFirmeCredenziali WHERE IdUtente = @IdUtente AND IdCredenziale = @IdCredenziale)
			BEGIN
				UPDATE dbo.tblRentriFirmeCredenziali
				SET
					CredentialsId = @CredentialsId,
					DeviceIdentifier = @DeviceIdentifier,
					DataBoarding = SYSDATETIME(),
					Lock = 0
				WHERE IdUtente = @IdUtente AND IdCredenziale = @IdCredenziale;
			END
			ELSE
			BEGIN
				INSERT dbo.tblRentriFirmeCredenziali (IdUtente, IdCredenziale, CredentialsId, DeviceIdentifier, DataBoarding, Lock)
				VALUES (@IdUtente, @IdCredenziale, @CredentialsId, @DeviceIdentifier, SYSDATETIME(), 0);
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


-- 4c) uspRentriFirmeCredenziali_del -----------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFirmeCredenziali_del]
	@IdSessione CHAR(16) = NULL,
	@IdUtente CHAR(16) = NULL,
	@IdCredenziale CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		SET @IdCredenziale = NULLIF(LTRIM(RTRIM(@IdCredenziale)), '');

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
		IF @IdCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdCredenziale non può essere vuoto';
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

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRentriCredenziali rc
			INNER JOIN dbo.tblUtenti u ON u.IdDominio = rc.IdDominio
			WHERE rc.Id = @IdCredenziale AND u.Id = @IdUtente
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		UPDATE dbo.tblRentriFirmeCredenziali
		SET
			Lock = 4,
			CredentialsId = NULL
		WHERE
			IdUtente = @IdUtente
			AND IdCredenziale = @IdCredenziale
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


-- 5) uspRentriFirmeOperazioni_ins -------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriFirmeOperazioni_ins]
	@IdSessione CHAR(16) = NULL,
	@IdUtente CHAR(16) = NULL,
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
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');

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

		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblRentriFirmeOperazioni (Id, IdUtente, DataOra, Handle, Esito, Note)
			VALUES (@returnId, @IdUtente, SYSDATETIME(), @Handle, @Esito, @Note);
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
