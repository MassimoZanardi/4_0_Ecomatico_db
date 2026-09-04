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
