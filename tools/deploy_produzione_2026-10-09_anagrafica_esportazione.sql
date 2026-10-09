/*
Deploy produzione 2026-10-09 - Esportazione in Excel e CSV degli elenchi del modulo Anagrafica

Indipendente dagli altri script del 2026-10-09 (usa solo tabelle già in produzione con l'Anagrafica estesa e la
Fatturazione del 2026-10-07/08: va eseguito dopo quelli). Rieseguibile. Eseguire con sqlcmd -f 65001 -I.

SP di esportazione, una per elenco: stesse righe e stesso ordine della SP dell'elenco, colonne con il nome
dell'intestazione, al massimo @MaxRighe + 1 righe.
1. uspSedi_get_AziendeEsterne_Esportazione: soggetti.
2. uspPersone_get_Esportazione: persone.
3. uspOggetti_get_Esportazione: oggetti.
4. uspAmministratori_get_Esportazione: amministratori.
5. uspClientiFornitori_get_Esportazione: clienti e fornitori.

Nessuna modifica alle tabelle né alle SP degli elenchi. Va deployato insieme all'app.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/


PRINT 'uspSedi_get_AziendeEsterne_Esportazione';
GO
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

PRINT 'uspPersone_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Persone: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspPersone_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspPersone_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Ruolo VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = NULLIF(LTRIM(RTRIM(@Nome)), '');
		SET @Ruolo = NULLIF(LTRIM(RTRIM(@Ruolo)), '');
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione (APC = Gestione Oggetti/Persone)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'APC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		-- Ramo 1: persone dell'azienda della sessione; ramo 2: persone condivise da altre aziende
		WITH tbl AS (
			SELECT
				s.Id,
				Area = c.Area
			FROM
				dbo.tblPersone s
				INNER JOIN dbo.tblSessioni e ON s.IdSede = e.IdAzienda
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
				AND s.Lock = 0
			UNION ALL

			SELECT
				s.Id,
				Area = c.Area
			FROM
				dbo.tblPersone s
				CROSS APPLY (
					SELECT TOP 1 x.Id, x.IdArea, x.Area
					FROM
						dbo.tblSessioni e
						CROSS APPLY dbo.ufnPersone_get_CondiviseByUtente_List(e.IdUtente) x
					WHERE
						e.Id = @IdSessione
						AND x.Id = s.Id
						AND x.IdSede <> e.IdAzienda
				) c
		)
		-- Ruolo: il più recente, come nell'elenco
		SELECT TOP (@MaxRighe + 1)
			[Nome] = s.Nome,
			[Cognome] = s.Cognome,
			[Ruolo] = r.Ruolo,
			[Ruolo dal] = r.DataInizio,
			[Ruolo al] = r.DataFine,
			[Impiegabile nei servizi] = IIF(s.ImpiegabileServizi = 1, 'Sì', 'No'),
			[Unità di misura nei servizi] = um.Nome,
			[Disabilitata] = IIF(s.Disabilitata = 1, 'Sì', 'No'),
			[Condivisa nell'area] = tbl.Area
		FROM
			tbl
			INNER JOIN dbo.tblPersone s ON tbl.Id = s.Id
			LEFT JOIN dbo.tblUnitaMisura um ON s.IdUnitaMisura = um.Id
			OUTER APPLY (
				SELECT TOP 1 Ruolo = r.Nome, pr.DataInizio, pr.DataFine
				FROM
					dbo.tblPersoneRuoli pr
					INNER JOIN dbo.tblRuoli r ON pr.IdRuolo = r.Id
				WHERE pr.Id = s.Id
				ORDER BY pr.DataInizio DESC
			) r
		WHERE
			(@Nome IS NULL OR s.NomeCompleto LIKE '%' + @Nome + '%')
			AND
				(
				@Ruolo IS NULL
				OR s.Id IN (SELECT pr.Id FROM dbo.tblPersoneRuoli pr INNER JOIN dbo.tblRuoli r ON pr.IdRuolo = r.Id WHERE r.Nome LIKE '%' + @Ruolo + '%')
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

PRINT 'uspOggetti_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Oggetti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspOggetti_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspOggetti_get_Esportazione
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
		SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione (APC = Gestione Oggetti/Persone)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'APC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		-- Ramo 1: oggetti dell'azienda della sessione; ramo 2: oggetti condivisi da altre aziende
		WITH tbl AS (
			SELECT
				s.Id,
				Area = c.Area
			FROM
				dbo.tblOggetti s
				INNER JOIN dbo.tblSessioni e ON s.IdSede = e.IdAzienda
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
				AND s.Lock = 0
			UNION ALL

			SELECT
				s.Id,
				Area = c.Area
			FROM
				dbo.tblOggetti s
				CROSS APPLY (
					SELECT TOP 1 x.Id, x.IdArea, x.Area
					FROM
						dbo.tblSessioni e
						CROSS APPLY dbo.ufnOggetti_get_CondivisiByUtente_List(e.IdUtente) x
					WHERE
						e.Id = @IdSessione
						AND x.Id = s.Id
						AND x.IdSede <> e.IdAzienda
				) c
		)
		SELECT TOP (@MaxRighe + 1)
			[Nome] = s.Nome,
			[Codice] = s.Codice,
			[Tipo] = t.Nome,
			[Descrizione] = s.Descrizione,
			[Impiegabile nei servizi] = IIF(s.ImpiegabileServizi = 1, 'Sì', 'No'),
			[Unità di misura nei servizi] = um.Nome,
			[Disabilitato] = IIF(s.Disabilitata = 1, 'Sì', 'No'),
			[Condiviso nell'area] = tbl.Area
		FROM
			tbl
			INNER JOIN dbo.tblOggetti s ON tbl.Id = s.Id
			LEFT JOIN dbo.tblOggettiTipi t ON s.IdTipo = t.Id
			LEFT JOIN dbo.tblUnitaMisura um ON s.IdUnitaMisura = um.Id
		WHERE (@Search IS NULL OR s.Nome LIKE '%' + @Search + '%')
		ORDER BY s.Nome
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

PRINT 'uspAmministratori_get_Esportazione';
GO
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

PRINT 'uspClientiFornitori_get_Esportazione';
GO
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
