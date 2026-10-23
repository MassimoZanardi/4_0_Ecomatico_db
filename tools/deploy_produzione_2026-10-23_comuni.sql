/*
Deploy produzione 2026-10-23 - Ricerca dei comuni nelle select degli indirizzi

Rieseguibile, indipendente dagli script DIWASS. Eseguire con sqlcmd -f 65001 -I -b (oppure da SSMS) sul DB 4_0_ecomatico.
Non serve pubblicare l'app.

uspComuni_get_SelectList: con il testo di ricerca ordina per pertinenza (nome uguale, poi che inizia con il testo, poi
che lo contiene, infine i comuni trovati solo per la provincia). Prima "Milano" mostrava solo i primi comuni della
provincia di Milano in ordine alfabetico e il comune di Milano restava fuori dalle 10 righe proposte.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Comuni per le select degli indirizzi (prime 10 righe). Con @Search, ordine per pertinenza: nome uguale al testo, poi
-- che inizia con il testo, poi che lo contiene, infine i comuni trovati solo per la provincia (così "Milano" propone
-- per primo il comune, non i comuni della provincia di Milano in ordine alfabetico)
CREATE OR ALTER PROCEDURE [dbo].[uspComuni_get_SelectList]
	@IdSelected CHAR(6) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Normalizza: NULL → '000000' (nessuna selezione)
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), REPLICATE('0', 6));
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		WITH cte AS (
			-- Opzione vuota sempre in cima
			SELECT
				Id = CAST('000000' AS CHAR(6)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
				Selected = CAST(0 AS BIT),
				Pos = 0,
				Pertinenza = 0

			UNION ALL -- rami mutualmente esclusivi per Id e Pos

			-- Comune selezionato: appare sempre
			SELECT
				c.Id,
				[Text] = c.Nome + ' (' + ISNULL(p.Nome, '') + ' - ' + ISNULL(p.Sigla, '') + ')',
				Selected = CAST(1 AS BIT),
				Pos = 1,
				Pertinenza = 0
			FROM
				dbo.tblComuni c
				LEFT JOIN dbo.tblProvince p ON c.IdProvincia = p.Id
			WHERE
				c.Id = @IdSelected
				AND c.Id <> REPLICATE('0', 6) -- esclude il caso nessuna selezione
			UNION ALL

			-- Altri comuni: filtrati per @Search o tutti se NULL
			SELECT
				c.Id,
				[Text] = c.Nome + ' (' + ISNULL(p.Nome, '') + ' - ' + ISNULL(p.Sigla, '') + ')',
				Selected = CAST(0 AS BIT),
				Pos = 2,
				Pertinenza = CASE
					WHEN @Search IS NULL THEN 0
					WHEN c.Nome = @Search THEN 0
					WHEN c.Nome LIKE @Search + '%' THEN 1
					WHEN c.Nome LIKE '%' + @Search + '%' THEN 2
					ELSE 3
				END
			FROM
				dbo.tblComuni c
				LEFT JOIN dbo.tblProvince p ON c.IdProvincia = p.Id
			WHERE
				c.Id <> @IdSelected
				AND
					(
					@Search IS NULL
					OR c.Nome LIKE '%' + @Search + '%'
					OR p.Nome LIKE '%' + @Search + '%'
					)
		)
		SELECT TOP 10
			Id,
			[Text],
			Selected
		FROM cte
		ORDER BY Pos, Pertinenza, [Text]
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
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
