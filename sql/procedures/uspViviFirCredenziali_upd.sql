SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva la credenziale Vi.Vi.FIR del dominio, che si associa poi alle aziende interne in Vivifir > Aziende
-- (uspViviFirAziende_upd). Le credenziali applicative (ClientId e ClientSecret del flusso OAuth2) vanno nella riga dell'hub
-- [1_0_vivifir]..tblCredenziali, creata al primo salvataggio, come per le credenziali RENTRI e DIWASS; la scadenza (le
-- credenziali applicative valgono un anno) resta nell'app ed è solo informativa
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirCredenziali_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@ClientId VARCHAR(100) = NULL,
	@ClientSecret VARCHAR(200) = NULL,
	@Scadenza DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @ClientId = NULLIF(LTRIM(RTRIM(@ClientId)), '');
		SET @ClientSecret = NULLIF(LTRIM(RTRIM(@ClientSecret)), '');

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
			SET @returnMessage = 'Indicare un nome per la credenziale';
			GOTO BRANCH_END;
		END
		IF @ClientId IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il ClientId';
			GOTO BRANCH_END;
		END
		IF @ClientSecret IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il ClientSecret';
			GOTO BRANCH_END;
		END
		IF @Scadenza IS NOT NULL AND (@Scadenza < '20200101' OR @Scadenza > '20501231')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare una scadenza compresa tra il 01/01/2020 e il 31/12/2050';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera IdDominio/IdViviFir correnti
		DECLARE @idDominio CHAR(16);
		DECLARE @idViviFir CHAR(16);
		SELECT
			@idDominio = c.IdDominio,
			@idViviFir = c.IdViviFir
		FROM
			dbo.tblViviFirCredenziali c
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

		-- Controlla che non esista un'altra credenziale con lo stesso nome nel dominio
		IF EXISTS (
			SELECT 1
			FROM dbo.tblViviFirCredenziali
			WHERE
				Id <> @Id
				AND IdDominio = @idDominio
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra credenziale con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			-- Crea la riga hub al primo salvataggio, altrimenti la aggiorna
			IF @idViviFir IS NULL
			BEGIN
				SET @idViviFir = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));
				INSERT INTO [1_0_vivifir]..tblCredenziali (Id, ClientId, ClientSecret)
				VALUES (@idViviFir, @ClientId, @ClientSecret);
			END
			ELSE
			BEGIN
				UPDATE [1_0_vivifir]..tblCredenziali
				SET
					ClientId = @ClientId,
					ClientSecret = @ClientSecret
				WHERE Id = @idViviFir;
			END

			UPDATE dbo.tblViviFirCredenziali
			SET
				Lock = 0,
				IdViviFir = @idViviFir,
				Nome = @Nome,
				Scadenza = @Scadenza
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Credenziale non trovata o già eliminata';
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
