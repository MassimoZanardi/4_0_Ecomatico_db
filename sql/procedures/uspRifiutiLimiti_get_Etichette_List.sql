SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiLimiti_get_Etichette_List]
	@Id CHAR(16) = NULL,
	@DaAssociare BIT = 0,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RLM',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sul limite padre + recupero IdSede (le etichette sono scopate per sede)
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblRifiutiLimiti c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Ramo 1: etichette già associate al limite
		IF @DaAssociare = 0
		BEGIN
			SELECT
				e.Id,
				e.Nome,
				e.Descrizione,
				Colore = IIF(e.Visualizzazione = 'C', c.Hex, c.Css),
				e.Visualizzazione
			FROM
				dbo.tblRifiutiLimitiEtichette a
				INNER JOIN dbo.tblEtichette e ON a.IdEtichetta = e.Id
				INNER JOIN dbo.tblColori c ON e.IdColore = c.Id
			WHERE a.IdLimite = @Id
			ORDER BY
				e.Nome;
		END

		-- Ramo 2: etichette della sede/modulo Rifiuti non ancora associate, con filtro @Search opzionale
		ELSE
		BEGIN
			SELECT TOP 50
				e.Id,
				e.Nome,
				e.Descrizione,
				Colore = IIF(e.Visualizzazione = 'C', c.Hex, c.Css),
				e.Visualizzazione
			FROM
				dbo.tblEtichette e
				INNER JOIN dbo.tblColori c ON e.IdColore = c.Id
			WHERE
				e.IdSede = @idSede
				AND e.IdModulo = 'RIF'
				AND e.Lock = 0
				AND e.Id NOT IN (SELECT IdEtichetta FROM dbo.tblRifiutiLimitiEtichette WHERE IdLimite = @Id)
				AND
					(
					@Search IS NULL
					OR e.Nome LIKE '%' + @Search + '%'
					OR e.Descrizione LIKE '%' + @Search + '%'
					)
			ORDER BY
				e.Nome;
		END

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
GO
