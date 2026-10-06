SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_get_Soggetti_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: basta la lettura su clienti (ANC) o fornitori (ANF)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'ANF',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		-- Solo i soggetti di cui l'azienda del contesto è proprietaria: quelli visti tramite un'area
		-- appartengono a un'altra azienda e non possono diventare clienti o fornitori
		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(500)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- soggetto selezionato: sempre presente, anche se disabilitato o fuori da @Search

			SELECT
				s.Id,
				[Text] = CAST(s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') AS VARCHAR(500)),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM
				dbo.tblSedi s
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				e.Id = @IdSessione
				AND s.Id = @IdSelected
				AND s.InternaEsterna = 'E'
				AND s.IdParent IS NULL
				AND s.Lock = 0

			UNION ALL -- altri soggetti attivi dell'azienda, filtrabili per @Search

			SELECT
				s.Id,
				[Text] = CAST(s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') AS VARCHAR(500)),
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblSedi s
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				e.Id = @IdSessione
				AND s.InternaEsterna = 'E'
				AND s.IdParent IS NULL
				AND s.Lock = 0
				AND ISNULL(s.Disabilitata, 0) = 0
				AND s.Id <> @IdSelected
				AND
					(
					@Search IS NULL
					OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%'
					OR s.PartitaIva LIKE '%' + @Search + '%'
					OR s.CodiceFiscale LIKE '%' + @Search + '%'
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
