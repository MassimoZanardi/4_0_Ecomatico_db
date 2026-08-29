SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRentriCertificati_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Identificativo VARCHAR(20) = NULL,
	@Password VARCHAR(20) = NULL,
	@DataScadenza DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Identificativo = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Identificativo, 0, 1));

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
		IF @DataScadenza IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataScadenza non può essere vuoto';
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

		-- Controlla il permesso sul record (titolarità) e recupera IdDominio/IdRentri correnti
		DECLARE @idDominio CHAR(16);
		DECLARE @idRentri CHAR(16);
		SELECT
			@idDominio = c.IdDominio,
			@idRentri = c.IdRentri
		FROM
			dbo.tblRentriCertificati c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro certificato con lo stesso nome nel dominio
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRentriCertificati
			WHERE
				Id <> @Id
				AND IdDominio = @idDominio
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro certificato con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			-- Crea la riga hub al primo salvataggio, altrimenti la aggiorna
			IF @idRentri IS NULL
			BEGIN
				SET @idRentri = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));
				INSERT INTO [1_0_rentri]..tblCertificati (Id, Identificativo, Password)
				VALUES (@idRentri, @Identificativo, @Password);
			END
			ELSE
			BEGIN
				UPDATE [1_0_rentri]..tblCertificati
				SET Identificativo = @Identificativo, Password = @Password
				WHERE Id = @idRentri;
			END

			UPDATE dbo.tblRentriCertificati
			SET
				Lock = 0,
				IdRentri = @idRentri,
				Nome = @Nome,
				DataScadenza = @DataScadenza
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Certificato non trovato o già eliminato';
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
