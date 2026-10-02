SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
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
			AS BIT),
			-- Blocco dell'accesso, mostrato solo dopo la verifica della password (lato C#, per non
			-- rivelare lo stato del dominio a chi non conosce la password). Valgono fino al giorno di
			-- scadenza compreso. Il dominio Master non viene mai bloccato: i suoi amministratori
			-- riattivano gli altri domini o ne spostano la scadenza
			Blocco = CASE
				WHEN ISNULL(d.[Master], 0) = 1 THEN NULL
				WHEN d.IdStato = 'SO' THEN 'Dominio sospeso'
				WHEN d.Scadenza < CAST(GETDATE() AS DATE) THEN 'Dominio scaduto'
				WHEN u.Scadenza < CAST(GETDATE() AS DATE) THEN 'Utente scaduto'
				ELSE NULL
			END
		FROM
			dbo.tblUtenti u
			LEFT JOIN dbo.tblDomini d ON u.IdDominio = d.Id
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
GO
