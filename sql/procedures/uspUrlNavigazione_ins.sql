CREATE OR ALTER PROCEDURE [dbo].[uspUrlNavigazione_ins]
	@IdSessione CHAR(16) = NULL,
	@UrlPartenza VARCHAR(2000) = NULL,
	@UrlDestinazione VARCHAR(2000) = NULL,
	@IsUrlRadice BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametri
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @UrlPartenza = dbo.ufnStringhe_get_SenzaSpazi(@UrlPartenza, 0, 1);
		SET @UrlDestinazione = dbo.ufnStringhe_get_SenzaSpazi(@UrlDestinazione, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @UrlPartenza IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @UrlPartenza non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @UrlDestinazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @UrlDestinazione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Rimuove handler tecnico dall'URL di partenza
		SET @UrlPartenza = REPLACE(@UrlPartenza, '&handler=open', '');

		BEGIN TRANSACTION;
			-- Se URL radice: azzera lo storico della sessione
			IF @IsUrlRadice = 1
				DELETE dbo.tblUrlNavigazione
				WHERE IdSessione = @IdSessione;

			-- Inserisce la nuova voce con posizione = max + 1
			INSERT INTO dbo.tblUrlNavigazione
				(IdSessione, Pos, UrlPartenza, UrlDestinazione)
			SELECT
				@IdSessione,
				Pos = ISNULL((MAX(Pos) + 1), 0),
				@UrlPartenza,
				@UrlDestinazione
			FROM dbo.tblUrlNavigazione
			WHERE IdSessione = @IdSessione;
		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
