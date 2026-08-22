CREATE OR ALTER PROCEDURE [dbo].[uspOggetti_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Codice VARCHAR(20) = NULL,
	@Descrizione VARCHAR(500) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@ImpiegabileServizi BIT = 0,
	@IdTipo CHAR(2) = NULL,
	@Disabilitata BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'APC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Formattazione parametri opzionali
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Codice = dbo.ufnStringhe_get_SenzaSpazi(@Codice, 0, 1);
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');
		SET @IdTipo = NULLIF(LTRIM(RTRIM(@IdTipo)), '');

		DECLARE @idAzienda CHAR(16) = (SELECT IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione);

		-- Titolarità richiesta indipendentemente dal Lock: prima veniva controllata solo
		-- per Lock=0 (oggetto finalizzato), quindi un oggetto Lock=2 (bozza appena creata
		-- da uspOggetti_ins, non ancora finalizzata) di un'altra azienda poteva essere
		-- completato da chiunque conoscesse l'Id, senza alcun controllo di titolarità.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblOggetti
		WHERE
			Id = @Id
			AND IdSede = @idAzienda
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un oggetto condiviso da altre aziende non può essere modificato';
			GOTO BRANCH_END;
		END

		IF @Nome IS NOT NULL AND @IdTipo IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblOggetti
			WHERE
				Id <> @Id
				AND IdSede = @idAzienda
				AND Lock = 0
				AND Nome = @Nome
				AND IdTipo = @IdTipo
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro oggetto con lo stesso nome e dello stesso tipo è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE dbo.tblOggetti
			SET
				Lock = 0,
				Nome = @Nome,
				Codice = @Codice,
				Descrizione = @Descrizione,
				IdUnitaMisura = @IdUnitaMisura,
				ImpiegabileServizi = @ImpiegabileServizi,
				IdTipo = @IdTipo,
				Disabilitata = @Disabilitata
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Oggetto non trovato o già eliminato';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
