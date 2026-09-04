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

		-- Titolarità sull'utente target: se stesso, oppure Amministratore del suo Dominio
		-- (o di un Dominio Master). Stesso schema di uspUtenti_upd.
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

		-- Titolarità sulla Credenziale: deve appartenere allo stesso Dominio del target
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

		-- Lo scollegamento e' solo locale (nessuna chiamata RENTRI): il DeviceIdentifier resta
		-- valorizzato apposta, cosi' un futuro ricollegamento per lo stesso operatore riusa lo
		-- stesso dispositivo invece di farne registrare uno nuovo a RENTRI.
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
