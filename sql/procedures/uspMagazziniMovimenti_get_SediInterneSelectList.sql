SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimenti_get_SediInterneSelectList
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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

		-- Sedi della stessa azienda interna della sessione (l'azienda stessa e le sue sedi
		-- figlie): usata per scegliere la Sede interna del DDT prima che il Movimento esista,
		-- pertanto non richiede @IdMovimento a differenza di uspMagazziniMovimentiRighe_get_SediSelectList
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda FROM dbo.tblSessioni WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SELECT TOP (0) Id = CAST(NULL AS CHAR(16)), [Text] = CAST(NULL AS VARCHAR(401)), Selected = CAST(0 AS BIT);
			GOTO BRANCH_END;
		END

		SELECT TOP (50)
			s.Id,
			[Text] = s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, ''),
			Selected = CAST(IIF(s.Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblSedi s
		WHERE
			(s.Id = @idAzienda OR s.IdParent = @idAzienda)
			AND ISNULL(s.Disabilitata, 0) = 0
			AND (@Search IS NULL OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%')
		ORDER BY s.NomeCompleto
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
