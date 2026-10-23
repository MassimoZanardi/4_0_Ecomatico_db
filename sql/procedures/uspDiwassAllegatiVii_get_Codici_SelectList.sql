SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Codici internazionali del rifiuto per l'Allegato VII (Id = "lista|codice"): prima i suggeriti per l'EER
-- (tblDiwassCodiciRifiutiEer), poi tutti gli altri della lista verde (Basel B, OCSE G.., allegati IIIA e IIIB: i codici OCSE A..
-- e R.. sono della lista ambra, fuori dall'Allegato VII). @Search filtra su "codice - descrizione"; "(Selezionare)" e il
-- codice selezionato restano sempre in elenco
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_get_Codici_SelectList]
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdSelected NVARCHAR(40) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

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
				Id = CAST('' AS NVARCHAR(40)),
				[Text] = CAST(N'(Selezionare)' AS NVARCHAR(300)),
				Selected = CAST(IIF(@IdSelected IS NULL, 1, 0) AS BIT),
				Gruppo = 0,
				Pos = 0

			UNION ALL -- rami mutualmente esclusivi: suggeriti (Gruppo 1) e altri (Gruppo 2)

			SELECT
				Id = CAST(c.Lista + '|' + c.Codice AS NVARCHAR(40)),
				[Text] = CAST(IIF(g.IdEer IS NULL, N'', N'★ ') + c.Codice + N' - ' + LEFT(c.Descrizione, 200) AS NVARCHAR(300)),
				Selected = CAST(IIF(c.Lista + '|' + c.Codice = @IdSelected, 1, 0) AS BIT),
				Gruppo = IIF(g.IdEer IS NULL, 2, 1),
				Pos = ISNULL(g.Pos, 0)
			FROM
				dbo.tblDiwassCodiciRifiuti c
				LEFT JOIN dbo.tblDiwassCodiciRifiutiEer g ON c.Lista = g.Lista AND c.Codice = g.Codice AND g.IdEer = @IdEer
			WHERE
				c.Lista + '|' + c.Codice = @IdSelected
				OR
					(
						(
						c.Lista IN ('basel_b', 'wsr_a3a', 'wsr_a3b')
						OR
							(
							c.Lista = 'oecd'
							AND c.Codice LIKE 'G%'
							)
						)
					AND
						(
						@Search IS NULL
						OR c.Codice + N' - ' + c.Descrizione LIKE N'%' + @Search + N'%'
						)
					)
		)
		SELECT
			Id,
			[Text],
			Selected
		FROM cte
		ORDER BY Gruppo, Pos, Id
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
