SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Aliquote di sistema (IdSede NULL, sola lettura) più quelle dell'azienda interna corrente della
		-- sessione, dalla più alta alla più bassa; senza azienda nel contesto nessuna riga
		SELECT
			a.Id,
			StatoValore = 0,
			StatoDescrizione = 'OK',
			a.Nome,
			a.Codice,
			a.Valore,
			TipoNome = t.Nome,
			a.IdNatura,
			NaturaNome = n.Nome,
			IsSistema = CAST(IIF(a.IdSede IS NULL, 1, 0) AS BIT),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblAliquoteIva a
			INNER JOIN dbo.tblSessioni e ON a.IdSede IS NULL OR a.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblAliquoteIvaTipi t ON a.IdTipo = t.Id
			LEFT JOIN dbo.tblAliquoteIvaNatura n ON a.IdNatura = n.Id
		WHERE
			e.Id = @IdSessione
			AND e.IdAzienda IS NOT NULL
			AND a.Lock = 0
			AND (@Search IS NULL OR a.Nome LIKE '%' + @Search + '%' OR a.Codice LIKE '%' + @Search + '%')
		ORDER BY a.Valore DESC, a.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
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
GO
