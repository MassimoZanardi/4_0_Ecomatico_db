SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		-- Validazione parametri
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
		-- Risolve l'utente della sessione corrente
		DECLARE @idUtente CHAR(16);
		SELECT @idUtente = IdUtente
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;
		IF @idUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida o scaduta';
			GOTO BRANCH_END;
		END
		-- Controllo permessi: l'utente richiedente deve essere Admin
		-- Scenario 1: Admin dello stesso dominio dell'utente target
		-- Scenario 2: Admin di un dominio Master (visibilità globale)
		-- Se NESSUNO dei due è verificato → accesso negato
		IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblUtenti u
				INNER JOIN dbo.tblUtenti a
						   ON u.IdDominio = a.IdDominio
				WHERE
					u.Id = @Id
					AND a.Id = @idUtente
					AND a.IdRuolo = 'AD' -- AD = Amministratore
					AND a.Lock = 0
					AND u.[Master] = 0
		)
		AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblUtenti u
				INNER JOIN dbo.tblUtenti a
						   ON a.Id = @idUtente
				INNER JOIN dbo.tblDomini d
						   ON a.IdDominio = d.Id
				WHERE
					u.Id = @Id
					AND a.IdRuolo = 'AD' -- AD = Amministratore
					AND a.Lock = 0
					AND d.[Master] = 1 -- dominio Master: visibilità globale
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblUtenti
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Utente non trovato';
			GOTO BRANCH_END;
		END
		-- Dati utente: tabelle base invece di viewUtenti
		SELECT
			u.Id,
			u.IdDominio,
			u.IdRuolo,
			u.IdStato,
			u.Email,
			u.Scadenza,
			PasswordPrecedenti = ISNULL(u.PasswordPrecedenti, 0),
			PasswordScadenzaGiorni = ISNULL(u.PasswordScadenzaGiorni, 0),
			PasswordLunghezzaMinima = ISNULL(u.PasswordLunghezzaMinima, 8),
			u.CodiceFiscale,
			u.Nome,
			u.Cognome,
			u.Lock
		FROM
			dbo.tblUtenti u
		WHERE
			u.Id = @Id
			AND u.Lock <= 2;
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
