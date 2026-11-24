SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Impostazioni > Registro email: un'email del dominio della sessione con il testo, per la finestra che la mostra
-- (funzione EMR, solo amministratori).
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EMR',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			e.Id,
			e.Creazione,
			e.Invio,
			e.Indirizzo,
			e.Mittente,
			e.RispondiA,
			e.Oggetto,
			e.Contenuto
		FROM
			dbo.tblEmail e
			INNER JOIN dbo.tblUtenti u ON e.IdDominio = u.IdDominio
			INNER JOIN dbo.tblSessioni s ON s.IdUtente = u.Id
		WHERE
			e.Id = @Id
			AND s.Id = @IdSessione;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
GO
