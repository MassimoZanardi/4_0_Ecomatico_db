CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_get_LoginByEmail]
	@Email NVARCHAR(255) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Normalizzazione: rimuove spazi, vuoti e forza minuscolo
		-- LOWER() rende il confronto sicuro senza COLLATE runtime
		SET @Email = LOWER(NULLIF(LTRIM(RTRIM(@Email)), ''));

		IF @Email IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Email non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @StatoAttivo NVARCHAR(10) = 'AT'; -- AT = Attivo (tblUtentiStati)

		SELECT TOP 1
			u.Id,
			u.IdDominio,
			u.IdRuolo,
			u.Email,
			p.[Password],
			PasswordScaduta = CAST(
				CASE
					WHEN p.Temporanea = 1 THEN 1
					WHEN u.PasswordScadenzaGiorni > 0
						 AND DATEDIFF(
							 DAY,
							 ISNULL(p.[Data], GETDATE()),
							 GETDATE()
						 ) > u.PasswordScadenzaGiorni THEN 1
					ELSE 0
				END
			AS BIT)
		FROM
			dbo.tblUtenti u
			OUTER APPLY (
				SELECT TOP 1 [Password], [Data], Temporanea
				FROM dbo.tblUtentiPassword
				WHERE Id = u.Id
				ORDER BY [Data] DESC
			) p
		WHERE
			u.Email = @Email
			AND u.IdStato = @StatoAttivo
			AND u.Lock = 0
		ORDER BY
			u.Id ASC;

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
