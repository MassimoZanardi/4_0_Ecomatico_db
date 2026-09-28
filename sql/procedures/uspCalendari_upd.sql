CREATE OR ALTER PROCEDURE [dbo].[uspCalendari_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Descrizione VARCHAR(500) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	DECLARE @returnValue INT = 0;
	DECLARE @returnMessage NVARCHAR(200) = NULL;
	DECLARE @permesso TINYINT;

	BEGIN TRY

		-- ── Validazione parametri ───
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdModulo = NULLIF(LTRIM(RTRIM(@IdModulo)), '');

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
		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdModulo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- ── Controllo permessi ───
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'CLD',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Verifica che il calendario esista, appartenga davvero a @IdSede/@IdModulo
		-- (evita che parametri disallineati aggirino il controllo di unicità sotto)
		-- e che la sede sia accessibile dalla sessione corrente
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblCalendari c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
					   ON c.IdSede = i.Id
			WHERE
				c.Id = @Id
				AND c.IdSede = @IdSede
				AND c.IdModulo = @IdModulo
				AND c.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Calendario non trovato';
			GOTO BRANCH_END;
		END

		-- ── Formattazione parametri ───
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);

		-- ── Verifica unicità Nome nella sede/modulo ───
		IF @Nome IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblCalendari
			WHERE
				Id <> @Id
				AND IdSede = @IdSede
				AND IdModulo = @IdModulo
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro calendario con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		-- ── Aggiornamento ───
		BEGIN TRANSACTION;

			UPDATE dbo.tblCalendari
			SET
				Lock = 0,
				Nome = ISNULL(@Nome, Nome),
				Descrizione = ISNULL(@Descrizione, Descrizione)
			WHERE
				Id = @Id
				AND IdSede = @IdSede
				AND IdModulo = @IdModulo
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Calendario non trovato o già eliminato';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

		-- Log fuori transazione
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
