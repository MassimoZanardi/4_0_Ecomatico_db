CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiAutorizzazioni_upd_Conducente]
	@Id CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Cognome VARCHAR(50) = NULL,
	@ScadenzaPatente DATE = NULL,
	@ScadenzaPatenteAdr DATE = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Cognome = dbo.ufnStringhe_get_SenzaSpazi(@Cognome, 0, 1);
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Cognome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Cognome non può essere vuoto';
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
			@IdFunzione = 'RAT',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sull'autorizzazione padre: senza questo controllo, chiunque avesse
		-- permesso RAT sul modulo (anche di un'altra azienda) poteva modificare i conducenti
		-- di un'autorizzazione non propria conoscendone l'Id.
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiAutorizzazioni a
			INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
			INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				a.Id = @Id
				AND e.Id = @IdSessione
				AND a.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''autorizzazione condivisa da altre aziende non può essere modificata';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblRifiutiAutorizzazioniConducenti
			SET
				ScadenzaPatente = IIF(@ScadenzaPatente <= '19000101', NULL, @ScadenzaPatente),
				ScadenzaPatenteAdr = IIF(@ScadenzaPatenteAdr <= '19000101', NULL, @ScadenzaPatenteAdr)
			WHERE
				Id = @Id
				AND Nome = @Nome
				AND Cognome = @Cognome;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Conducente non trovato';
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
