SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Credenziali DIWASS attive del dominio della sessione, da associare a un'azienda in Diwass > Aziende. La prima voce
-- "(Nessuna)" toglie l'associazione; @Search filtra per nome o utente EU Login
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAziende_get_Credenziali_SelectList]
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

		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);
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
			@IdFunzione = 'DWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Nessuna)' AS VARCHAR(200)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- credenziale selezionata: sempre presente, anche se non combacia con @Search

			SELECT
				c.Id,
				[Text] = CAST(c.Nome + ISNULL(' (' + h.Username + ')', '') AS VARCHAR(200)),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM
				dbo.tblDiwassCredenziali c
				INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
				LEFT JOIN [1_0_diwass]..tblCredenziali h ON c.IdDiwass = h.Id
			WHERE
				e.Id = @IdSessione
				AND c.Id = @IdSelected
			UNION ALL -- altre credenziali attive del dominio, con l'utente EU Login per distinguerle

			SELECT
				c.Id,
				[Text] = CAST(c.Nome + ISNULL(' (' + h.Username + ')', '') AS VARCHAR(200)),
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblDiwassCredenziali c
				INNER JOIN dbo.tblSessioni e ON c.IdDominio = e.IdDominio
				LEFT JOIN [1_0_diwass]..tblCredenziali h ON c.IdDiwass = h.Id
			WHERE
				e.Id = @IdSessione
				AND c.Lock = 0
				AND c.Id <> @IdSelected
				AND
					(
					@Search IS NULL
					OR c.Nome LIKE '%' + @Search + '%'
					OR h.Username COLLATE DATABASE_DEFAULT LIKE '%' + @Search + '%'
					)
		)
		SELECT TOP 20
			Id,
			[Text],
			Selected
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
