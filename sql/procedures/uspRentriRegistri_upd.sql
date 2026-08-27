SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistri_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdCredenziale CHAR(16) = NULL,
	@Identificativo VARCHAR(20) = NULL,
	@BloccoFormulari VARCHAR(10) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdCredenziale = NULLIF(LTRIM(RTRIM(@IdCredenziale)), '');
		SET @Identificativo = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Identificativo, 0, 1));
		SET @BloccoFormulari = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@BloccoFormulari, 0, 1));

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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede del registro
		DECLARE @idSede CHAR(16);
		SELECT @idSede = g.IdSede
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			g.Id = @Id
			AND g.Lock = 0;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idRentri CHAR(16);
		SELECT @idRentri = IdRentri
		FROM dbo.tblRentriRegistri
		WHERE Id = @Id;

		-- Scollegamento: nessun campo valorizzato
		IF @IdCredenziale IS NULL AND @Identificativo IS NULL AND @BloccoFormulari IS NULL
		BEGIN
			IF @idRentri IS NOT NULL
			BEGIN
				BEGIN TRANSACTION;
					DELETE dbo.tblRentriRegistri WHERE Id = @Id;
					DELETE [1_0_rentri]..tblRegistri WHERE Id = @idRentri;
				COMMIT TRANSACTION;
			END
			SELECT ReturnValue = @returnValue;
			GOTO BRANCH_END;
		END

		-- Per collegare/aggiornare serve una credenziale associata alla sede del registro
		IF @IdCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la credenziale';
			GOTO BRANCH_END;
		END

		DECLARE @idRentriSede CHAR(16);
		SELECT @idRentriSede = IdRentri
		FROM dbo.tblRentriCredenzialiSedi
		WHERE
			IdSede = @idSede
			AND IdCredenziale = @IdCredenziale;

		IF @idRentriSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La credenziale selezionata non è associata a questa sede';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista già un altro registro con lo stesso identificativo
		IF @Identificativo IS NOT NULL AND EXISTS (
			SELECT 1
			FROM
				dbo.tblRentriRegistri r
				INNER JOIN [1_0_rentri]..tblRegistri h ON r.IdRentri = h.Id
			WHERE
				r.Id <> @Id
				AND h.Identificativo = @Identificativo
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro registro con lo stesso identificativo è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			IF @idRentri IS NULL
			BEGIN
				SET @idRentri = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));
				INSERT INTO [1_0_rentri]..tblRegistri (Id, IdSede, Identificativo, BloccoFormulari)
				VALUES (@idRentri, @idRentriSede, @Identificativo, @BloccoFormulari);

				INSERT INTO dbo.tblRentriRegistri (Id, IdRentri)
				VALUES (@Id, @idRentri);
			END
			ELSE
			BEGIN
				UPDATE [1_0_rentri]..tblRegistri
				SET
					IdSede = @idRentriSede,
					Identificativo = @Identificativo,
					BloccoFormulari = @BloccoFormulari
				WHERE Id = @idRentri;
			END
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
