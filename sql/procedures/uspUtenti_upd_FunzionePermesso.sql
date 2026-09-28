CREATE OR ALTER PROCEDURE [dbo].[uspUtenti_upd_FunzionePermesso]
	@Id CHAR(16) = NULL,
	@IdFunzione CHAR(3) = NULL,
	@IdPermesso INT = 0,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		-- Validazione parametri
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdFunzione = NULLIF(LTRIM(RTRIM(@IdFunzione)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdFunzione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdFunzione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- Controllo permesso sulla funzione (UTE = Gestione Utenti)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'UTE',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idDominioSessione CHAR(16);
		SELECT @idDominioSessione = a.IdDominio
		FROM dbo.tblSessioni s INNER JOIN dbo.tblUtenti a ON a.Id = s.IdUtente
		WHERE s.Id = @IdSessione;

		-- Titolarità: Admin dello stesso Dominio dell'utente target, oppure Admin di un Dominio Master.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblUtenti
		WHERE
			Id = @Id
			AND IdDominio = @idDominioSessione
		)
		AND NOT EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE
			Id = @idDominioSessione
			AND [Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			-- Rimuove il permesso esistente
			DELETE dbo.tblUtentiFunzioni
			WHERE
				Id = @Id
				AND IdFunzione = @IdFunzione;
			-- Inserisce il nuovo permesso solo se > 0
			-- @IdPermesso = 0 equivale a revocare l'accesso
			IF @IdPermesso > 0
				INSERT INTO dbo.tblUtentiFunzioni (Id, IdFunzione, IdPermesso)
				VALUES (@Id, @IdFunzione, @IdPermesso);
		COMMIT TRANSACTION;
		-- Log FUORI dalla transazione: uspId_upd gestisce internamente
		-- la propria transazione e con XACT_ABORT ON potrebbe condannare
		-- la transazione padre se chiamata al suo interno
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
		THROW 50001, @returnMessage, 1;
	END
END;
