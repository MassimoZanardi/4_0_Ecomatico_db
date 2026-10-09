SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Autorizzazioni dei rifiuti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspRifiutiAutorizzazioni_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiAutorizzazioni_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Numero VARCHAR(50) = NULL,
	@Sede VARCHAR(50) = NULL,
	@IdRuolo CHAR(1) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Numero = dbo.ufnStringhe_get_SenzaSpazi(@Numero, 0, 1);
		SET @Sede = dbo.ufnStringhe_get_SenzaSpazi(@Sede, 0, 1);
		SET @IdRuolo = NULLIF(LTRIM(RTRIM(@IdRuolo)), '');
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
			@IdFunzione = 'RAT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END;

		WITH tbl AS (
			-- Autorizzazioni interne: legate alla sessione tramite IdAziendaInterna
			SELECT
				a.Id,
				Stato = CASE
					WHEN a.DataFine < GETDATE() THEN 'Autorizzazione scaduta'
					WHEN a.Disabilitata = 1 THEN 'Autorizzazione disabilitata'
					WHEN s.Disabilitata = 1 THEN 'Sede disabilitata'
					WHEN DATEDIFF(DAY, GETDATE(), a.DataFine) < 30 THEN 'Autorizzazione in scadenza'
					ELSE 'OK'
				END,
				Sede = s.NomeCompleto + ' - ' + s.IndirizzoCompleto
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
				INNER JOIN dbo.tblRifiutiRuoli r ON a.IdRuolo = r.Id
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				e.Id = @IdSessione
				AND a.Nessuna = 0
				AND a.Lock = 0
				AND (@Numero IS NULL OR a.Numero LIKE '%' + @Numero + '%')
				AND (@Sede IS NULL OR s.NomeCompleto + ' - ' + s.IndirizzoCompleto LIKE '%' + @Sede + '%')
				AND (@IdRuolo IS NULL OR a.IdRuolo = @IdRuolo)
			UNION ALL

			-- Autorizzazioni esterne: legate alla sessione tramite aziende esterne condivise
			SELECT
				a.Id,
				Stato = CASE
					WHEN a.DataFine < GETDATE() THEN 'Autorizzazione scaduta'
					WHEN DATEDIFF(DAY, GETDATE(), a.DataFine) < 30 THEN 'Autorizzazione in scadenza'
					ELSE 'OK'
				END,
				Sede = s.NomeCompleto + ' - ' + s.IndirizzoCompleto
			FROM
				dbo.tblSedi s
				INNER JOIN dbo.tblRifiutiAutorizzazioni a ON s.Id = a.IdSede
				INNER JOIN dbo.tblRifiutiRuoli r ON a.IdRuolo = r.Id
				CROSS APPLY (
					SELECT TOP 1 x.Id
					FROM
						dbo.tblSessioni e
						CROSS APPLY dbo.ufnSedi_get_AziendeEsterneCondiviseByUtente_List(e.IdUtente) x
					WHERE
						e.Id = @IdSessione
						AND x.Id = s.Id
						AND x.IdAziendaInterna <> e.IdAzienda
				) c
			WHERE
				a.Disabilitata = 0
				AND a.Nessuna = 0
				AND s.Disabilitata = 0
				AND a.Lock = 0
				AND (@Numero IS NULL OR a.Numero LIKE '%' + @Numero + '%')
				AND (@Sede IS NULL OR s.NomeCompleto + ' - ' + s.IndirizzoCompleto LIKE '%' + @Sede + '%')
				AND (@IdRuolo IS NULL OR a.IdRuolo = @IdRuolo)
		)
		SELECT TOP (@MaxRighe + 1)
			[Sede] = tbl.Sede,
			[Codice fiscale] = s.CodiceFiscale,
			[Ruolo] = r.Nome,
			[Tipo] = t.Nome,
			[Tipo numero] = nt.Nome,
			[Numero] = a.Numero,
			[Identificativo] = a.Identificativo,
			[Dal] = a.DataInizio,
			[Al] = a.DataFine,
			[Stato] = tbl.Stato,
			[Note] = a.Note
		FROM
			tbl
			INNER JOIN dbo.tblRifiutiAutorizzazioni a ON tbl.Id = a.Id
			INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
			INNER JOIN dbo.tblRifiutiRuoli r ON a.IdRuolo = r.Id
			LEFT JOIN dbo.tblRifiutiAutorizzazioniTipi t ON a.IdTipo = t.Id
			LEFT JOIN dbo.tblRifiutiAutorizzazioniNumeriTipi nt ON a.IdNumeroTipo = nt.Id
		ORDER BY tbl.Sede, a.DataFine DESC
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