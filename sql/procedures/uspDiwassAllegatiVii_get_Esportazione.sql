SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Allegati VII: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspDiwassAllegatiVii_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspDiwassAllegatiVii_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Stato VARCHAR(20) = NULL,
	@Ruolo CHAR(1) = NULL,
	@DaFare BIT = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');
		SET @Ruolo = NULLIF(LTRIM(RTRIM(@Ruolo)), '');
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
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (@MaxRighe + 1)
			[Numero DIWASS] = a.Numero,
			[Stato] = dbo.ufnDiwassAllegatiVii_get_StatoDescrizione(a.Stato) + IIF(a.DaInviare = 1, ' - modifiche da inviare a DIWASS', ''),
			[Data della spedizione] = a.DataSpedizione,
			[EER] = e.Nome,
			[Codice internazionale] = a.Codice,
			[Descrizione] = a.Descrizione,
			[Quantità] = a.Quantita,
			[Unità] = IIF(a.UnitaQuantita = 'M', 'm³', 't'),
			[Ruolo dell'azienda] = dbo.ufnDiwassAllegatiVii_get_RuoliDescrizione(a.Ruoli),
			[Ricevuto da DIWASS] = IIF(a.Ricevuto = 1, 'Sì', 'No'),
			[Organizzatore] = ISNULL(so.NomeCompleto, xo.Nome),
			[Destinatario] = ISNULL(d.NomeCompleto, x.Nome),
			[Paese di spedizione] = ns.Nome,
			[Paese di destinazione] = n.Nome,
			[Inviato il] = a.DataInvio,
			[Presa in carico] = v.PresaInCaricoData,
			[Ricezione del destinatario] = IIF(v.RicezioneDestinatarioPrevista = 0, NULL, v.RicezioneDestinatarioData),
			[Ricezione all'impianto] = v.RicezioneImpiantoData,
			[Recupero completato] = v.CompletamentoData,
			[Da fare] = v.DaFare,
			[Scadenza] = v.Scadenza
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni s ON a.IdAziendaInterna = s.IdAzienda
			LEFT JOIN dbo.tblRifiutiEer e ON a.IdEer = e.Id
			LEFT JOIN dbo.tblDiwassAllegatiViiSoggetti x ON a.Id = x.Id AND x.Ruolo = 'D' AND x.Pos = 1
			LEFT JOIN dbo.tblSedi d ON x.IdSede = d.Id
			LEFT JOIN dbo.tblDiwassAllegatiViiSoggetti xo ON a.Id = xo.Id AND xo.Ruolo = 'O' AND xo.Pos = 1
			LEFT JOIN dbo.tblSedi so ON xo.IdSede = so.Id
			LEFT JOIN dbo.tblNazioni n ON a.IdNazioneDestinazione = n.Id
			LEFT JOIN dbo.tblNazioni ns ON a.IdNazioneSpedizione = ns.Id
			OUTER APPLY dbo.ufnDiwassAllegatiVii_get_Avanzamento(a.Id) v
		WHERE
			s.Id = @IdSessione
			AND a.Lock = 0
			AND
				(
				@Stato IS NULL
				OR
					(
					@Stato = 'B'
					AND a.Stato IS NULL
					)
				OR a.Stato = @Stato
				)
			AND
				(
				@Search IS NULL
				OR a.Numero LIKE '%' + @Search + '%'
				OR a.Descrizione LIKE '%' + @Search + '%'
				OR e.Nome LIKE '%' + @Search + '%'
				OR ISNULL(d.NomeCompleto, x.Nome) LIKE '%' + @Search + '%'
				OR ISNULL(so.NomeCompleto, xo.Nome) LIKE '%' + @Search + '%'
				)
			AND
				(
				@Ruolo IS NULL
				OR ISNULL(a.Ruoli, 'O') LIKE '%' + @Ruolo + '%'
				)
			AND
				(
				ISNULL(@DaFare, 0) = 0
				OR v.DaFare IS NOT NULL
				)
		ORDER BY a.DataSpedizione DESC, a.Id DESC
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
