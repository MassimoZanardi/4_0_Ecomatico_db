SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scadenziario clienti (@Tipo = C) e fornitori (@Tipo = F): righe per l'esportazione dell'elenco in Excel e in
-- CSV (Azioni > Esporta in Excel, Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel
-- file: l'applicazione (ExcelService, CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per
-- cambiare che cosa si esporta si modifica solo questa SP.
-- Stesse rate e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspFattureRate_get_Scadenzario_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al
-- massimo @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
-- Come nell'elenco, gli importi della rata di una nota di credito hanno il segno meno (importo da restituire).
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_get_Scadenzario_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Numero VARCHAR(30) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@Stato CHAR(1) = NULL,
	@MaxRighe INT = NULL
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
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

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

		-- Rate della ricerca, nell'ordine dell'elenco (stessi criteri e stesso ORDER BY di
		-- uspFattureRate_get_Scadenzario_List), con pagato, residuo e stato già calcolati
		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);
		DECLARE @rate TABLE (
			Pos INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			Pagato DECIMAL(18, 2) NOT NULL,
			Residuo DECIMAL(18, 2) NOT NULL
		);

		WITH rate AS (
			SELECT
				r.Id,
				r.DataScadenza,
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
		)
		INSERT @rate (Id, Pagato, Residuo)
		SELECT TOP (@MaxRighe + 1)
			t.Id,
			t.Pagato,
			t.Residuo
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
		OPTION (RECOMPILE);

		IF @Tipo = 'C'
			SELECT
				[Scadenza] = r.DataScadenza,
				[Stato] = CASE WHEN x.Residuo = 0 THEN 'Saldata' WHEN r.DataScadenza < @oggi THEN 'Scaduta' ELSE 'Da pagare' END,
				[Importo] = CAST(g.Segno * ISNULL(r.Importo, 0) AS DECIMAL(18, 2)),
				[Abbuono] = CAST(g.Segno * NULLIF(r.Abbuono, 0) AS DECIMAL(18, 2)),
				[Incassato] = CAST(g.Segno * NULLIF(x.Pagato, 0) AS DECIMAL(18, 2)),
				[Residuo] = CAST(g.Segno * x.Residuo AS DECIMAL(18, 2)),
				[Fattura] = CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, ''),
				[Data fattura] = f.DataEmissione,
				[Tipo documento] = p.Nome,
				[Cliente] = s.NomeCompleto,
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Pagamento tramite] = m.Nome,
				[Banca o cassa] = b.Nome
			FROM
				@rate x
				INNER JOIN dbo.tblFattureRate r ON x.Id = r.Id
				INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
				LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
				LEFT JOIN dbo.tblPagamentiModalita m ON f.IdModalita = m.Id
				LEFT JOIN dbo.tblBancheCasse b ON f.IdBancaCassa = b.Id
				CROSS APPLY (SELECT Segno = IIF(f.IdTipo = 'TD04', -1, 1)) g
			ORDER BY x.Pos;
		ELSE
			SELECT
				[Scadenza] = r.DataScadenza,
				[Stato] = CASE WHEN x.Residuo = 0 THEN 'Saldata' WHEN r.DataScadenza < @oggi THEN 'Scaduta' ELSE 'Da pagare' END,
				[Importo] = CAST(g.Segno * ISNULL(r.Importo, 0) AS DECIMAL(18, 2)),
				[Abbuono] = CAST(g.Segno * NULLIF(r.Abbuono, 0) AS DECIMAL(18, 2)),
				[Pagato] = CAST(g.Segno * NULLIF(x.Pagato, 0) AS DECIMAL(18, 2)),
				[Residuo] = CAST(g.Segno * x.Residuo AS DECIMAL(18, 2)),
				[Protocollo] = CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, ''),
				[Numero fornitore] = f.NumeroFornitore,
				[Data fattura] = f.DataEmissione,
				[Tipo documento] = p.Nome,
				[Fornitore] = s.NomeCompleto,
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Pagamento tramite] = m.Nome,
				[IBAN del fornitore] = f.Iban,
				[Banca o cassa] = b.Nome
			FROM
				@rate x
				INNER JOIN dbo.tblFattureRate r ON x.Id = r.Id
				INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
				LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
				LEFT JOIN dbo.tblPagamentiModalita m ON f.IdModalita = m.Id
				LEFT JOIN dbo.tblBancheCasse b ON f.IdBancaCassa = b.Id
				CROSS APPLY (SELECT Segno = IIF(f.IdTipo = 'TD04', -1, 1)) g
			ORDER BY x.Pos;

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
