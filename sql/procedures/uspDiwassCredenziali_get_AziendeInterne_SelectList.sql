SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Aziende interne proponibili per una credenziale DIWASS: quelle visibili all'utente della sessione che non hanno già
-- un'altra credenziale attiva (una sola per azienda). @IdSelected è l'azienda della credenziale aperta
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassCredenziali_get_AziendeInterne_SelectList]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
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
				Id = CAST(REPLICATE('0', 16) AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
				Selected = CAST(IIF(@IdSelected = REPLICATE('0', 16), 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- rami mutualmente esclusivi per Id e Pos

			SELECT
				s.Id,
				[Text] = CAST(s.NomeCompleto + ' ' + s.IndirizzoCompleto AS VARCHAR(200)),
				Selected = CAST(IIF(s.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
				INNER JOIN dbo.tblSedi s ON i.Id = s.Id
			WHERE
				e.Id = @IdSessione
				AND i.IdDominio = e.IdDominio
				AND NOT EXISTS (
					SELECT 1
					FROM dbo.tblDiwassCredenziali c
					WHERE
						c.IdAziendaInterna = s.Id
						AND c.Lock = 0
						AND (@Id IS NULL OR c.Id <> @Id)
				)
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
