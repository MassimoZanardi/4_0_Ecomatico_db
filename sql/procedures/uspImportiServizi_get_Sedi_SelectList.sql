SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select dei soggetti e delle sedi per le variabili di un importo dei servizi. La prima voce (Id a zeri) significa
-- "qualsiasi": la variabile non viene confrontata con il servizio.
--   @Livello = 'A': solo i soggetti (aziende, sedi radice): richiedente
--   @Livello = 'S': il soggetto @IdParent e le sue sedi: sede richiedente (senza @IdParent solo la prima voce)
--   @Livello = 'T': soggetti e sedi (non usato dagli importi dei servizi)
-- Visibilità come uspSedi_get_Sedi_SelectList: anagrafiche dell'azienda interna corrente della sessione o
-- condivise nel dominio tramite un'area. La voce selezionata è sempre presente, anche se disabilitata, fuori
-- dalla ricerca o oltre le prime 50.
CREATE OR ALTER PROCEDURE dbo.uspImportiServizi_get_Sedi_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Livello CHAR(1) = 'T',
	@IdParent CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Livello = ISNULL(NULLIF(UPPER(LTRIM(RTRIM(@Livello))), ''), 'T');
		SET @IdParent = NULLIF(NULLIF(LTRIM(RTRIM(@IdParent)), ''), @idSediciZeri);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Livello NOT IN ('A', 'S', 'T')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Livello deve essere A, S o T';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Servizi sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('SRV', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST(IIF(@Livello = 'S', '(Tutte)', '(Tutti)') AS VARCHAR(400)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0
			UNION ALL
			SELECT
				s.Id,
				[Text] = CAST(s.NomeCompleto + IIF(@Livello = 'A', '', ISNULL(' ' + s.IndirizzoCompleto, '')) AS VARCHAR(400)),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblSedi s
			WHERE
				s.Id = @IdSelected
				AND s.Id <> @idSediciZeri
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
						[Text] = CAST(s.NomeCompleto + IIF(@Livello = 'A', '', ISNULL(' ' + s.IndirizzoCompleto, '')) AS VARCHAR(400))
					FROM
						dbo.tblSessioni e
						CROSS APPLY dbo.ufnSedi_get_SediByUtente_List(e.IdUtente) u
						INNER JOIN dbo.tblSedi s ON u.Id = s.Id
					WHERE
						e.Id = @IdSessione
						AND
							(
								(
								u.IdDominio = e.IdDominio
								AND u.Condivisa = 1
								)
							OR u.IdAziendaInterna = e.IdAzienda
							)
						AND u.Disabilitata = 0
						AND s.Id <> @IdSelected
						AND
							(
							@Livello = 'T'
							OR (@Livello = 'A' AND u.IdParent IS NULL)
							OR (@Livello = 'S' AND (u.Id = @IdParent OR u.IdParent = @IdParent))
							)
						AND
							(
							@Search IS NULL
							OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%'
							)
					ORDER BY s.NomeCompleto, s.IndirizzoCompleto
				) t
		)
		SELECT
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
