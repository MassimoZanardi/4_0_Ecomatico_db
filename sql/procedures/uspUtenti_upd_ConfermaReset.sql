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
