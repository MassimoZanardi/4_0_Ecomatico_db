SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Soggetti (aziende esterne): righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel,
-- Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService,
-- CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si
-- modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspSedi_get_AziendeEsterne_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al
-- massimo @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspSedi_get_AziendeEsterne_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Indirizzo VARCHAR(50) = NULL,
	@CodiceFiscale VARCHAR(50) = NULL,
	@Note VARCHAR(50) = NULL,
	@Amministratore VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Indirizzo = dbo.ufnStringhe_get_SenzaSpazi(@Indirizzo, 0, 1);
		SET @CodiceFiscale = dbo.ufnStringhe_get_SenzaSpazi(@CodiceFiscale, 0, 1);
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);
		SET @Amministratore = dbo.ufnStringhe_get_SenzaSpazi(@Amministratore, 0, 1);
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
			@IdFunzione = 'ANS',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		-- Ramo 1: soggetti dell'azienda della sessione; ramo 2: soggetti condivisi da altre aziende
		WITH tbl AS (
			SELECT
				s.Id,
				Area = c.Area
			FROM
				dbo.tblSedi s
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
				OUTER APPLY (
					SELECT TOP 1 a.Id, Area = a.Nome
					FROM
						dbo.tblAreeOsepe ae
						INNER JOIN dbo.tblAree a ON ae.Id = a.Id
					WHERE
						a.Lock = 0
						AND ae.IdOsepe = s.Id
				) c
			WHERE
				e.Id = @IdSessione
				AND s.InternaEsterna = 'E'
				AND s.IdParent IS NULL
				AND s.Lock = 0
			UNION ALL

			SELECT
				s.Id,
				Area = c.Area
			FROM
				dbo.tblSedi s
				CROSS APPLY (
					SELECT TOP 1 x.Id, x.IdArea, x.Area
					FROM
						dbo.tblSessioni e
						CROSS APPLY dbo.ufnSedi_get_AziendeEsterneCondiviseByUtente_List(e.IdUtente) x
					WHERE
						e.Id = @IdSessione
						AND x.Id = s.Id
						AND x.IdAziendaInterna <> e.IdAzienda
				) c
		)
		SELECT TOP (@MaxRighe + 1)
			[Nome] = s.NomeCompleto,
			[Tipo] = t.NomeParent,
			[Codice fiscale] = s.CodiceFiscale,
			[Partita IVA] = s.PartitaIva,
			[Codice] = s.Codice,
			[Indirizzo] = NULLIF(LTRIM(RTRIM(ISNULL(ind.Indirizzo, '') + ISNULL(' ' + NULLIF(ind.NumeroCivico, ''), ''))), ''),
			[Località] = NULLIF(ind.Localita, ''),
			[CAP] = NULLIF(ind.CAP, ''),
			[Comune] = co.Nome,
			[Provincia] = pv.Sigla,
			[Nazione] = nz.Nome,
			[Telefono] = t0.Valore,
			[Email] = m0.Valore,
			[Note] = s.Note,
			[Disabilitata] = IIF(s.Disabilitata = 1, 'Sì', 'No'),
			[Condivisa nell'area] = tbl.Area
		FROM
			tbl
			INNER JOIN dbo.tblSedi s ON tbl.Id = s.Id
			INNER JOIN dbo.tblSediTipi t ON s.IdTipo = t.Id
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
			(@Nome IS NULL OR s.NomeCompleto LIKE '%' + @Nome + '%')
			AND (@Indirizzo IS NULL OR s.IndirizzoCompleto LIKE '%' + @Indirizzo + '%')
			AND (@CodiceFiscale IS NULL OR s.CodiceFiscale LIKE '%' + @CodiceFiscale + '%')
			AND (@Note IS NULL OR s.Note LIKE '%' + @Note + '%')
			-- Amministratore (modulo Anagrafica estesa): solo i soggetti amministrati da un
			-- amministratore attivo il cui nome contiene il testo cercato
			AND
				(
				@Amministratore IS NULL
				OR EXISTS (
					SELECT 1
					FROM
						dbo.tblAmministratoriSedi x
						INNER JOIN dbo.tblAmministratori a ON x.Id = a.Id
						INNER JOIN dbo.tblSedi sa ON a.IdSede = sa.Id
					WHERE
						x.IdSede = tbl.Id
						AND a.Lock = 0
						AND sa.NomeCompleto LIKE '%' + @Amministratore + '%'
				)
				)
		ORDER BY s.NomeCompleto
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
