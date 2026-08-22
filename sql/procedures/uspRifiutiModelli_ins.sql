CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiModelli_ins]
	@IdSessione CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdOperazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdOperazione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RMD', @Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idRegistro CHAR(16);
		SELECT @idRegistro = IdRegistro
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Se non è stato selezionato il registro
		IF @idRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il registro';
			GOTO BRANCH_END;
		END

		-- Limita il numero max di Modelli
		IF 50 <= (SELECT COUNT(*)
		FROM dbo.tblRifiutiModelli
		WHERE
			IdRegistro = @idRegistro
			AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'È stato raggiunto il limite massimo di modelli inseribili';
			GOTO BRANCH_END;
		END

		-- uspId_get gestisce la propria transazione internamente: chiamata FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblRifiutiModelli
				(Id, IdRegistro, IdOperazione, Lock)
			VALUES
				(@returnId, @idRegistro, @IdOperazione, 2);
		COMMIT TRANSACTION;

		SELECT Id = @returnId;

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
