CREATE OR ALTER PROCEDURE [dbo].[uspPersone_ins_Ruolo]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdRuolo CHAR(2) = NULL,
	@DataInizio DATE = NULL,
	@DataFine DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRuolo = NULLIF(LTRIM(RTRIM(@IdRuolo)), '');

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
		IF @IdRuolo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRuolo non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataInizio IS NOT NULL AND @DataFine IS NOT NULL AND @DataInizio > @DataFine
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di inizio non può essere successiva alla data di fine';
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

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblPersone s
			INNER JOIN dbo.tblSessioni e ON s.IdSede = e.IdAzienda
			WHERE
				s.Id = @Id
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una persona condivisa da altre aziende non può essere modificata';
			GOTO BRANCH_END;
		END

		IF 20 <= (SELECT COUNT(*)
		FROM dbo.tblPersoneRuoli
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'È stato raggiunto il limite massimo di ruoli inseribili';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			INSERT INTO dbo.tblPersoneRuoli (Id, IdRuolo, DataInizio, DataFine)
			VALUES (@Id, @IdRuolo, @DataInizio, @DataFine);
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
