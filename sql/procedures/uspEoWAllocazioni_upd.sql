SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdAllocazioneTipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdAllocazioneTipo = NULLIF(LTRIM(RTRIM(@IdAllocazioneTipo)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);

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
		IF @IdAllocazioneTipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdAllocazioneTipo non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede reale dell'allocazione
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblEoWAllocazioniTipi WHERE Id = @IdAllocazioneTipo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il tipo di allocazione indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Non è possibile cambiare il tipo se l'allocazione ha già lotti collegati (il vincolo di
		-- riga per tipo, es. Lotto unico = max 1 riga, è validato solo in inserimento riga)
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWAllocazioni
			WHERE
				Id = @Id
				AND Lock = 0
				AND IdAllocazioneTipo <> @IdAllocazioneTipo
				AND EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare il tipo di un''allocazione con lotti associati';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un'altra allocazione attiva con lo stesso nome nella stessa sede
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWAllocazioni
			WHERE
				Id <> @Id
				AND IdSede = @idSede
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra allocazione con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblEoWAllocazioni
			SET
				Lock = 0,
				IdAllocazioneTipo = @IdAllocazioneTipo,
				Nome = @Nome
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Allocazione non trovata o già eliminata';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

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
