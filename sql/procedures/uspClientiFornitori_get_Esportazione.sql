SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Clienti e fornitori: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel,
-- Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService,
-- CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si
-- modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspClientiFornitori_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
-- Le colonne sono le stesse per clienti e fornitori; cambia solo l'intestazione dell'IBAN.
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Indirizzo VARCHAR(50) = NULL,
	@CodiceFiscale VARCHAR(50) = NULL,
	@Note VARCHAR(50) = NULL,
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
		SET @Indirizzo = dbo.ufnStringhe_get_SenzaSpazi(@Indirizzo, 0, 1);
		SET @CodiceFiscale = dbo.ufnStringhe_get_SenzaSpazi(@CodiceFiscale, 0, 1);
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);
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

		-- Controlla il permesso sulla funzione: ANC per i clienti, ANF per i fornitori
		DECLARE @idFunzione CHAR(3) = IIF(@Tipo = 'C', 'ANC', 'ANF');
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga.
		-- Codice fiscale e partita IVA si cercano con lo stesso filtro
		SELECT
			c.Id,
			Ordine = ROW_NUMBER() OVER (ORDER BY s.NomeCompleto),
			[Nome] = s.NomeCompleto,
			[Codice fiscale] = s.CodiceFiscale,
			[Partita IVA] = s.PartitaIva,
			[Indirizzo] = NULLIF(LTRIM(RTRIM(ISNULL(ind.Indirizzo, '') + ISNULL(' ' + NULLIF(ind.NumeroCivico, ''), ''))), ''),
			[Località] = NULLIF(ind.Localita, ''),
			[CAP] = NULLIF(ind.CAP, ''),
			[Comune] = co.Nome,
			[Provincia] = pv.Sigla,
			[Nazione] = nz.Nome,
			[Telefono] = t0.Valore,
			[Email] = m0.Valore,
			[Pagamento tramite] = m.Nome,
			[Giorni] = r.Nome,
			[Da] = ri.Nome,
			[Giorno del mese] = NULLIF(c.RataGiorniInizio, 0),
			[Banca o cassa] = b.Nome,
			[IBAN] = c.Iban,
			[Aliquota IVA] = a.Nome,
			[Valuta] = v.Nome,
			[Split payment] = IIF(c.SplitPayment = 1, 'Sì', 'No'),
			[Ritenuta d'acconto %] = NULLIF(c.RitenutaAcconto, 0),
			[Importo minimo fatturabile] = c.ImportoMinimoFatturabile,
			[Codice destinatario] = c.CodiceDestinatario,
			[PEC destinatario] = c.PecDestinatario,
			[Note] = c.Note,
			[Soggetto disabilitato] = IIF(s.Disabilitata = 1, 'Sì', 'No')
		INTO #righe
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			LEFT JOIN dbo.tblPagamentiModalita m ON c.IdModalita = m.Id
			LEFT JOIN dbo.tblPagamentiRate r ON c.IdRata = r.Id
			LEFT JOIN dbo.tblPagamentiRateInizi ri ON c.IdRataInizio = ri.Id
			LEFT JOIN dbo.tblBancheCasse b ON c.IdBancaCassa = b.Id
			LEFT JOIN dbo.tblAliquoteIva a ON c.IdAliquotaIva = a.Id
			LEFT JOIN dbo.tblPagamentiValute v ON c.IdValuta = v.Id
			OUTER APPLY (
				SELECT TOP 1 i.IdComune, i.IdNazione, i.Indirizzo, i.NumeroCivico, i.Localita, i.CAP
				FROM
					dbo.tblSediIndirizzi si
					INNER JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
				WHERE si.Id = s.Id
			) ind
			LEFT JOIN dbo.tblComuni co ON ind.IdComune = co.Id
			LEFT JOIN dbo.tblProvince pv ON co.IdProvincia = pv.Id
			LEFT JOIN dbo.tblNazioni nz ON ind.IdNazione = nz.Id
			LEFT JOIN dbo.tblSediRecapiti t0 ON s.Id = t0.Id AND t0.IdRecapito = 'T0'
			LEFT JOIN dbo.tblSediRecapiti m0 ON s.Id = m0.Id AND m0.IdRecapito = 'M0'
		WHERE
			e.Id = @IdSessione
			AND c.Tipo = @Tipo
			AND c.Lock = 0
			AND (@Nome IS NULL OR s.NomeCompleto LIKE '%' + @Nome + '%')
			AND (@Indirizzo IS NULL OR s.IndirizzoCompleto LIKE '%' + @Indirizzo + '%')
			AND
				(
				@CodiceFiscale IS NULL
				OR s.CodiceFiscale LIKE '%' + @CodiceFiscale + '%'
				OR s.PartitaIva LIKE '%' + @CodiceFiscale + '%'
				)
			AND (@Note IS NULL OR c.Note LIKE '%' + @Note + '%')
		OPTION (RECOMPILE);

		IF @Tipo = 'C'
			SELECT TOP (@MaxRighe + 1)
				[Nome], [Codice fiscale], [Partita IVA], [Indirizzo], [Località], [CAP], [Comune], [Provincia], [Nazione],
				[Telefono], [Email], [Pagamento tramite], [Giorni], [Da], [Giorno del mese], [Banca o cassa],
				[IBAN del cliente] = [IBAN], [Aliquota IVA], [Valuta], [Split payment], [Ritenuta d'acconto %],
				[Importo minimo fatturabile], [Codice destinatario], [PEC destinatario], [Note], [Soggetto disabilitato]
			FROM #righe
			ORDER BY Ordine;
		ELSE
			SELECT TOP (@MaxRighe + 1)
				[Nome], [Codice fiscale], [Partita IVA], [Indirizzo], [Località], [CAP], [Comune], [Provincia], [Nazione],
				[Telefono], [Email], [Pagamento tramite], [Giorni], [Da], [Giorno del mese], [Banca o cassa],
				[IBAN del fornitore] = [IBAN], [Aliquota IVA], [Valuta], [Split payment], [Ritenuta d'acconto %],
				[Importo minimo fatturabile], [Codice destinatario], [PEC destinatario], [Note], [Soggetto disabilitato]
			FROM #righe
			ORDER BY Ordine;

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
