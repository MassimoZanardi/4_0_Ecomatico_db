CREATE OR ALTER PROCEDURE [dbo].[uspAree_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Descrizione VARCHAR(500) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	DECLARE @returnValue INT = 0;
	DECLARE @returnMessage NVARCHAR(200) = NULL;

	BEGIN TRY

		-- Validazione parametri obbligatori
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

		-- Permesso sulla funzione (ARE = Gestione Aree)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ARE',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Legge il dominio dalla sessione
		DECLARE @idDominio CHAR(16);
		SELECT @idDominio = IdDominio
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida o scaduta';
			GOTO BRANCH_END;
		END

		-- Normalizza parametri opzionali: collassa spazi multipli interni, trim, NULL se vuoto
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);

		-- Verifica unicità nome nel dominio (solo record completati)
		IF @Nome IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblAree
			WHERE
				Id <> @Id
				AND IdDominio = @idDominio
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra area con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE dbo.tblAree
			SET
				Lock = 0,
				Nome = ISNULL(@Nome, Nome),
				Descrizione = ISNULL(@Descrizione, Descrizione)
			WHERE
				Id = @Id
				AND IdDominio = @idDominio
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Area non trovata o già eliminata';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@Operazione = 'U';

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
