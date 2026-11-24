SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Impostazioni > Registro email, Azioni > Invia email di prova (funzione EMR, solo amministratori): mette in coda
-- un'email di servizio all'indirizzo dell'utente collegato, per controllare che l'invio funzioni. Non conta nella quota
-- e parte al giro successivo dell'invio (entro 5 minuti). Una sola email di prova ancora da inviare per utente.
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_ins_Prova]
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16), @idDominio CHAR(16), @indirizzo VARCHAR(250);
		SELECT
			@idUtente = u.Id,
			@idDominio = u.IdDominio,
			@indirizzo = u.Email
		FROM
			dbo.tblSessioni s
			INNER JOIN dbo.tblUtenti u ON s.IdUtente = u.Id
		WHERE s.Id = @IdSessione;

		IF EXISTS (
			SELECT 1
			FROM dbo.tblEmail
			WHERE
				IdUtente = @idUtente
				AND Tipo = 'S'
				AND IdStato IN ('D', 'P'))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'C''è già un''email di prova da inviare: parte entro 5 minuti';
			GOTO BRANCH_END;
		END

		DECLARE @contenuto NVARCHAR(MAX) = N'Gentile utente,<br /><br />'
			+ N'questa è un''email di prova richiesta il ' + FORMAT(GETDATE(), 'dd/MM/yyyy HH:mm') + N' da Impostazioni &gt; Registro email.<br />'
			+ N'Se la ricevi, l''invio delle email funziona.';

		DECLARE @id CHAR(16);
		EXEC dbo.uspEmail_ins
			@IdDominio = @idDominio,
			@Tipo = 'S',
			@IdUtente = @idUtente,
			@Indirizzo = @indirizzo,
			@Oggetto = N'Email di prova',
			@Contenuto = @contenuto,
			@Id = @id OUTPUT;

		SELECT @returnValue AS ReturnValue;

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
