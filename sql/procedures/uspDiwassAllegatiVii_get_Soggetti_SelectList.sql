SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Soggetti proponibili in un Allegato VII: sedi del contesto o condivise (ufnDiwassOperatori_get_SediBySessione_List)
-- collegate a DIWASS con il ruolo WSR nuovo o valido. @IdSelected resta in elenco anche se nel frattempo non lo è più
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Soggetti_SelectList]
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), REPLICATE('0', 16));

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
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		;WITH cte AS (
			SELECT
				Id = CAST(REPLICATE('0', 16) AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(400)),
				Selected = CAST(IIF(@IdSelected = REPLICATE('0', 16), 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- rami mutualmente esclusivi per Id e Pos

			SELECT
				s.Id,
				[Text] = CAST(ISNULL(p.NomeCompleto + ' - ', '') + s.NomeCompleto + ' (' + s.IndirizzoCompleto + ')' AS VARCHAR(400)),
				Selected = CAST(IIF(s.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM
				dbo.ufnDiwassOperatori_get_SediBySessione_List(@IdSessione) v
				INNER JOIN dbo.tblSedi s ON v.Id = s.Id
				INNER JOIN dbo.tblDiwassOperatori o ON s.Id = o.Id
				LEFT JOIN dbo.tblSedi p ON s.IdParent = p.Id
			WHERE
				o.Stato IN ('NEW', 'VALID')
				OR s.Id = @IdSelected
		)
		SELECT
			Id,
			[Text],
			Selected
		FROM cte
		ORDER BY Pos, [Text];

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
