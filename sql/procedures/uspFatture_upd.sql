SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva la testata della fattura. Con @Conferma = 1 (Salva) la bozza diventa attiva e, se manca,
-- riceve il numero; con @Conferma = 0 la testata viene salvata lasciando la fattura nello stato in cui
-- è (serve prima di generare le rate, che si calcolano sui dati salvati).
CREATE OR ALTER PROCEDURE dbo.uspFatture_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@IdTipo CHAR(4) = NULL,
	@IdStato CHAR(1) = NULL,
	@IdModalita CHAR(4) = NULL,
	@IdRata CHAR(3) = NULL,
	@IdRataInizio CHAR(2) = NULL,
	@IdValuta CHAR(3) = NULL,
	@IdBancaCassa CHAR(16) = NULL,
	@IdFatturaRiferimento CHAR(16) = NULL,
	@Numero INT = NULL,
	@Sezionale VARCHAR(5) = NULL,
	@NumeroFornitore VARCHAR(50) = NULL,
	@DataRegistrazione DATE = NULL,
	@DataEmissione DATE = NULL,
	@Iban VARCHAR(50) = NULL,
	@RataGiorniInizio INT = NULL,
	@Ordine VARCHAR(50) = NULL,
	@DataOrdine DATE = NULL,
	@SplitPayment BIT = 0,
	@Bollo DECIMAL(9, 2) = NULL,
	@CodiceCig VARCHAR(20) = NULL,
	@CodiceCup VARCHAR(20) = NULL,
	@Causale VARCHAR(250) = NULL,
	@Note VARCHAR(1000) = NULL,
	@SolaLettura BIT = 0,
	@Conferma BIT = 1
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Le select propongono come prima voce "(Selezionare)" con Id a zeri: vale come non indicato
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @IdTipo = UPPER(NULLIF(NULLIF(LTRIM(RTRIM(@IdTipo)), ''), REPLICATE('0', 4)));
		SET @IdStato = ISNULL(UPPER(NULLIF(NULLIF(LTRIM(RTRIM(@IdStato)), ''), '0')), 'G');
		SET @IdModalita = NULLIF(NULLIF(LTRIM(RTRIM(@IdModalita)), ''), REPLICATE('0', 4));
		SET @IdRata = NULLIF(NULLIF(LTRIM(RTRIM(@IdRata)), ''), REPLICATE('0', 3));
		SET @IdRataInizio = NULLIF(NULLIF(LTRIM(RTRIM(@IdRataInizio)), ''), REPLICATE('0', 2));
		SET @IdValuta = NULLIF(NULLIF(LTRIM(RTRIM(@IdValuta)), ''), REPLICATE('0', 3));
		SET @IdBancaCassa = NULLIF(NULLIF(LTRIM(RTRIM(@IdBancaCassa)), ''), REPLICATE('0', 16));
		SET @IdFatturaRiferimento = NULLIF(NULLIF(LTRIM(RTRIM(@IdFatturaRiferimento)), ''), REPLICATE('0', 16));
		SET @Causale = dbo.ufnStringhe_get_SenzaSpazi(@Causale, 0, 1);
		SET @Numero = NULLIF(@Numero, 0);
		SET @Sezionale = NULLIF(UPPER(LTRIM(RTRIM(@Sezionale))), '');
		SET @NumeroFornitore = NULLIF(LTRIM(RTRIM(@NumeroFornitore)), '');
		-- IBAN, CIG e CUP: maiuscolo e senza spazi interni
		SET @Iban = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@Iban)), ' ', '')), '');
		SET @CodiceCig = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@CodiceCig)), ' ', '')), '');
		SET @CodiceCup = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@CodiceCup)), ' ', '')), '');
		SET @Ordine = NULLIF(LTRIM(RTRIM(@Ordine)), '');
		SET @RataGiorniInizio = ISNULL(@RataGiorniInizio, 0);
		SET @SplitPayment = ISNULL(@SplitPayment, 0);
		SET @Bollo = ISNULL(@Bollo, 0);
		SET @SolaLettura = ISNULL(@SolaLettura, 0);
		SET @Conferma = ISNULL(@Conferma, 1);
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @tipo CHAR(1);
		DECLARE @lock INT;
		DECLARE @solaLetturaAttuale BIT;
		DECLARE @idClienteFornitoreAttuale CHAR(16);
		SELECT
			@idAzienda = f.IdSede,
			@tipo = f.Tipo,
			@lock = f.Lock,
			@solaLetturaAttuale = ISNULL(f.SolaLettura, 0),
			@idClienteFornitoreAttuale = f.IdClienteFornitore
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
		WHERE
			f.Id = @Id
			AND e.Id = @IdSessione
			AND f.Lock <= 2;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END

		-- Sola lettura: protezione dalle modifiche involontarie. Per modificare la fattura va prima tolta la spunta
		IF @solaLetturaAttuale = 1 AND @SolaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura';
			GOTO BRANCH_END;
		END

		-- Cliente o fornitore: scheda attiva dell'azienda e del tipo della fattura. La scheda già sulla
		-- fattura resta valida anche se nel frattempo è stata cancellata
		IF @IdClienteFornitore IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'C', 'Selezionare il cliente', 'Selezionare il fornitore');
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblClientiFornitori
			WHERE
				Id = @IdClienteFornitore
				AND IdAziendaInterna = @idAzienda
				AND Tipo = @tipo
				AND (Lock = 0 OR Id = @idClienteFornitoreAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'C', 'Il cliente indicato non esiste', 'Il fornitore indicato non esiste');
			GOTO BRANCH_END;
		END

		-- Tipo di documento: le autofatture (TD17, TD18, TD19) si registrano tra le fatture fornitori,
		-- la pre-fattura (TD00) si emette solo per un cliente
		IF @IdTipo IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = @IdTipo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il tipo di documento';
			GOTO BRANCH_END;
		END
		IF @tipo = 'C' AND @IdTipo IN ('TD17', 'TD18', 'TD19')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''autofattura si registra tra le fatture fornitori';
			GOTO BRANCH_END;
		END
		IF @tipo = 'F' AND @IdTipo = 'TD00'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La pre-fattura si emette solo per un cliente';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureStati WHERE Id = @IdStato)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lo stato indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Fattura di riferimento: solo per la nota di credito (TD04), facoltativa. È la fattura stornata:
		-- attiva, numerata (non una pre-fattura né un'altra nota di credito) e dello stesso cliente o fornitore
		IF @IdTipo <> 'TD04'
			SET @IdFatturaRiferimento = NULL;
		IF @IdFatturaRiferimento IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblFatture
			WHERE
				Id = @IdFatturaRiferimento
				AND Id <> @Id
				AND IdSede = @idAzienda
				AND Tipo = @tipo
				AND IdClienteFornitore = @IdClienteFornitore
				AND IdTipo NOT IN ('TD00', 'TD04')
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'C', 'La fattura di riferimento non esiste tra le fatture del cliente', 'La fattura di riferimento non esiste tra le fatture del fornitore');
			GOTO BRANCH_END;
		END
		IF LEN(@Causale) > 200
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La causale non può superare i 200 caratteri';
			GOTO BRANCH_END;
		END

		-- Date. Fattura cliente: data di emissione obbligatoria, la registrazione coincide se non indicata.
		-- Fattura fornitore: data e numero del documento ricevuto obbligatori, registrazione oggi se non indicata
		IF @DataEmissione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'C', 'Indicare la data della fattura', 'Indicare la data della fattura del fornitore');
			GOTO BRANCH_END;
		END
		IF @tipo = 'C'
			SET @DataRegistrazione = ISNULL(@DataRegistrazione, @DataEmissione);
		ELSE
			SET @DataRegistrazione = ISNULL(@DataRegistrazione, CAST(GETDATE() AS DATE));

		IF @tipo = 'F' AND @DataRegistrazione < @DataEmissione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di registrazione non può precedere la data della fattura del fornitore';
			GOTO BRANCH_END;
		END
		IF @tipo = 'F' AND @NumeroFornitore IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il numero della fattura del fornitore';
			GOTO BRANCH_END;
		END
		IF @tipo = 'C'
			SET @NumeroFornitore = NULL;
		IF LEN(@NumeroFornitore) > 30
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero della fattura del fornitore non può superare i 30 caratteri';
			GOTO BRANCH_END;
		END
		IF @DataOrdine IS NOT NULL AND @DataOrdine > @DataEmissione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data dell''ordine non può seguire la data della fattura';
			GOTO BRANCH_END;
		END
		IF LEN(@Ordine) > 30
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il riferimento dell''ordine non può superare i 30 caratteri';
			GOTO BRANCH_END;
		END

		-- Sezionale: una lettera, facoltativo (nella scheda si sceglie da una select)
		IF @Sezionale IS NOT NULL AND (LEN(@Sezionale) > 1 OR @Sezionale NOT LIKE '[A-Z]')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il sezionale è una sola lettera';
			GOTO BRANCH_END;
		END
		IF @Numero < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero della fattura non può essere negativo';
			GOTO BRANCH_END;
		END

		-- Condizioni di pagamento, come sulla scheda del cliente o del fornitore
		IF @IdModalita IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la modalità di pagamento';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = @IdModalita)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La modalità di pagamento indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @IdRata IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = @IdRata)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La rateizzazione indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @IdRataInizio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la decorrenza delle rate (campo Da)';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRateInizi WHERE Id = @IdRataInizio)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La decorrenza delle rate indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @IdValuta IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la valuta';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiValute WHERE Id = @IdValuta)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La valuta indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @RataGiorniInizio < 0 OR @RataGiorniInizio > 31
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il giorno del mese deve essere compreso tra 0 e 31';
			GOTO BRANCH_END;
		END

		-- Banca/cassa: solo dell'azienda della fattura
		IF @IdBancaCassa IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblBancheCasse
			WHERE
				Id = @IdBancaCassa
				AND IdSede = @idAzienda
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La banca o cassa indicata non esiste';
			GOTO BRANCH_END;
		END

		-- Il formato dell'IBAN è controllato dall'applicazione (Strings.cs): qui si protegge solo la lunghezza
		IF LEN(@Iban) > 34
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''IBAN non può superare i 34 caratteri';
			GOTO BRANCH_END;
		END
		-- RiBa (MP12) su una fattura cliente: serve l'IBAN della banca d'appoggio del cliente
		IF @tipo = 'C' AND @IdModalita = 'MP12' AND @Iban IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con il pagamento RiBa indicare l''IBAN del cliente';
			GOTO BRANCH_END;
		END
		IF @Bollo < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il bollo non può essere negativo';
			GOTO BRANCH_END;
		END
		IF LEN(@CodiceCig) > 10
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice CIG non può superare i 10 caratteri';
			GOTO BRANCH_END;
		END
		IF LEN(@CodiceCup) > 15
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice CUP non può superare i 15 caratteri';
			GOTO BRANCH_END;
		END

		-- Numerazione: progressiva per azienda, tipo (clienti / fornitori), anno e sezionale. L'anno è
		-- quello della data di emissione per le fatture cliente, della data di registrazione (protocollo)
		-- per le fatture fornitore. La pre-fattura non ha numero: lo riceve quando diventa fattura.
		-- Una bozza salvata senza conferma non impegna un numero
		DECLARE @dataNumero DATE = IIF(@tipo = 'C', @DataEmissione, @DataRegistrazione);
		DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@dataNumero), 1, 1);
		DECLARE @annoFine DATE = DATEADD(YEAR, 1, @annoInizio);
		DECLARE @numerata BIT = IIF(@IdTipo <> 'TD00' AND (@Conferma = 1 OR @lock = 0), 1, 0);

		IF @numerata = 0
			SET @Numero = NULL;

		BEGIN TRANSACTION;
			IF @numerata = 1 AND @Numero IS NULL
			BEGIN
				SELECT @Numero = ISNULL(MAX(Numero), 0) + 1
				FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
				WHERE
					IdSede = @idAzienda
					AND Tipo = @tipo
					AND Lock = 0
					AND Id <> @Id
					AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
					AND IIF(@tipo = 'C', DataEmissione, DataRegistrazione) >= @annoInizio
					AND IIF(@tipo = 'C', DataEmissione, DataRegistrazione) < @annoFine;
			END
			ELSE IF @numerata = 1 AND EXISTS (
				SELECT 1
				FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
				WHERE
					IdSede = @idAzienda
					AND Tipo = @tipo
					AND Lock = 0
					AND Id <> @Id
					AND Numero = @Numero
					AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
					AND IIF(@tipo = 'C', DataEmissione, DataRegistrazione) >= @annoInizio
					AND IIF(@tipo = 'C', DataEmissione, DataRegistrazione) < @annoFine
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Esiste già una fattura con questo numero nello stesso anno';
				GOTO BRANCH_END;
			END

			UPDATE dbo.tblFatture
			SET
				Lock = IIF(@Conferma = 1, 0, Lock),
				IdClienteFornitore = @IdClienteFornitore,
				IdTipo = @IdTipo,
				IdStato = @IdStato,
				IdModalita = @IdModalita,
				IdRata = @IdRata,
				IdRataInizio = @IdRataInizio,
				IdValuta = @IdValuta,
				IdBancaCassa = @IdBancaCassa,
				IdFatturaRiferimento = @IdFatturaRiferimento,
				Numero = @Numero,
				Sezionale = @Sezionale,
				NumeroFornitore = @NumeroFornitore,
				DataRegistrazione = @DataRegistrazione,
				DataEmissione = @DataEmissione,
				Iban = @Iban,
				RataGiorniInizio = @RataGiorniInizio,
				Ordine = @Ordine,
				DataOrdine = @DataOrdine,
				SplitPayment = @SplitPayment,
				Bollo = @Bollo,
				CodiceCig = @CodiceCig,
				CodiceCup = @CodiceCup,
				Causale = @Causale,
				Note = @Note,
				SolaLettura = @SolaLettura
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Fattura non trovata o già eliminata';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		IF @Conferma = 1
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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
