SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMud_get_UnitaLocale_SelectList]
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

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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
			@IdFunzione = 'MUD',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16), @idAzienda CHAR(16);
		SELECT
			@idUtente = IdUtente,
			@idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- unità locale selezionata: sempre presente, anche se non combacia con @Search
			-- (sia sedi interne che esterne della stessa azienda interna: uno studio/
			-- azienda può dichiarare il MUD anche per conto di aziende esterne gestite)

			SELECT
				s.Id,
				[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM
				dbo.ufnSedi_get_SediByUtente_List(@idUtente) i
				INNER JOIN dbo.tblSedi s ON i.Id = s.Id
			WHERE
				i.IdAziendaInterna = @idAzienda
				AND s.Id = @IdSelected

			UNION ALL -- altre sedi (interne ed esterne) della stessa azienda interna, filtrabili per @Search

			SELECT
				s.Id,
				[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.ufnSedi_get_SediByUtente_List(@idUtente) i
				INNER JOIN dbo.tblSedi s ON i.Id = s.Id
			WHERE
				i.IdAziendaInterna = @idAzienda
				AND s.Id <> @IdSelected
				AND
					(
					@Search IS NULL
					OR s.NomeCompleto + ' ' + s.IndirizzoCompleto LIKE '%' + @Search + '%'
					)
		)
		SELECT TOP 50 Id, [Text], Selected
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
