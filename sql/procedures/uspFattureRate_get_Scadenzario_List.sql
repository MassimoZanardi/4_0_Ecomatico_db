SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scadenziario: le rate delle fatture attive dei clienti (@Tipo = C) o dei fornitori (@Tipo = F) dell'azienda
-- del contesto, dalla scadenza più vecchia. Le pre-fatture (TD00) non entrano. @Stato: A aperte (da pagare
-- e scadute, predefinito), S scadute, D da pagare non scadute, P saldate, T tutte.
-- Residuo = importo - abbuono - pagato. La rata di una nota di credito (NotaCredito = 1) è un importo da
-- restituire.
-- SolaLettura = fattura in sola lettura: la rata non si modifica, i pagamenti si registrano comunque.
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_get_Scadenzario_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Numero VARCHAR(30) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@Stato CHAR(1) = NULL
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
		SET @Stato = ISNULL(UPPER(NULLIF(LTRIM(RTRIM(@Stato)), '')), 'A');

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
		IF @Stato NOT IN ('A', 'S', 'D', 'P', 'T')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Stato deve essere A, S, D, P o T';
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
		-- Pagato = quote dei pagamenti attivi attribuite alla rata.
		-- Il residuo serve al filtro per stato, quindi va calcolato per tutte le rate dell'azienda: lo si fa
		-- con le sole colonne che servono a filtro e ordinamento (quelle degli indici delle fatture e delle
		-- rate); il resto della riga (tipo, modalità, banca) si legge solo per le rate della pagina
		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);

		WITH rate AS (
			SELECT
				r.Id,
				r.IdFattura,
				r.DataScadenza,
				Importo = ISNULL(r.Importo, 0),
				Abbuono = ISNULL(r.Abbuono, 0),
				x.Pagato,
				Residuo = IIF(ISNULL(r.Importo, 0) - ISNULL(r.Abbuono, 0) - x.Pagato > 0, ISNULL(r.Importo, 0) - ISNULL(r.Abbuono, 0) - x.Pagato, 0),
				f.Numero,
				s.NomeCompleto
			FROM
				dbo.tblFattureRate r
				INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
				CROSS APPLY
					(
						SELECT Pagato = ISNULL(SUM(rp.Importo), 0)
						FROM
							dbo.tblFattureRatePagamenti rp
							INNER JOIN dbo.tblPagamenti g ON rp.IdPagamento = g.Id
						WHERE
							rp.IdRata = r.Id
							AND g.Lock = 0
					) x
			WHERE
				e.Id = @IdSessione
				AND f.Tipo = @Tipo
				AND f.Lock = 0
				AND ISNULL(f.IdTipo, '') <> 'TD00'
				AND (@Nome IS NULL OR s.NomeCompleto LIKE '%' + @Nome + '%')
				AND
					(
					@Numero IS NULL
					OR CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, '') LIKE @Numero + '%'
					OR f.NumeroFornitore LIKE '%' + @Numero + '%'
					)
				AND (@DataDa IS NULL OR r.DataScadenza >= @DataDa)
				AND (@DataA IS NULL OR r.DataScadenza <= @DataA)
		),
		pagina AS (
			SELECT
				t.Id,
				t.IdFattura,
				t.DataScadenza,
				t.Importo,
				t.Abbuono,
				t.Pagato,
				t.Residuo,
				t.Numero,
				t.NomeCompleto,
				RowsCount = COUNT(*) OVER ()
			FROM rate t
			WHERE
				@Stato = 'T'
				OR (@Stato = 'A' AND t.Residuo > 0)
				OR (@Stato = 'S' AND t.Residuo > 0 AND t.DataScadenza < @oggi)
				OR (@Stato = 'D' AND t.Residuo > 0 AND t.DataScadenza >= @oggi)
				OR (@Stato = 'P' AND t.Residuo = 0)
			ORDER BY
				t.DataScadenza,
				t.NomeCompleto,
				t.Numero,
				t.Id
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
		)
		SELECT
			t.Id,
			t.IdFattura,
			StatoValore = CASE
				WHEN t.Residuo = 0 THEN 0
				WHEN t.DataScadenza < @oggi THEN 2
				ELSE 1
			END,
			StatoDescrizione = CASE
				WHEN t.Residuo = 0 THEN 'Saldata'
				WHEN t.DataScadenza < @oggi THEN 'Scaduta'
				ELSE 'Da pagare'
			END,
			t.DataScadenza,
			f.Numero,
			f.Sezionale,
			f.NumeroFornitore,
			f.DataEmissione,
			f.IdTipo,
			TipoNome = p.Nome,
			f.IdModalita,
			f.IdBancaCassa,
			f.IdClienteFornitore,
			t.NomeCompleto,
			NotaCredito = CAST(IIF(f.IdTipo = 'TD04', 1, 0) AS BIT),
			SolaLettura = ISNULL(f.SolaLettura, 0),
			Importo = CAST(t.Importo AS DECIMAL(18, 2)),
			Abbuono = CAST(t.Abbuono AS DECIMAL(18, 2)),
			Pagato = CAST(t.Pagato AS DECIMAL(18, 2)),
			Residuo = CAST(t.Residuo AS DECIMAL(18, 2)),
			t.RowsCount
		FROM
			pagina t
			INNER JOIN dbo.tblFatture f ON t.IdFattura = f.Id
			LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
		ORDER BY
			t.DataScadenza,
			t.NomeCompleto,
			t.Numero,
			t.Id
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
