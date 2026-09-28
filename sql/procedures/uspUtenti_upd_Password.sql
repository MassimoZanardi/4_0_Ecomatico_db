CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_upd_Password]
	@Id CHAR(16) = NULL,
	@Password NVARCHAR(200) = NULL,
	@Temporanea BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		-- Validazione parametri
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Password = NULLIF(LTRIM(RTRIM(@Password)), '');
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Password IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Password non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- Aggiorna solo l'ultima password inserita per questo utente
		UPDATE TOP (1) dbo.tblUtentiPassword
		SET
			[Password] = @Password,
			[Data] = GETDATE(),
			Temporanea = @Temporanea
		WHERE
			Id = @Id
			AND [Data] = ( SELECT MAX([Data]) FROM dbo.tblUtentiPassword WHERE Id = @Id );
		-- Verifica che l'UPDATE abbia effettivamente modificato una riga
		IF @@ROWCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Nessuna password trovata per l''utente specificato';
			GOTO BRANCH_END;
		END
		-- Restituisce LoginResponse per login immediato post-cambio password
		-- Tabelle base invece di viewUtenti: evita OUTER APPLY su tblUtentiPassword
		SELECT
			u.Id,
			u.IdDominio,
			u.IdRuolo,
			u.Email,
			CAST(@Temporanea AS BIT) AS PasswordScaduta
		FROM dbo.tblUtenti u
		WHERE
			u.Id = @Id
			AND u.Lock <= 2;
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
