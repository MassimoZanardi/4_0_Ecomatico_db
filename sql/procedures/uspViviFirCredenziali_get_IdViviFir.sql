SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Id della riga dell'hub [1_0_vivifir]..tblCredenziali di una credenziale (Verifica connessione)
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirCredenziali_get_IdViviFir]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità), stesso pattern di uspViviFirCredenziali_get
		DECLARE @idViviFir CHAR(16);
		SELECT @idViviFir = c.IdViviFir
		FROM
			dbo.tblViviFirCredenziali c
			INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
		WHERE
			c.Id = @Id
			AND c.Lock <= 2
			AND e.Id = @IdSessione;

		IF @@ROWCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Credenziale non trovata';
			GOTO BRANCH_END;
		END

		IF @idViviFir IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Salvare la credenziale prima di verificare la connessione';
			GOTO BRANCH_END;
		END

		SELECT rtn = @idViviFir;

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
