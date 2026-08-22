CREATE OR ALTER PROCEDURE [dbo].[uspPersone_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Cognome VARCHAR(50) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@ImpiegabileServizi BIT = 0,
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
		SET @Cognome = dbo.ufnStringhe_get_SenzaSpazi(@Cognome, 0, 1);
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');

		DECLARE @idAzienda CHAR(16) = (SELECT IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione);

		-- Titolarità richiesta indipendentemente dal Lock: prima veniva controllata solo
		-- per Lock=0 (anagrafica finalizzata), quindi una persona Lock=2 (bozza appena
		-- creata da uspPersone_ins, non ancora finalizzata) di un'altra azienda poteva
		-- essere completata da chiunque conoscesse l'Id, senza alcun controllo di titolarità.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblPersone
		WHERE
			Id = @Id
			AND IdSede = @idAzienda
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una persona condivisa da altre aziende non può essere modificata';
			GOTO BRANCH_END;
		END

		IF @Nome IS NOT NULL AND @Cognome IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblPersone
			WHERE
				Id <> @Id
				AND IdSede = @idAzienda
				AND Lock = 0
				AND Nome = @Nome
				AND Cognome = @Cognome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra persona con lo stesso nome e cognome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE dbo.tblPersone
			SET
				Lock = 0,
				Nome = @Nome,
				Cognome = @Cognome,
				Disabilitata = @Disabilitata,
				NomeCompleto = COALESCE(@Cognome + ' ' + @Nome, @Cognome, @Nome),
				ImpiegabileServizi = @ImpiegabileServizi,
				IdUnitaMisura = @IdUnitaMisura
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Persona non trovata o già eliminata';
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
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
