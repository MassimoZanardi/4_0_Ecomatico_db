SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Conferma della sola presa visione della copia del FIR digitale ("RENTRI - Verifica esito", Rifiuti/
-- Registrazioni/Edit, lato mittente di un conferimento a terzi) - separata deliberatamente
-- dall'aggiornamento dei campi Esito (uspRentriRegistrazioni_upd_Esito): la presa visione e' un obbligo
-- verso RENTRI indipendente dal poter modificare il registro cronologico locale, quindi VA CONSENTITA
-- anche quando la registrazione e' gia' stata trasmessa al RENTRI o e' bloccata per conservazione
-- sostitutiva (a differenza di uspRentriRegistrazioni_upd_Esito, qui NESSUN controllo su
-- RentriIdentificativo/RentriData/ConservazioneSostitutiva - la conferma su RENTRI stesso
-- (RentriHubFormularioDigitaleService.ConfermaCopiaAsync) e' gia' avvenuta lato chiamante prima di questa
-- SP, se quella riporta un dato mancante localmente le due parti andrebbero disallineate).
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_upd_PresaVisione]
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

		DECLARE @idMovimento CHAR(16), @rentriFormularioDataPresaVisione SMALLDATETIME;
		SELECT
			@idMovimento = m.Id,
			@rentriFormularioDataPresaVisione = m.RentriFormularioDataPresaVisione
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
				AND o.IsEsito = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non prevede un esito di conferimento';
			GOTO BRANCH_END;
		END

		IF @rentriFormularioDataPresaVisione IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La presa visione della copia è già stata registrata per questa registrazione';
			GOTO BRANCH_END;
		END

		UPDATE dbo.tblRifiutiMovimenti
		SET RentriFormularioDataPresaVisione = GETDATE()
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
