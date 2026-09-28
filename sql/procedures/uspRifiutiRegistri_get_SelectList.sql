CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistri_get_SelectList]
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
			@IdFunzione = 'RRT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Se @IdSelected non fornito, usa il registro della sessione corrente
		-- oppure l'opzione vuota (REPLICATE('0',16))
		SELECT @IdSelected =
			COALESCE(
				@IdSelected,
				(SELECT s.IdRegistro
				 FROM
					 dbo.tblSessioni s
					 INNER JOIN dbo.tblRifiutiRegistri r ON s.IdRegistro = r.Id
				 WHERE
					 s.Id = @IdSessione
					 AND r.Lock = 0
				),
				REPLICATE('0', 16)
			);

		SELECT TOP 20
			Id,
			[Text],
			Selected
		FROM (
			SELECT
				Id = CAST(REPLICATE('0', 16) AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(500)),
				Selected = CAST(IIF(@IdSelected = REPLICATE('0', 16), 1, 0) AS BIT),
				Pos = 0
			UNION ALL
			SELECT
				r.Id,
				[Text] = r.Nome + ' - ' + s.Nome + ' ' + s.IndirizzoCompleto,
				Selected = CAST(IIF(r.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM
				dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
				INNER JOIN dbo.tblRifiutiRegistri r ON i.Id = r.IdSede
				INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id
			WHERE
				r.Lock = 0
				AND
					(
					@Search IS NULL
					OR (r.Nome + ' - ' + s.Nome + ' ' + s.IndirizzoCompleto) LIKE '%' + @Search + '%'
					)
		) x
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
