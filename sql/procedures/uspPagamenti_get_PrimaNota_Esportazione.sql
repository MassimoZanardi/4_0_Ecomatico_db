SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Prima nota: righe per l'esportazione in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV). Stessi
-- movimenti e stessa ricerca dell'elenco (ufnPagamenti_get_PrimaNota), tutti e senza paginazione, con più
-- colonne di quelle a video.
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine, uguali nei due formati. Per cambiare che cosa si
-- esporta si modifica solo questa SP. Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione
-- che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspPagamenti_get_PrimaNota_Esportazione
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdBancaCassa CHAR(16) = NULL,
	@Verso CHAR(1) = NULL,
	@Testo VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdBancaCassa = NULLIF(NULLIF(LTRIM(RTRIM(@IdBancaCassa)), ''), REPLICATE('0', 16));
		SET @Verso = UPPER(NULLIF(LTRIM(RTRIM(@Verso)), ''));
		SET @Testo = dbo.ufnStringhe_get_SenzaSpazi(@Testo, 0, 1);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Verso IS NOT NULL AND @Verso NOT IN ('E', 'U')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Verso deve essere E (entrate) o U (uscite)';
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

		SELECT TOP (@MaxRighe + 1)
			[Data contabile] = t.DataContabile,
			[Data registrazione] = t.DataRegistrazione,
			[Banca o cassa] = t.BancaCassaNome,
			[Movimento] = IIF(t.Tipo = 'E', 'Entrata', 'Uscita'),
			[Pagamento tramite] = t.ModalitaNome,
			[Causale] = t.Causale,
			[Conto] = t.ContoNome,
			[Entrata] = t.Entrata,
			[Uscita] = t.Uscita,
			[Saldo] = t.Saldo,
			[Fatture] = t.Fatture,
			[Cliente o fornitore] = t.NomeCompleto,
			[Origine] = IIF(t.Manuale = 1, 'Movimento manuale', 'Fattura'),
			[Partita IVA] = t.PartitaIva,
			[Codice fiscale] = t.CodiceFiscale
		FROM dbo.ufnPagamenti_get_PrimaNota(@IdSessione, @DataDa, @DataA, @IdBancaCassa, @Verso, @Testo) t
		ORDER BY
			t.DataContabile,
			t.DataRegistrazione,
			t.Id
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
