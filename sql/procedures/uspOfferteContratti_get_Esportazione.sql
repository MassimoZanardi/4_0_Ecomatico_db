SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Contratti clienti e Offerte clienti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta
-- in Excel, Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione
-- (ExcelService, CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa
-- si esporta si modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: scope e criteri di ricerca sono in ufnOfferteContratti_get_List,
-- comune a uspOfferteContratti_get_List; il filtro @SoloInVigore è ricopiato da quella e va tenuto allineato.
-- Tutte le righe, senza paginazione: al massimo @MaxRighe + 1 (la riga in più dice all'applicazione che la
-- ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Search VARCHAR(50) = NULL,
	@SoloInVigore BIT = 0,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = NULLIF(UPPER(LTRIM(RTRIM(@Tipo))), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @SoloInVigore = ISNULL(@SoloInVigore, 0);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'O')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (contratto) o O (offerta)';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);

		SELECT TOP (@MaxRighe + 1)
			[Cliente] = t.Cliente,
			[Indirizzo] = t.ClienteIndirizzo,
			[Partita IVA] = t.ClientePartitaIva,
			[Codice fiscale] = t.ClienteCodiceFiscale,
			[Dal] = t.DataInizio,
			[Al] = t.DataFine,
			[Stato] = t.StatoDescrizione,
			[Descrizione] = t.Descrizione,
			[Protocollo] = t.Protocollo,
			[Ordine] = t.Ordine,
			[Data ordine] = t.DataOrdine,
			[CIG] = t.CodiceCig,
			[CUP] = t.CodiceCup,
			[Importi] = t.Importi
		FROM dbo.ufnOfferteContratti_get_List(@IdSessione, @Tipo, @Search) t
		WHERE
			@SoloInVigore = 0
			OR (t.DataInizio <= @oggi AND t.DataFine >= @oggi)
		ORDER BY t.Cliente, t.DataInizio DESC, t.Id
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
