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
