SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiLimiti_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Valore DECIMAL(18, 2) = NULL,
	@Riferimento CHAR(1) = NULL,
	@Intervallo CHAR(2) = NULL,
	@IdOperazioni VARCHAR(200) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Riferimento = NULLIF(LTRIM(RTRIM(@Riferimento)), '');
		SET @Intervallo = NULLIF(LTRIM(RTRIM(@Intervallo)), '');
		SET @IdOperazioni = NULLIF(LTRIM(RTRIM(@IdOperazioni)), '');

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
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdUnitaMisura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUnitaMisura non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Valore IS NULL OR @Valore <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il valore del limite deve essere maggiore di zero';
			GOTO BRANCH_END;
		END
		IF @Riferimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Riferimento non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Intervallo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Intervallo non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @IdUnitaMisura NOT IN ('GG', 'KG', 'LT')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Unità di misura non valida';
			GOTO BRANCH_END;
		END
		IF @Riferimento NOT IN ('G', 'O')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Riferimento non valido';
			GOTO BRANCH_END;
		END
		IF @Intervallo NOT IN ('GG', 'WK', 'MM', 'YY')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Intervallo non valido';
			GOTO BRANCH_END;
		END

		-- L'unità di misura "Giorni" ha senso solo per i limiti di giacenza (giorni di
		-- permanenza di un carico), non per i limiti sulle operazioni in un intervallo.
		IF @IdUnitaMisura = 'GG' AND @Riferimento <> 'G'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''unità di misura Giorni è ammessa solo per i limiti di giacenza';
			GOTO BRANCH_END;
		END

		-- Le operazioni sono filtrabili solo per i limiti sulle operazioni
		IF @IdOperazioni IS NOT NULL AND @Riferimento <> 'O'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le operazioni sono associabili solo ai limiti per operazioni';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RLM',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede reale del limite
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblRifiutiLimiti c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Se indicato un registro specifico, deve appartenere alla stessa sede del limite
		IF @IdRegistro IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistri
			WHERE
				Id = @IdRegistro
				AND IdSede = @idSede
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro indicato non appartiene alla sede del limite';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro record con lo stesso nome nella sede
		-- (ambito Sede e non Registro: IdRegistro è opzionale sui limiti)
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiLimiti
			WHERE
				Id <> @Id
				AND IdSede = @idSede
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro limite con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblRifiutiLimiti
			SET
				Lock = 0,
				IdRegistro = @IdRegistro,
				IdUnitaMisura = @IdUnitaMisura,
				Nome = @Nome,
				Valore = @Valore,
				Riferimento = @Riferimento,
				Intervallo = @Intervallo
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Limite non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			-- Operazioni: sostituzione completa del set (solo se Riferimento = 'O')
			DELETE dbo.tblRifiutiLimitiOperazioni
			WHERE IdLimite = @Id;

			IF @IdOperazioni IS NOT NULL
				INSERT dbo.tblRifiutiLimitiOperazioni (IdLimite, IdOperazione)
				SELECT
					@Id,
					o.Id
				FROM
					dbo.tblRifiutiOperazioni o
					INNER JOIN STRING_SPLIT(@IdOperazioni, ';') v ON o.Id = v.value;
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
