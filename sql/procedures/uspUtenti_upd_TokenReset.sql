CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_upd_TokenReset]
	@Email NVARCHAR(255) = NULL,
	@Token NVARCHAR(32) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametri
		SET @Email = NULLIF(LTRIM(RTRIM(@Email)), '');
		SET @Token = NULLIF(LTRIM(RTRIM(@Token)), '');

		IF @Email IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Email non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @Token IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Token non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @StatoAttivo NVARCHAR(10) = 'AT'; -- AT = Attivo (tblUtentiStati)

		UPDATE dbo.tblUtenti
		SET
			TokenReset = @Token,
			TokenResetScade = DATEADD(HOUR, 1, GETDATE())
		WHERE
			Email = @Email COLLATE Latin1_General_CI_AS
			AND Lock = 0
			AND IdStato = @StatoAttivo
			AND
				(
				Scadenza IS NULL
				OR Scadenza >= CAST(GETDATE() AS DATE)
				);

		-- 0 = utente non trovato, scaduto o bloccato
		-- 1 = token impostato correttamente
		SET @returnValue = @@ROWCOUNT;

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
