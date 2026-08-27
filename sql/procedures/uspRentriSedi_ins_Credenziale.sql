SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriSedi_ins_Credenziale]
	@IdSede CHAR(16) = NULL,
	@IdCredenziale CHAR(16) = NULL,
	@Identificativo VARCHAR(30) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdCredenziale = NULLIF(LTRIM(RTRIM(@IdCredenziale)), '');
		SET @Identificativo = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Identificativo, 0, 1));
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la credenziale';
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

		-- Titolarità sulla sede + dominio della sede
		DECLARE @idDominio CHAR(16);
		SELECT @idDominio = i.IdDominio
		FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
		WHERE i.Id = @IdSede;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La credenziale deve appartenere allo stesso dominio, essere attiva e già collegata all'hub
		DECLARE @idRentriCredenziale CHAR(16);
		SELECT @idRentriCredenziale = IdRentri
		FROM dbo.tblRentriCredenziali
		WHERE
			Id = @IdCredenziale
			AND IdDominio = @idDominio
			AND Lock = 0;

		IF @idRentriCredenziale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La credenziale selezionata non è valida';
			GOTO BRANCH_END;
		END

		IF EXISTS (
			SELECT 1
			FROM dbo.tblRentriCredenzialiSedi
			WHERE
				IdSede = @IdSede
				AND IdCredenziale = @IdCredenziale)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La credenziale è già associata a questa sede';
			GOTO BRANCH_END;
		END

		-- Calcolo intermedio in SMALLINT: ISNULL(MAX(Pos), -1) andrebbe in overflow
		-- se valutato direttamente in TINYINT (Pos è TINYINT, range 0-255).
		DECLARE @posCalc SMALLINT;
		SELECT @posCalc = MAX(CAST(Pos AS SMALLINT))
		FROM dbo.tblRentriCredenzialiSedi
		WHERE IdSede = @IdSede;
		SET @posCalc = ISNULL(@posCalc, -1) + 1;
		DECLARE @pos TINYINT = CAST(@posCalc AS TINYINT);

		DECLARE @idRentri CHAR(16) = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));

		BEGIN TRANSACTION;
			INSERT INTO [1_0_rentri]..tblSedi (Id, IdCredenziale, Identificativo)
			VALUES (@idRentri, @idRentriCredenziale, @Identificativo);

			INSERT INTO dbo.tblRentriCredenzialiSedi (IdSede, IdCredenziale, IdRentri, Pos)
			VALUES (@IdSede, @IdCredenziale, @idRentri, @pos);
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
