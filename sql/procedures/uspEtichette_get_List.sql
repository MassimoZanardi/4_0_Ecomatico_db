CREATE OR ALTER PROCEDURE [dbo].[uspEtichette_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdModulo = NULLIF(LTRIM(RTRIM(@IdModulo)), '');
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdModulo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ETC',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF dbo.ufnModuli_get_IsAttivoBySessione(@IdModulo, @IdSessione) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		SELECT
			a.Id,
			StatoValore = 0,
			StatoDescrizione = CAST('OK' AS VARCHAR(50)),
			a.Nome,
			a.Descrizione,
			Colore = c.Nome,
			Anteprima = (
				SELECT
					e.Nome,
					Colore = IIF(e.Visualizzazione = 'C', c2.Hex, c2.Css),
					e.Descrizione,
					e.Visualizzazione
				FROM
					dbo.tblEtichette e
					INNER JOIN dbo.tblColori c2 ON e.IdColore = c2.Id
				WHERE a.Id = e.Id FOR JSON PATH),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblEtichette a
			INNER JOIN dbo.tblSessioni e ON a.IdSede = e.IdSede
			LEFT JOIN dbo.tblColori c ON a.IdColore = c.Id
		WHERE
			e.Id = @IdSessione
			AND a.IdModulo = @IdModulo
			AND a.Lock = 0
			AND
				(
				@Search IS NULL
				OR a.Nome LIKE '%' + @Search + '%'
				)
		ORDER BY a.Nome
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
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
