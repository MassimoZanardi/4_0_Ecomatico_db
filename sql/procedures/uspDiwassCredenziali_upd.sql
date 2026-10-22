SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva la credenziale DIWASS di un'azienda interna (una sola credenziale attiva per azienda). I dati di accesso
-- (utente EU Login, chiave di autenticazione, client id) vanno nella riga dell'hub [1_0_diwass]..tblCredenziali,
-- creata al primo salvataggio, come per le credenziali RENTRI (uspRentriCredenziali_upd)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassCredenziali_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@IdAziendaInterna CHAR(16) = NULL,
	@Username VARCHAR(50) = NULL,
	@AuthKey VARCHAR(200) = NULL,
	@ClientId VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @IdAziendaInterna = NULLIF(NULLIF(LTRIM(RTRIM(@IdAziendaInterna)), ''), REPLICATE('0', 16));
		SET @Username = NULLIF(LTRIM(RTRIM(@Username)), '');
		SET @AuthKey = NULLIF(LTRIM(RTRIM(@AuthKey)), '');
		SET @ClientId = NULLIF(LTRIM(RTRIM(@ClientId)), '');

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
		IF @IdAziendaInterna IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END
		IF @Username IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il nome utente EU Login';
			GOTO BRANCH_END;
		END
		IF @AuthKey IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la chiave di autenticazione';
			GOTO BRANCH_END;
		END
		IF @ClientId IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il client id';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera IdDominio/IdDiwass correnti
		DECLARE @idDominio CHAR(16);
		DECLARE @idDiwass CHAR(16);
		SELECT
			@idDominio = c.IdDominio,
			@idDiwass = c.IdDiwass
		FROM
			dbo.tblDiwassCredenziali c
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

		-- L'azienda deve essere un'azienda interna attiva visibile all'utente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
			WHERE
				e.Id = @IdSessione
				AND i.Id = @IdAziendaInterna
				AND i.IdDominio = @idDominio
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''azienda selezionata non è valida';
			GOTO BRANCH_END;
		END

		-- Una sola credenziale DIWASS attiva per azienda
		IF EXISTS (
			SELECT 1
			FROM dbo.tblDiwassCredenziali
			WHERE
				Id <> @Id
				AND IdAziendaInterna = @IdAziendaInterna
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''azienda selezionata ha già una credenziale DIWASS';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un'altra credenziale con lo stesso nome nel dominio
		IF EXISTS (
			SELECT 1
			FROM dbo.tblDiwassCredenziali
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
			IF @idDiwass IS NULL
			BEGIN
				SET @idDiwass = LOWER(REPLACE(LEFT(CONVERT(VARCHAR(36), NEWID()), 18), '-', ''));
				INSERT INTO [1_0_diwass]..tblCredenziali (Id, Username, AuthKey, ClientId)
				VALUES (@idDiwass, @Username, @AuthKey, @ClientId);
			END
			ELSE
			BEGIN
				UPDATE [1_0_diwass]..tblCredenziali
				SET
					Username = @Username,
					AuthKey = @AuthKey,
					ClientId = @ClientId
				WHERE Id = @idDiwass;
			END

			UPDATE dbo.tblDiwassCredenziali
			SET
				Lock = 0,
				IdDiwass = @idDiwass,
				Nome = @Nome,
				IdAziendaInterna = @IdAziendaInterna
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
