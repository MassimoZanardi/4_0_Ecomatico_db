SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_get_LottiSelectList
	@Id CHAR(16) = NULL,
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

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
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
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati dell'allocazione
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Materiale già fissato dai lotti presenti nell'allocazione, NULL se ancora nessuno
		DECLARE @idMateriale CHAR(2) = (
			SELECT TOP 1 l.IdMateriale
			FROM dbo.tblEoWLottiAllocazioni la
			INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
			WHERE la.IdAllocazione = @Id
		);

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(500)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- lotto selezionato: sempre presente, anche se non combacia con @Search

			SELECT
				l.Id,
				[Text] = l.Nome,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblEoWLotti l
			WHERE
				l.Id = @IdSelected
				AND l.IdSede = @idSede

			UNION ALL -- altri lotti aperti/non disabilitati della sede, stesso materiale degli altri
			          -- lotti già in allocazione (o qualsiasi se nessuno ancora presente), non già
			          -- inseriti in questa allocazione, filtrabili per @Search

			SELECT
				l.Id,
				[Text] = l.Nome,
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM dbo.tblEoWLotti l
			WHERE
				l.IdSede = @idSede
				AND l.Lock = 0
				AND ISNULL(l.Disabilitato, 0) = 0
				AND l.DataChiusura IS NULL
				AND (@idMateriale IS NULL OR l.IdMateriale = @idMateriale)
				AND l.Id <> @IdSelected
				AND NOT EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id AND IdLotto = l.Id)
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
