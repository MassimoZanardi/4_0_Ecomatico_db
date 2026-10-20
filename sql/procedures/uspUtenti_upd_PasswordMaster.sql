SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_upd_PasswordMaster]
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Allinea la password degli utenti Master di tutti i domini a quella dell'amministratore
		-- del dominio Master (regola D1.5). Chiamata da ogni SP che cambia una password:
		-- se @Id non è l'amministratore del dominio Master non fa nulla
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblUtenti u
			INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
			WHERE
				u.Id = @Id
				AND u.IdRuolo = 'AD'
				AND u.Lock = 0
				AND d.[Master] = 1
		)
			GOTO BRANCH_END;

		-- Solo la password corrente (la più recente) e solo se definitiva: una password
		-- temporanea va cambiata al primo accesso e uspUtenti_upd_Login la cancella, quindi
		-- si propaga la password che l'amministratore sceglie al cambio
		DECLARE @password NVARCHAR(200);
		DECLARE @temporanea BIT;
		SELECT TOP 1
			@password = [Password],
			@temporanea = ISNULL(Temporanea, 0)
		FROM dbo.tblUtentiPassword
		WHERE Id = @Id
		ORDER BY [Data] DESC;

		IF @password IS NULL OR @temporanea = 1
			GOTO BRANCH_END;

		BEGIN TRANSACTION;

			-- Sostituisce la password corrente di ogni utente Master: lo storico resta com'è
			UPDATE up
			SET
				[Password] = @password,
				Temporanea = 0
			FROM dbo.tblUtentiPassword up
			INNER JOIN dbo.tblUtenti u ON up.Id = u.Id
			WHERE
				u.[Master] = 1
				AND u.Id <> @Id
				AND up.[Data] = ( SELECT MAX([Data]) FROM dbo.tblUtentiPassword WHERE Id = up.Id );

			-- Utenti Master ancora senza password
			INSERT INTO dbo.tblUtentiPassword (Id, [Password], [Data], Temporanea)
			SELECT u.Id, @password, GETDATE(), 0
			FROM dbo.tblUtenti u
			WHERE
				u.[Master] = 1
				AND u.Id <> @Id
				AND NOT EXISTS (SELECT 1 FROM dbo.tblUtentiPassword WHERE Id = u.Id);

		COMMIT TRANSACTION;

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
