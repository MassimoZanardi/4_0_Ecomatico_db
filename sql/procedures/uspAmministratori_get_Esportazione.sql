SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Amministratori: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in
-- CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService,
-- CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si
-- modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspAmministratori_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspAmministratori_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Indirizzo VARCHAR(50) = NULL,
	@CodiceFiscale VARCHAR(50) = NULL,
	@Amministrato VARCHAR(50) = NULL,
	@Note VARCHAR(50) = NULL,
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
		SET @Amministrato = dbo.ufnStringhe_get_SenzaSpazi(@Amministrato, 0, 1);
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);
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
			@IdFunzione = 'ANM',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga.
		-- Codice fiscale e partita IVA si cercano con lo stesso filtro; @Amministrato cerca tra i
		-- soggetti amministrati (nome + indirizzo)
		SELECT TOP (@MaxRighe + 1)
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
			[Amministrati] = (SELECT COUNT(*) FROM dbo.tblAmministratoriSedi x WHERE x.Id = c.Id),
			[Note] = c.Note,
			[Soggetto disabilitato] = IIF(s.Disabilitata = 1, 'Sì', 'No')
		FROM
			dbo.tblAmministratori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
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
			AND c.Lock = 0
			AND (@Nome IS NULL OR s.NomeCompleto LIKE '%' + @Nome + '%')
			AND (@Indirizzo IS NULL OR s.IndirizzoCompleto LIKE '%' + @Indirizzo + '%')
			AND
				(
				@CodiceFiscale IS NULL
				OR s.CodiceFiscale LIKE '%' + @CodiceFiscale + '%'
				OR s.PartitaIva LIKE '%' + @CodiceFiscale + '%'
				)
			AND
				(
				@Amministrato IS NULL
				OR EXISTS (
					SELECT 1
					FROM
						dbo.tblAmministratoriSedi x
						INNER JOIN dbo.tblSedi sa ON x.IdSede = sa.Id
					WHERE
						x.Id = c.Id
						AND sa.NomeCompleto + ISNULL(' ' + sa.IndirizzoCompleto, '') LIKE '%' + @Amministrato + '%'
				)
				)
			AND (@Note IS NULL OR c.Note LIKE '%' + @Note + '%')
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
