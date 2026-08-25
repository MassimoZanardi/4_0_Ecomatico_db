SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiLimiti_get_Eer_List]
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

		-- Titolarità sul limite padre
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiLimiti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Ramo 1: EER già associati al limite
		IF @DaAssociare = 0
		BEGIN
			SELECT
				e.Id,
				Nome = e.Nome + IIF(e.Pericoloso = 1, '*', ''),
				e.Descrizione,
				e.Pericoloso
			FROM
				dbo.tblRifiutiLimitiEer a
				INNER JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
			WHERE a.IdLimite = @Id
			ORDER BY
				e.Id;
		END

		-- Ramo 2: EER non ancora associati (da associare), con filtro @Search opzionale
		ELSE
		BEGIN
			SELECT TOP 50
				Id,
				Nome = Nome + IIF(Pericoloso = 1, '*', ''),
				Descrizione,
				Pericoloso
			FROM
				dbo.tblRifiutiEer
			WHERE
				Id NOT IN (SELECT IdEer FROM dbo.tblRifiutiLimitiEer WHERE IdLimite = @Id)
				AND
					(
					@Search IS NULL
					OR Nome LIKE '%' + @Search + '%'
					OR Descrizione LIKE '%' + @Search + '%'
					)
			ORDER BY
				Id;
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
