SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Carica il logo di stampa (DDT e fatture) dell'azienda interna corrente della sessione, subito alla scelta del
-- file come per il logo del dominio. Se il layout non è ancora stato salvato crea la riga con i valori
-- predefiniti di ufnSediReport_get_Layout. Dimensione massima 200 KB (controllata anche dalla pagina).
CREATE OR ALTER PROCEDURE dbo.uspSediReport_upd_Logo
	@IdSessione CHAR(16) = NULL,
	@Logo VARBINARY(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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
			@IdFunzione = 'AZI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il logo è dell'azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		IF @Logo IS NULL OR DATALENGTH(@Logo) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il file del logo';
			GOTO BRANCH_END;
		END
		IF DATALENGTH(@Logo) > 204800
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare un file di dimensioni inferiori a 200 KB';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblSediReport WITH (UPDLOCK, HOLDLOCK)
			SET Logo = @Logo
			WHERE Id = @idAzienda;

			IF @@ROWCOUNT = 0
				INSERT dbo.tblSediReport (Id, IdLayout, Intestazione, Piepagina, IntestazioneColore, IntestazioneFontSize, IntestazioneAllineamento, PiepaginaColore, PiepaginaFontSize, PiepaginaAllineamento, Logo)
				SELECT @idAzienda, IdLayout, Intestazione, PiePagina, IntestazioneColore, IntestazioneFontSize, IntestazioneAllineamento, PiePaginaColore, PiePaginaFontSize, PiePaginaAllineamento, @Logo
				FROM dbo.ufnSediReport_get_Layout(@idAzienda);
		COMMIT TRANSACTION;

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
		THROW 50001, @returnMessage, 1;
	END
END;
GO
