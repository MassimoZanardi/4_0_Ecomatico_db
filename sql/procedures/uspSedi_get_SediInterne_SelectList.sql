CREATE PROCEDURE [dbo].[uspSedi_get_SediInterne_SelectList]
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Determina la selezione corrente: parametro → sede della sessione → nessuna
		SET @IdSelected = COALESCE(
			NULLIF(LTRIM(RTRIM(@IdSelected)), ''),
			(SELECT s.Id
			FROM dbo.tblSessioni e
			INNER JOIN dbo.tblSedi s ON e.IdSede = s.Id
			 WHERE
				 e.Id = @IdSessione
				 AND s.Lock = 0
			),
			REPLICATE('0', 16)
		);

		;WITH cte AS (
			-- Opzione vuota sempre in cima
			SELECT
				Id = CAST(REPLICATE('0', 16) AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
				Selected = CAST(0 AS BIT),
				Pos = 0

			UNION ALL -- rami mutualmente esclusivi per Id e Pos

			-- Sede interna selezionata: appare sempre
			SELECT
				s.Id,
				[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblSedi s
			WHERE
				s.Id = @IdSelected
				AND s.Id <> REPLICATE('0', 16)
			UNION ALL

			-- Altre sedi interne accessibili dall'utente della sessione
			SELECT
				s.Id,
				[Text] = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblSessioni e
			CROSS APPLY dbo.ufnSedi_get_SediInterneByUtente_List(e.IdUtente) i
			INNER JOIN dbo.tblSedi s ON i.Id = s.Id
			WHERE
				e.Id = @IdSessione
				AND s.Id <> @IdSelected
				AND (@Search IS NULL OR s.NomeCompleto + ' ' + s.IndirizzoCompleto LIKE '%' + @Search + '%')
		)
		SELECT TOP 50
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
		THROW 50001, @returnMessage, 1
	END

END;
