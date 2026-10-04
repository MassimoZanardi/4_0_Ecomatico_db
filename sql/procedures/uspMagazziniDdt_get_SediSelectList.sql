SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniDdt_get_SediSelectList
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Destinatario/Trasportatore possono essere qualunque anagrafica (anche esterna:
		-- clienti, fornitori, trasportatori) gestita dall'azienda interna corrente
		-- Nome + indirizzo come la select delle sedi interne del contesto (uspSedi_get_SediInterne_SelectList).
		-- L'anagrafica selezionata è sempre presente e per prima, anche se disabilitata, fuori dalla
		-- ricerca o oltre le prime 50: altrimenti la select perderebbe il valore corrente.
		SELECT
			x.Id,
			x.[Text],
			x.Selected
		FROM
			(
				SELECT
					s.Id,
					[Text] = s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, ''),
					Selected = CAST(1 AS BIT),
					Pos = 1
				FROM
					dbo.tblSedi s
					INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
				WHERE
					e.Id = @IdSessione
					AND s.Id = @IdSelected

				UNION ALL

				SELECT
					t.Id,
					t.[Text],
					Selected = CAST(0 AS BIT),
					Pos = 2
				FROM
					(
						SELECT TOP (50)
							s.Id,
							[Text] = s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '')
						FROM
							dbo.tblSedi s
							INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
						WHERE
							e.Id = @IdSessione
							AND ISNULL(s.Disabilitata, 0) = 0
							AND (@IdSelected IS NULL OR s.Id <> @IdSelected)
							AND (@Search IS NULL OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%')
						ORDER BY s.NomeCompleto
					) t
			) x
		ORDER BY x.Pos, x.[Text]
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
