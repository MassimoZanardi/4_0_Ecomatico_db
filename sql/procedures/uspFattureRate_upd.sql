SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva una rata (scadenza) della fattura: con @Id vuoto la aggiunge a @IdFattura, altrimenti la
-- modifica. Le rate si salvano subito, anche sulla fattura in bozza. Restituisce l'Id della rata.
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_upd
	@Id CHAR(16) = NULL,
	@IdFattura CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@DataScadenza DATE = NULL,
	@Importo DECIMAL(18, 2) = NULL,
	@Abbuono DECIMAL(18, 2) = NULL,
	@Note VARCHAR(250) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdFattura = NULLIF(LTRIM(RTRIM(@IdFattura)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Abbuono = ISNULL(@Abbuono, 0);
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);

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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Rata esistente: la fattura è quella della rata
		IF @Id IS NOT NULL
		BEGIN
			SET @IdFattura = NULL;
			SELECT @IdFattura = IdFattura
			FROM dbo.tblFattureRate
			WHERE Id = @Id;
		END

		-- La fattura deve esistere (in bozza o attiva, non eliminata), appartenere all'azienda interna
		-- corrente della sessione e non essere in sola lettura
		DECLARE @idAzienda CHAR(16);
		DECLARE @solaLettura BIT;
		SELECT
			@idAzienda = f.IdSede,
			@solaLettura = ISNULL(f.SolaLettura, 0)
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			f.Id = @IdFattura
			AND e.Id = @IdSessione
			AND f.Lock IN (0, 2);

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END
		IF @solaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura e salvare';
			GOTO BRANCH_END;
		END

		IF @DataScadenza IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data di scadenza della rata';
			GOTO BRANCH_END;
		END
		IF @Importo IS NULL OR @Importo <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo della rata deve essere maggiore di zero';
			GOTO BRANCH_END;
		END
		IF @Abbuono < 0 OR @Abbuono > @Importo
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''abbuono deve essere compreso tra zero e l''importo della rata';
			GOTO BRANCH_END;
		END
		IF LEN(@Note) > 200
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le note della rata non possono superare i 200 caratteri';
			GOTO BRANCH_END;
		END

		-- Nuova rata: uspId_get FUORI dalla transazione
		DECLARE @nuova BIT = IIF(@Id IS NULL, 1, 0);
		IF @nuova = 1
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @Id OUTPUT;

		BEGIN TRANSACTION;
			IF @nuova = 1
				INSERT dbo.tblFattureRate (Id, IdFattura, Importo, Abbuono, DataScadenza, Note)
				VALUES (@Id, @IdFattura, @Importo, @Abbuono, @DataScadenza, @Note);
			ELSE
				UPDATE dbo.tblFattureRate
				SET
					Importo = @Importo,
					Abbuono = @Abbuono,
					DataScadenza = @DataScadenza,
					Note = @Note
				WHERE Id = @Id;
		COMMIT TRANSACTION;

		SELECT Id = @Id;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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
