SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspSediDatiEstesi_upd]
	@IdSede CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdAteco VARCHAR(10) = NULL,
	@CodiceRea VARCHAR(10) = NULL,
	@Dipendenti INT = NULL,
	@LegaleNome VARCHAR(50) = NULL,
	@LegaleCognome VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdAteco = NULLIF(LTRIM(RTRIM(@IdAteco)), '');
		SET @CodiceRea = dbo.ufnStringhe_get_SenzaSpazi(@CodiceRea, 0, 1);
		SET @LegaleNome = dbo.ufnStringhe_get_SenzaSpazi(@LegaleNome, 0, 1);
		SET @LegaleCognome = dbo.ufnStringhe_get_SenzaSpazi(@LegaleCognome, 0, 1);

		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Dipendenti IS NOT NULL AND @Dipendenti < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero di addetti non può essere negativo';
			GOTO BRANCH_END;
		END
		IF @IdAteco IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblAteco WHERE Id = @IdAteco)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Codice ATECO non valido';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MUD',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sulla sede indicata (scope azienda interna)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSedi s
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON s.IdAziendaInterna = i.Id
			WHERE s.Id = @IdSede)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			IF EXISTS (SELECT 1 FROM dbo.tblSediDatiEstesi WHERE Id = @IdSede)
			BEGIN
				UPDATE dbo.tblSediDatiEstesi
				SET
					IdAteco = @IdAteco,
					CodiceRea = @CodiceRea,
					Dipendenti = @Dipendenti,
					LegaleNome = @LegaleNome,
					LegaleCognome = @LegaleCognome
				WHERE Id = @IdSede;
			END
			ELSE
			BEGIN
				INSERT dbo.tblSediDatiEstesi (Id, IdAteco, CodiceRea, Dipendenti, LegaleNome, LegaleCognome)
				VALUES (@IdSede, @IdAteco, @CodiceRea, @Dipendenti, @LegaleNome, @LegaleCognome);
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
