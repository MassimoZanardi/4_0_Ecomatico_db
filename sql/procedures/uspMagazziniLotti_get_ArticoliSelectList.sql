SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniLotti_get_ArticoliSelectList
	@IdSede CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
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

		-- Elenco Articoli filtrato sulla stessa Azienda a cui appartiene la Sede indicata
		-- (Sede stessa se è l'Azienda, oppure la Sede padre se è una sede figlia), non su
		-- tblSessioni.IdAzienda: questa pagina lavora nel contesto Contesto.Sede, non Azienda.
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = CASE WHEN s.IdParent IS NULL THEN s.Id ELSE s.IdParent END
		FROM
			dbo.tblSedi s
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON s.Id = i.Id
		WHERE s.Id = @IdSede;

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
