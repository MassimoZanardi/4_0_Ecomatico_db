CREATE OR ALTER PROCEDURE [dbo].[uspUrlNavigazione_get]
	@IdSessione CHAR(16) = NULL,
	@UrlDestinazione VARCHAR(2000) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	SET DATEFORMAT YMD;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @UrlDestinazione = dbo.ufnStringhe_get_SenzaSpazi(@UrlDestinazione, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @UrlDestinazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @UrlDestinazione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Normalizza: minuscolo e rimuove query-string
		SET @UrlDestinazione = LOWER(@UrlDestinazione);
		DECLARE @index INT = CHARINDEX('?', @UrlDestinazione);
		IF @index > 0
			SET @UrlDestinazione = LEFT(@UrlDestinazione, @index - 1);

		DECLARE @urlPartenza VARCHAR(2000);
		DECLARE @IsUrlRadice BIT;
		DECLARE @pos TINYINT;
		DECLARE @trovato INT = 0;

		-- Cerca l'URL di destinazione esatto nello storico della sessione
		SELECT TOP 1
			@urlPartenza = UrlPartenza,
			@IsUrlRadice = 0,
			@pos = Pos,
			@trovato = 1
		FROM dbo.tblUrlNavigazione
		WHERE
			IdSessione = @IdSessione
			AND UrlDestinazione = @UrlDestinazione
		ORDER BY Pos DESC;

		-- Se non trovato cerca l'URL radice (ultimo elemento dello storico)
		IF @trovato = 0
		BEGIN
			SELECT TOP 1
				@urlPartenza = UrlPartenza,
				@UrlDestinazione = NULL,
				@IsUrlRadice = 1,
				@pos = 0
			FROM dbo.tblUrlNavigazione
			WHERE IdSessione = @IdSessione
			ORDER BY Pos DESC;
		END

		IF @urlPartenza IS NULL
		BEGIN
			-- Nessuno storico: usa la destinazione come partenza
			SET @urlPartenza = @UrlDestinazione;
		END
		ELSE
		BEGIN
			-- Rimuove le voci dello storico dalla posizione corrente in poi
			DELETE dbo.tblUrlNavigazione
			WHERE
				IdSessione = @IdSessione
				AND Pos >= @pos;
		END

		SELECT
			IdSessione = @IdSessione,
			UrlPartenza = @urlPartenza,
			UrlDestinazione = @UrlDestinazione,
			IsUrlRadice = @IsUrlRadice;

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
