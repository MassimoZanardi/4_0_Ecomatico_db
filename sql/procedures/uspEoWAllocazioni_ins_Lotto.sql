SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_ins_Lotto
	@Id CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@Valore DECIMAL(18, 2) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdLotto non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
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

		-- Titolarità + dati dell'allocazione
		DECLARE @idSedeAllocazione CHAR(16);
		DECLARE @idAllocazioneTipo CHAR(1);
		SELECT
			@idSedeAllocazione = c.IdSede,
			@idAllocazioneTipo = c.IdAllocazioneTipo
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE
			c.Id = @Id
			AND c.Lock <= 2;

		IF @idSedeAllocazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allocazione non trovata o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il materiale dell'allocazione non è un campo proprio: si ricava dal primo lotto aggiunto
		-- e deve restare coerente con gli altri lotti già presenti (nessuna anagrafica/duplicazione
		-- separata, "un'Allocazione = un Materiale" è solo un vincolo, non uno stato memorizzato).
		DECLARE @idMaterialeAllocazione CHAR(2) = (
			SELECT TOP 1 l.IdMateriale
			FROM dbo.tblEoWLottiAllocazioni la
			INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
			WHERE la.IdAllocazione = @Id
		);

		-- Titolarità + dati del lotto
		DECLARE @idSedeLotto CHAR(16);
		DECLARE @idMaterialeLotto CHAR(2);
		SELECT
			@idSedeLotto = l.IdSede,
			@idMaterialeLotto = l.IdMateriale
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
		WHERE
			l.Id = @IdLotto
			AND l.Lock = 0;

		IF @idSedeLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lotto non trovato o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idSedeLotto <> @idSedeAllocazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto selezionato non appartiene alla sede dell''allocazione';
			GOTO BRANCH_END;
		END

		IF @idMaterialeAllocazione IS NOT NULL AND @idMaterialeLotto <> @idMaterialeAllocazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il materiale del lotto non coincide con il materiale degli altri lotti già presenti nell''allocazione';
			GOTO BRANCH_END;
		END

		IF EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id AND IdLotto = @IdLotto)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questo lotto è già presente nell''allocazione';
			GOTO BRANCH_END;
		END

		-- Validazione specifica per tipo (i valori dei tipi sono in tblEoWAllocazioniTipi: U=Lotto
		-- unico, P=Percentuale, C=Priorità/Capacità)
		IF @idAllocazioneTipo = 'U' AND EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''allocazione di tipo Lotto unico può contenere un solo lotto';
			GOTO BRANCH_END;
		END

		IF @idAllocazioneTipo = 'P' AND (@Valore IS NULL OR @Valore <= 0 OR @Valore > 100)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La percentuale deve essere maggiore di zero e non superiore a 100';
			GOTO BRANCH_END;
		END

		IF @idAllocazioneTipo = 'C' AND (@Valore IS NULL OR @Valore <= 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La priorità deve essere un valore maggiore di zero';
			GOTO BRANCH_END;
		END

		IF @idAllocazioneTipo = 'U'
			SET @Valore = NULL;

		BEGIN TRANSACTION;
			INSERT dbo.tblEoWLottiAllocazioni (IdLotto, IdAllocazione, Valore)
			VALUES (@IdLotto, @Id, @Valore);
		COMMIT TRANSACTION;

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
