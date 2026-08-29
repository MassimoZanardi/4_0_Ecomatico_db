/*
	Deploy produzione - modulo Rentri/Certificati
	Data: 2026-08-28

	Contenuto:
	  1) Nuova SP dbo.uspRentriCertificati_get_IdRentri
	     (risolve l'IdRentri di un Certificato, usata dalla verifica di
	     connessione con l'hub RENTRI condiviso)
	  2) Aggiornamento di dbo.uspRentriCertificati_upd
	     (ora accetta e salva @Password sull'hub: prima la password non
	     veniva mai scritta se non contestualmente a un nuovo upload del
	     file, quindi modificarla da sola su un certificato gia' esistente
	     non aveva alcun effetto)

	Nessuna modifica di schema, nessuna migrazione dati: solo CREATE OR ALTER,
	idempotente, eseguibile piu' volte senza effetti collaterali.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_rentri_certificati_2026-08-28.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)

	Prerequisito verificato: il DB hub 1_0_rentri raggiungibile da produzione
	tramite [1_0_rentri]..tblCertificati deve gia' esistere con le stesse
	colonne Id/Identificativo/Password/File usate da questo script (nessuna
	modifica ad 1_0_rentri qui, solo letture/scritture verso tabelle gia'
	esistenti).
*/

--------------------------------------------------------------------------------
-- 1) dbo.uspRentriCertificati_get_IdRentri (nuova)
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRentriCertificati_get_IdRentri]
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
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità), stesso pattern di uspRentriCertificati_get
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRentriCertificati c
				INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
			WHERE
				c.Id = @Id
				AND c.Lock <= 2
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Certificato non trovato';
			GOTO BRANCH_END;
		END

		DECLARE @IdRentri CHAR(16);
		SELECT @IdRentri = IdRentri FROM dbo.tblRentriCertificati WHERE Id = @Id;

		IF @IdRentri IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il certificato non è ancora stato caricato su RENTRI';
			GOTO BRANCH_END;
		END

		SELECT rtn = @IdRentri;

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

--------------------------------------------------------------------------------
-- 2) dbo.uspRentriCertificati_upd (aggiornata: aggiunto @Password)
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriCertificati_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Identificativo VARCHAR(20) = NULL,
	@Password VARCHAR(20) = NULL,
	@DataScadenza DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Identificativo = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Identificativo, 0, 1));

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
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
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

		-- Controlla il permesso sul record (titolarità) e recupera IdDominio/IdRentri correnti
		DECLARE @idDominio CHAR(16);
		DECLARE @idRentri CHAR(16);
		SELECT
			@idDominio = c.IdDominio,
			@idRentri = c.IdRentri
		FROM
			dbo.tblRentriCertificati c
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

		-- Controlla che non esista un altro certificato con lo stesso nome nel dominio
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRentriCertificati
			WHERE
				Id <> @Id
				AND IdDominio = @idDominio
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro certificato con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			-- Crea la riga hub al primo salvataggio, altrimenti la aggiorna
			IF @idRentri IS NULL
			BEGIN
				SET @idRentri = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));
				INSERT INTO [1_0_rentri]..tblCertificati (Id, Identificativo, Password)
				VALUES (@idRentri, @Identificativo, @Password);
			END
			ELSE
			BEGIN
				UPDATE [1_0_rentri]..tblCertificati
				SET Identificativo = @Identificativo, Password = @Password
				WHERE Id = @idRentri;
			END

			UPDATE dbo.tblRentriCertificati
			SET
				Lock = 0,
				IdRentri = @idRentri,
				Nome = @Nome,
				DataScadenza = @DataScadenza
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Certificato non trovato o già eliminato';
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
