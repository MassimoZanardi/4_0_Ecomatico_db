SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Conferma locale del caricamento su RENTRI della copia del FIR digitale ("RENTRI - Carica copia FIR",
-- Rifiuti/Registrazioni/Edit, lato destinatario di un "carico di rifiuto ricevuti da terzi" - IsRentriAccettazione).
-- Riusa la colonna tblRifiutiMovimenti.RentriFormularioDataCopia (esistente ma mai valorizzata lato app,
-- vedi migrazione 2026-09-07 da tblRifiutiFormulari), stesso pattern di uspRentriRegistrazioni_upd_PresaVisione:
-- la chiamata all'hub RENTRI (RentriHubFormularioDigitaleService.CaricamentoCopiaAsync) e' gia' avvenuta lato
-- chiamante prima di questa SP, qui si registra solo l'esito in locale per nascondere l'azione dal menu.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_upd_CaricamentoCopia]
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
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idMovimento CHAR(16), @rentriFormularioDataCopia SMALLDATETIME;
		SELECT
			@idMovimento = m.Id,
			@rentriFormularioDataCopia = m.RentriFormularioDataCopia
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE r.Id = @Id;

		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			WHERE
				r.Id = @Id
				AND o.IsRentriAccettazione = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Operazione non consentita: questa registrazione non è di tipo "carico da terzi"';
			GOTO BRANCH_END;
		END

		IF @rentriFormularioDataCopia IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il caricamento della copia del FIR è già stato registrato per questa registrazione';
			GOTO BRANCH_END;
		END

		UPDATE dbo.tblRifiutiMovimenti
		SET RentriFormularioDataCopia = GETDATE()
		WHERE Id = @idMovimento;

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
		THROW 50001, @returnMessage, 1;
	END

END;
GO
