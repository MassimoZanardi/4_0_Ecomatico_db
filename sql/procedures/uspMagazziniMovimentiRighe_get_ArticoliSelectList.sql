SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_get_ArticoliSelectList
	@IdMovimento CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMovimento non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Articoli della stessa azienda del movimento, non della sessione (evita di
		-- affidarsi a tblSessioni.IdAzienda se l'utente ha cambiato contesto nel frattempo)
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = c.IdSede
		FROM
			dbo.tblMagazziniMovimenti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @IdMovimento
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SELECT TOP (0) Id = CAST(NULL AS CHAR(16)), [Text] = CAST(NULL AS VARCHAR(120)), Selected = CAST(0 AS BIT);
			GOTO BRANCH_END;
		END

		SELECT TOP (50)
			a.Id,
			[Text] = a.Nome + ISNULL(' (' + a.Codice + ')', ''),
			Selected = CAST(IIF(a.Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblMagazziniArticoli a
		WHERE
			a.IdSede = @idAzienda
			AND a.Lock = 0
			AND (@Search IS NULL OR a.Nome LIKE '%' + @Search + '%' OR a.Codice LIKE '%' + @Search + '%')
		ORDER BY a.Nome
		OPTION (RECOMPILE);

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
