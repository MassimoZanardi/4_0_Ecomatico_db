SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get_LottiSelectList
	@IdSede CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdMateriale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMateriale non può essere vuoto';
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
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sulla sede indicata
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
			WHERE i.Id = @IdSede)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(500)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- lotto selezionato: sempre presente, anche se non combacia con @Search o è nel frattempo chiuso/disabilitato

			SELECT
				l.Id,
				[Text] = l.Nome,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblEoWLotti l
			WHERE
				l.Id = @IdSelected
				AND l.IdSede = @IdSede
				AND l.IdMateriale = @IdMateriale

			UNION ALL -- altri lotti aperti/non disabilitati della sede per quel materiale, filtrabili per @Search

			SELECT
				l.Id,
				[Text] = l.Nome,
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM dbo.tblEoWLotti l
			WHERE
				l.IdSede = @IdSede
				AND l.IdMateriale = @IdMateriale
				AND l.Lock = 0
				AND ISNULL(l.Disabilitato, 0) = 0
				AND l.DataChiusura IS NULL
				AND l.Id <> @IdSelected
				AND
					(
					@Search IS NULL
					OR l.Nome LIKE '%' + @Search + '%'
					)
		)
		SELECT TOP 20 Id, [Text], Selected
		FROM cte
		ORDER BY Pos, [Text]
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
