/*
Deploy produzione 2026-10-09 - Esportazione in Excel e CSV degli elenchi del modulo Fatturazione

Da eseguire DOPO deploy_produzione_2026-10-09_fatturazione_prima_nota.sql (uspBancheCasse_get_Esportazione usa le
colonne del saldo iniziale; la SP di esportazione della prima nota è in quello script). Rieseguibile.
Eseguire con sqlcmd -f 65001 -I.

SP di esportazione, una per elenco: stesse righe e stesso ordine della SP dell'elenco, colonne con il nome
dell'intestazione, al massimo @MaxRighe + 1 righe.
1. uspFatture_get_Esportazione: fatture clienti e fornitori.
2. uspFattureRate_get_Scadenzario_Esportazione: scadenziario clienti e fornitori.
3. uspFattureConti_get_Esportazione: conti.
4. uspBancheCasse_get_Esportazione: banche e casse.
5. uspAliquoteIva_get_Esportazione: aliquote IVA.

Nessuna modifica alle tabelle né alle SP degli elenchi. Va deployato insieme all'app.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

PRINT 'uspFatture_get_Esportazione';
GO
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

PRINT 'uspFattureRate_get_Scadenzario_Esportazione';
GO
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

PRINT 'uspFattureConti_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Conti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in
-- CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService,
-- CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si
-- modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspFattureConti_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspFattureConti_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

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
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Nome] = c.Nome,
			[Codice] = c.Codice
		FROM
			dbo.tblFattureConti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			e.Id = @IdSessione
			AND c.Lock = 0
			AND
				(
				@Search IS NULL
				OR c.Nome LIKE '%' + @Search + '%'
				OR c.Codice LIKE '%' + @Search + '%'
				)
		ORDER BY c.Nome
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

PRINT 'uspBancheCasse_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Banche e casse: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in
-- CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService,
-- CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si
-- modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspBancheCasse_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

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
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Tipo] = CASE b.Tipo WHEN 'B' THEN 'Banca' WHEN 'C' THEN 'Cassa' END,
			[Nome] = b.Nome,
			[IBAN] = b.Iban,
			[BIC] = b.Bic,
			[Codice SIA] = b.CodiceSia,
			[Saldo iniziale] = b.SaldoIniziale,
			[Data saldo iniziale] = b.DataSaldoIniziale
		FROM
			dbo.tblBancheCasse b
			INNER JOIN dbo.tblSessioni e ON b.IdSede = e.IdAzienda
		WHERE
			e.Id = @IdSessione
			AND b.Lock = 0
			AND (@Search IS NULL OR b.Nome LIKE '%' + @Search + '%' OR b.Iban LIKE '%' + REPLACE(@Search, ' ', '') + '%')
		ORDER BY b.Nome
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

PRINT 'uspAliquoteIva_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Aliquote IVA: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in
-- CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService,
-- CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si
-- modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspAliquoteIva_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

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
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Aliquote di sistema (IdSede NULL) più quelle dell'azienda interna corrente della sessione, dalla più alta
		-- alla più bassa; senza azienda nel contesto nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Nome] = a.Nome,
			[Codice] = a.Codice,
			[Percentuale] = a.Valore,
			[Tipo] = t.Nome,
			[Natura] = a.IdNatura,
			[Descrizione della natura] = n.Nome,
			[Riferimento normativo] = a.RiferimentoNormativo,
			[Di sistema] = CAST(IIF(a.IdSede IS NULL, 1, 0) AS BIT)
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
