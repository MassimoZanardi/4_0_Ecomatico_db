SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture clienti (@Tipo = C) e fornitori (@Tipo = F): righe per l'esportazione dell'elenco in Excel e in CSV
-- (Azioni > Esporta in Excel, Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file:
-- l'applicazione (ExcelService, CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per
-- cambiare che cosa si esporta si modifica solo questa SP.
-- Stesse fatture e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspFatture_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
-- Pagato = quote dei pagamenti attivi sulle rate della fattura; Residuo = quanto resta da pagare delle rate
-- (vuoto se la fattura non ha rate). Avviso = lo stato di avviso dell'elenco.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Numero VARCHAR(30) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdTipo CHAR(4) = NULL,
	@IdStato CHAR(1) = NULL,
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
		SET @IdTipo = NULLIF(NULLIF(LTRIM(RTRIM(@IdTipo)), ''), REPLICATE('0', 4));
		SET @IdStato = NULLIF(NULLIF(LTRIM(RTRIM(@IdStato)), ''), '0');
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

		-- Fatture della ricerca, nell'ordine dell'elenco (stesso WHERE e stesso ORDER BY di uspFatture_get_List)
		DECLARE @fatture TABLE (
			Pos INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL
		);

		INSERT @fatture (Id)
		SELECT TOP (@MaxRighe + 1) f.Id
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
		OPTION (RECOMPILE);

		IF @Tipo = 'C'
			SELECT
				[Numero] = CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, ''),
				[Data] = f.DataEmissione,
				[Tipo documento] = p.Nome,
				[Stato] = a.Nome,
				[Cliente] = s.NomeCompleto,
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Imponibile] = t.Imponibile,
				[IVA] = t.Iva,
				[Ritenuta] = t.Ritenuta,
				[Totale] = t.Totale,
				[Netto a pagare] = t.NettoAPagare,
				[Incassato] = z.Pagato,
				[Residuo] = z.Residuo,
				[Pagamento tramite] = m.Nome,
				[Banca o cassa] = b.Nome,
				[Bollo] = NULLIF(f.Bollo, 0),
				[Split payment] = ISNULL(f.SplitPayment, 0),
				[Causale] = f.Causale,
				[Ordine] = f.Ordine,
				[Data ordine] = f.DataOrdine,
				[CIG] = f.CodiceCig,
				[CUP] = f.CodiceCup,
				[Fattura di riferimento] = CAST(rf.Numero AS VARCHAR(12)) + ISNULL('/' + rf.Sezionale, ''),
				[Sola lettura] = ISNULL(f.SolaLettura, 0),
				[File XML generato il] = f.DataXml,
				[Avviso] =
					CASE
						WHEN t.Totale = 0 THEN 'Fattura senza importi'
						WHEN z.Numero > 0 AND z.Importo <> t.NettoAPagare THEN 'Le rate non corrispondono al netto a pagare'
					END
			FROM
				@fatture x
				INNER JOIN dbo.tblFatture f ON x.Id = f.Id
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
				LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
				LEFT JOIN dbo.tblFattureStati a ON f.IdStato = a.Id
				LEFT JOIN dbo.tblPagamentiModalita m ON f.IdModalita = m.Id
				LEFT JOIN dbo.tblBancheCasse b ON f.IdBancaCassa = b.Id
				LEFT JOIN dbo.tblFatture rf ON f.IdFatturaRiferimento = rf.Id
				OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
				OUTER APPLY
					(
						SELECT
							Numero = COUNT(*),
							Importo = ISNULL(SUM(q.Importo), 0),
							Pagato = CAST(NULLIF(SUM(g.Pagato), 0) AS DECIMAL(18, 2)),
							Residuo = CAST(SUM(IIF(ISNULL(q.Importo, 0) - ISNULL(q.Abbuono, 0) - g.Pagato > 0, ISNULL(q.Importo, 0) - ISNULL(q.Abbuono, 0) - g.Pagato, 0)) AS DECIMAL(18, 2))
						FROM
							dbo.tblFattureRate q
							CROSS APPLY
								(
									SELECT Pagato = ISNULL(SUM(rp.Importo), 0)
									FROM
										dbo.tblFattureRatePagamenti rp
										INNER JOIN dbo.tblPagamenti k ON rp.IdPagamento = k.Id
									WHERE
										rp.IdRata = q.Id
										AND k.Lock = 0
								) g
						WHERE q.IdFattura = f.Id
					) z
			ORDER BY x.Pos;
		ELSE
			SELECT
				[Protocollo] = CAST(f.Numero AS VARCHAR(12)) + ISNULL('/' + f.Sezionale, ''),
				[Data registrazione] = f.DataRegistrazione,
				[Numero fornitore] = f.NumeroFornitore,
				[Data fattura] = f.DataEmissione,
				[Tipo documento] = p.Nome,
				[Fornitore] = s.NomeCompleto,
				[Partita IVA] = s.PartitaIva,
				[Codice fiscale] = s.CodiceFiscale,
				[Imponibile] = t.Imponibile,
				[IVA] = t.Iva,
				[Ritenuta] = t.Ritenuta,
				[Totale] = t.Totale,
				[Netto a pagare] = t.NettoAPagare,
				[Pagato] = z.Pagato,
				[Residuo] = z.Residuo,
				[Pagamento tramite] = m.Nome,
				[IBAN del fornitore] = f.Iban,
				[Banca o cassa] = b.Nome,
				[Bollo] = NULLIF(f.Bollo, 0),
				[Split payment] = ISNULL(f.SplitPayment, 0),
				[Causale] = f.Causale,
				[Ordine] = f.Ordine,
				[Data ordine] = f.DataOrdine,
				[CIG] = f.CodiceCig,
				[CUP] = f.CodiceCup,
				[Fattura di riferimento] = ISNULL(NULLIF(rf.NumeroFornitore, ''), CAST(rf.Numero AS VARCHAR(12)) + ISNULL('/' + rf.Sezionale, '')),
				[Sola lettura] = ISNULL(f.SolaLettura, 0),
				[Caricata da file XML il] = f.DataXml,
				[Avviso] =
					CASE
						WHEN t.Totale = 0 THEN 'Fattura senza importi'
						WHEN z.Numero > 0 AND z.Importo <> t.NettoAPagare THEN 'Le rate non corrispondono al netto a pagare'
					END
			FROM
				@fatture x
				INNER JOIN dbo.tblFatture f ON x.Id = f.Id
				LEFT JOIN dbo.tblClientiFornitori c ON f.IdClienteFornitore = c.Id
				LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
				LEFT JOIN dbo.tblFattureTipi p ON f.IdTipo = p.Id
				LEFT JOIN dbo.tblPagamentiModalita m ON f.IdModalita = m.Id
				LEFT JOIN dbo.tblBancheCasse b ON f.IdBancaCassa = b.Id
				LEFT JOIN dbo.tblFatture rf ON f.IdFatturaRiferimento = rf.Id
				OUTER APPLY dbo.ufnFatture_get_Totali(f.Id) t
				OUTER APPLY
					(
						SELECT
							Numero = COUNT(*),
							Importo = ISNULL(SUM(q.Importo), 0),
							Pagato = CAST(NULLIF(SUM(g.Pagato), 0) AS DECIMAL(18, 2)),
							Residuo = CAST(SUM(IIF(ISNULL(q.Importo, 0) - ISNULL(q.Abbuono, 0) - g.Pagato > 0, ISNULL(q.Importo, 0) - ISNULL(q.Abbuono, 0) - g.Pagato, 0)) AS DECIMAL(18, 2))
						FROM
							dbo.tblFattureRate q
							CROSS APPLY
								(
									SELECT Pagato = ISNULL(SUM(rp.Importo), 0)
									FROM
										dbo.tblFattureRatePagamenti rp
										INNER JOIN dbo.tblPagamenti k ON rp.IdPagamento = k.Id
									WHERE
										rp.IdRata = q.Id
										AND k.Lock = 0
								) g
						WHERE q.IdFattura = f.Id
					) z
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
