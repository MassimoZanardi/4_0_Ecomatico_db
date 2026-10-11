SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Numero VARCHAR(30) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdTipo CHAR(4) = NULL,
	@IdStato CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Numero = NULLIF(LTRIM(RTRIM(@Numero)), '');
		SET @IdTipo = NULLIF(NULLIF(LTRIM(RTRIM(@IdTipo)), ''), REPLICATE('0', 4));
		SET @IdStato = NULLIF(NULLIF(LTRIM(RTRIM(@IdStato)), ''), '0');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'F')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (cliente) o F (fornitore)';
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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga.
		-- @Numero cerca nel numero della fattura e, per i fornitori, nel numero del loro documento.
		-- Stato della riga: avviso se la fattura non ha righe con importi o se ha rate la cui somma è diversa
		-- dal netto a pagare (una fattura senza rate non è segnalata).
		-- Prima si filtra e si prende la pagina, con le sole colonne di filtro e ordinamento (quelle
		-- dell'indice delle fatture); poi, solo per le fatture della pagina, si leggono le altre colonne
		-- e si calcolano totali e rate
		;WITH pagina AS (
			SELECT
				f.Id,
				f.Numero,
				f.DataEmissione,
				s.NomeCompleto,
				RowsCount = COUNT(*) OVER ()
			FROM
				dbo.tblFatture f
				INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
			WHERE
				e.Id = @IdSessione
				AND f.Tipo = @Tipo
				AND f.Lock = 0
				AND (@Nome IS NULL OR s.NomeCompleto LIKE '%' + @Nome + '%')
				AND
					(
					@Numero IS NULL
					OR CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, '') LIKE @Numero + '%'
					OR f.NumeroFornitore LIKE '%' + @Numero + '%'
					)
				AND (@DataDa IS NULL OR f.DataEmissione >= @DataDa)
				AND (@DataA IS NULL OR f.DataEmissione <= @DataA)
				AND (@IdTipo IS NULL OR f.IdTipo = @IdTipo)
				AND (@IdStato IS NULL OR f.IdStato = @IdStato)
			ORDER BY
				f.DataEmissione DESC,
				f.Numero DESC,
				f.Id
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
		)
		SELECT
			g.Id,
			StatoValore = CASE WHEN t.Totale = 0 OR (z.Numero > 0 AND z.Importo <> t.NettoAPagare) THEN 1 ELSE 0 END,
			StatoDescrizione =
				CASE
					WHEN t.Totale = 0 THEN 'Fattura senza importi'
					WHEN z.Numero > 0 AND z.Importo <> t.NettoAPagare THEN 'Le rate non corrispondono al netto a pagare'
					ELSE 'OK'
				END,
			f.Numero,
			f.Sezionale,
			f.NumeroFornitore,
			f.DataEmissione,
			f.DataRegistrazione,
			f.IdTipo,
			TipoNome = p.Nome,
			f.IdStato,
			StatoNome = a.Nome,
			g.NomeCompleto,
			t.Imponibile,
			t.Iva,
			t.Totale,
			t.NettoAPagare,
			SolaLettura = ISNULL(f.SolaLettura, 0),
			g.RowsCount
		FROM
			pagina g
			INNER JOIN dbo.tblFatture f ON g.Id = f.Id
			LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
			LEFT JOIN dbo.tblFattureStati a ON f.IdStato = a.Id
			OUTER APPLY dbo.ufnFatture_get_Totali(g.Id) t
			OUTER APPLY (SELECT Numero = COUNT(*), Importo = ISNULL(SUM(q.Importo), 0) FROM dbo.tblFattureRate q WHERE q.IdFattura = g.Id) z
		ORDER BY
			g.DataEmissione DESC,
			g.Numero DESC,
			g.Id
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
