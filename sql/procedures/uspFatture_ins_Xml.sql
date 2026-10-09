SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture fornitori > Carica file XML: crea la fattura fornitore in bozza (Lock 2) con la testata letta dal
-- file della fattura elettronica. Righe e rate le aggiunge poi l'applicazione con uspFattureRighe_upd e
-- uspFattureRate_upd; la bozza si conferma dalla scheda con "Salva" (uspFatture_upd), che applica tutti i
-- controlli della testata e assegna il numero.
-- Il fornitore può mancare (non trovato in anagrafica): si sceglie nella scheda. DataXml = momento del
-- caricamento: distingue le fatture nate da un file, su cui la scelta del fornitore non sostituisce le
-- condizioni di pagamento arrivate dal file.
-- Restituisce l'Id della fattura.
CREATE OR ALTER PROCEDURE dbo.uspFatture_ins_Xml
	@IdSessione CHAR(16) = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@IdTipo CHAR(4) = NULL,
	@IdModalita CHAR(4) = NULL,
	@IdValuta CHAR(3) = NULL,
	@NumeroFornitore VARCHAR(50) = NULL,
	@DataEmissione DATE = NULL,
	@Iban VARCHAR(50) = NULL,
	@Ordine VARCHAR(50) = NULL,
	@DataOrdine DATE = NULL,
	@SplitPayment BIT = 0,
	@Bollo DECIMAL(9, 2) = NULL,
	@CodiceCig VARCHAR(20) = NULL,
	@CodiceCup VARCHAR(20) = NULL,
	@Causale VARCHAR(250) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @IdTipo = ISNULL(UPPER(NULLIF(LTRIM(RTRIM(@IdTipo)), '')), 'TD01');
		SET @IdModalita = UPPER(NULLIF(LTRIM(RTRIM(@IdModalita)), ''));
		SET @IdValuta = ISNULL(UPPER(NULLIF(LTRIM(RTRIM(@IdValuta)), '')), 'EUR');
		SET @NumeroFornitore = NULLIF(LTRIM(RTRIM(@NumeroFornitore)), '');
		-- IBAN, CIG e CUP: maiuscolo e senza spazi interni
		SET @Iban = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@Iban)), ' ', '')), '');
		SET @CodiceCig = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@CodiceCig)), ' ', '')), '');
		SET @CodiceCup = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@CodiceCup)), ' ', '')), '');
		SET @Ordine = NULLIF(LTRIM(RTRIM(@Ordine)), '');
		SET @Causale = dbo.ufnStringhe_get_SenzaSpazi(@Causale, 0, 1);
		SET @SplitPayment = ISNULL(@SplitPayment, 0);
		SET @Bollo = ISNULL(@Bollo, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @NumeroFornitore IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il file non indica il numero della fattura';
			GOTO BRANCH_END;
		END
		IF @DataEmissione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il file non indica la data della fattura';
			GOTO BRANCH_END;
		END
		IF LEN(@NumeroFornitore) > 30 OR LEN(@Iban) > 34 OR LEN(@Ordine) > 30 OR LEN(@CodiceCig) > 10 OR LEN(@CodiceCup) > 15 OR LEN(@Causale) > 200
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un dato della testata supera la lunghezza ammessa';
			GOTO BRANCH_END;
		END
		IF @Bollo < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il bollo non può essere negativo';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La fattura appartiene all'azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		-- Fornitore, se indicato: scheda fornitore attiva dell'azienda
		IF @IdClienteFornitore IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblClientiFornitori
			WHERE
				Id = @IdClienteFornitore
				AND IdAziendaInterna = @idAzienda
				AND Tipo = 'F'
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il fornitore indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Tipo di documento, modalità e valuta sono codici del tracciato: la pre-fattura non è un documento ricevuto
		IF @IdTipo = 'TD00' OR NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = @IdTipo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il tipo di documento indicato non esiste';
			GOTO BRANCH_END;
		END
		IF @IdModalita IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = @IdModalita)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La modalità di pagamento indicata non esiste';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiValute WHERE Id = @IdValuta)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La valuta indicata non esiste';
			GOTO BRANCH_END;
		END

		-- Fattura già registrata: stesso fornitore, stesso numero e stesso anno del documento
		IF @IdClienteFornitore IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblFatture
			WHERE
				IdSede = @idAzienda
				AND Tipo = 'F'
				AND Lock = 0
				AND IdClienteFornitore = @IdClienteFornitore
				AND NumeroFornitore = @NumeroFornitore
				AND YEAR(DataEmissione) = YEAR(@DataEmissione)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è già registrata: stesso fornitore, stesso numero e stesso anno';
			GOTO BRANCH_END;
		END

		-- La data dell'ordine non segue quella della fattura (come in uspFatture_upd): altrimenti non si importa
		IF @DataOrdine > @DataEmissione
			SET @DataOrdine = NULL;

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		-- Bozza, come uspFatture_ins: stato Generata, rate dalla data fattura (DF), registrazione di oggi
		BEGIN TRANSACTION;
			INSERT dbo.tblFatture (
				Id, IdSede, IdClienteFornitore, Tipo, IdTipo, IdStato, IdModalita, IdValuta, IdRataInizio,
				NumeroFornitore, DataRegistrazione, DataEmissione, Causale, Iban, RataGiorniInizio, Ordine, DataOrdine,
				SplitPayment, Bollo, CodiceCig, CodiceCup, SolaLettura, Lock, DataXml)
			VALUES (
				@returnId, @idAzienda, @IdClienteFornitore, 'F', @IdTipo, 'G', @IdModalita, @IdValuta, 'DF',
				@NumeroFornitore, CAST(GETDATE() AS DATE), @DataEmissione, @Causale, @Iban, 0, @Ordine, @DataOrdine,
				@SplitPayment, @Bollo, @CodiceCig, @CodiceCup, 0, 2, GETDATE());
		COMMIT TRANSACTION;

		SELECT Id = @returnId;

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
