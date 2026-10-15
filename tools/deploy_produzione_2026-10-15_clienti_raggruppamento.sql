/*
Deploy produzione 2026-10-15 - Clienti: raggruppamento delle fatture nella scheda del cliente

Indipendente dagli altri script. Rieseguibile. Eseguire con sqlcmd -f 65001 -I (oppure da SSMS).
Va deployato insieme all'app (Anagrafica > Clienti: nuova select "Raggruppamento delle fatture").

La colonna tblClientiFornitori.IdRaggruppamento (tblFattureRaggruppamenti: C cliente, S sede, T contratto) esisteva
già ed era usata dalla procedura automatica, ma la scheda del cliente non la leggeva né la scriveva.
1. uspClientiFornitori_get_Raggruppamenti_SelectList: nuova, la select della scheda.
2. uspClientiFornitori_get: IdRaggruppamento (per un cliente, C se vuoto).
3. uspClientiFornitori_upd: nuovo parametro @IdRaggruppamento, solo per i clienti (C se non indicato), azzerato
   per i fornitori.
4. uspClientiFornitori_ins: una scheda cliente nuova nasce con C.
5. Dati: i clienti senza raggruppamento passano a C (stesso comportamento di prima).
Regole: anagrafica-estesa.md X2.14, offerte-contratti.md O6.3 (repo app).
*/

-- ===== uspClientiFornitori_get_Raggruppamenti_SelectList
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_get_Raggruppamenti_SelectList
	@IdSelected CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		SELECT
			Id,
			[Text] = Nome,
			Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblFattureRaggruppamenti
		ORDER BY Id;

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

-- ===== uspClientiFornitori_get
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_get
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @tipo CHAR(1);
		SELECT @tipo = c.Tipo
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @tipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: ANC per i clienti, ANF per i fornitori
		DECLARE @idFunzione CHAR(3) = IIF(@tipo = 'C', 'ANC', 'ANF');
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

		IF NOT EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE Id = @Id AND Lock <= 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'C', 'Cliente non trovato', 'Fornitore non trovato');
			GOTO BRANCH_END;
		END

		-- I dati anagrafici del soggetto sono in sola lettura: si modificano in Anagrafica > Soggetti
		SELECT
			c.Id,
			c.IdAziendaInterna,
			c.IdSede,
			c.Tipo,
			c.IdModalita,
			c.IdRata,
			c.IdRataInizio,
			c.IdBancaCassa,
			c.IdAliquotaIva,
			c.IdValuta,
			SplitPayment = ISNULL(c.SplitPayment, 0),
			c.Iban,
			RataGiorniInizio = ISNULL(c.RataGiorniInizio, 0),
			ImportoMinimoFatturabile = ISNULL(c.ImportoMinimoFatturabile, 0),
			RitenutaAcconto = ISNULL(c.RitenutaAcconto, 0),
			c.CodiceDestinatario,
			c.PecDestinatario,
			c.Note,
			-- Raggruppamento delle fatture: per i clienti, per cliente (C) se non indicato
			IdRaggruppamento = IIF(c.Tipo = 'C', ISNULL(c.IdRaggruppamento, 'C'), NULL),
			c.Lock,
			SedeNomeCompleto = s.NomeCompleto,
			SedeIndirizzoCompleto = s.IndirizzoCompleto,
			SedeCodiceFiscale = s.CodiceFiscale,
			SedePartitaIva = s.PartitaIva,
			SedeDisabilitata = ISNULL(s.Disabilitata, 0)
		FROM
			dbo.tblClientiFornitori c
			LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE
			c.Id = @Id
			AND c.Lock <= 2;

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

-- ===== uspClientiFornitori_upd
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@IdModalita CHAR(4) = NULL,
	@IdRata CHAR(3) = NULL,
	@IdRataInizio CHAR(2) = NULL,
	@IdBancaCassa CHAR(16) = NULL,
	@IdAliquotaIva CHAR(16) = NULL,
	@IdValuta CHAR(3) = NULL,
	@SplitPayment BIT = 0,
	@Iban VARCHAR(50) = NULL,
	@RataGiorniInizio INT = NULL,
	@ImportoMinimoFatturabile DECIMAL(18, 2) = NULL,
	@RitenutaAcconto INT = NULL,
	@CodiceDestinatario VARCHAR(20) = NULL,
	@PecDestinatario VARCHAR(100) = NULL,
	@Note VARCHAR(1000) = NULL,
	@IdRaggruppamento CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Le select propongono come prima voce "(Selezionare)" con Id a zeri: vale come non indicato
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(NULLIF(LTRIM(RTRIM(@IdSede)), ''), REPLICATE('0', 16));
		SET @IdModalita = NULLIF(NULLIF(LTRIM(RTRIM(@IdModalita)), ''), REPLICATE('0', 4));
		SET @IdRata = NULLIF(NULLIF(LTRIM(RTRIM(@IdRata)), ''), REPLICATE('0', 3));
		SET @IdRataInizio = NULLIF(NULLIF(LTRIM(RTRIM(@IdRataInizio)), ''), REPLICATE('0', 2));
		SET @IdBancaCassa = NULLIF(NULLIF(LTRIM(RTRIM(@IdBancaCassa)), ''), REPLICATE('0', 16));
		SET @IdAliquotaIva = NULLIF(NULLIF(LTRIM(RTRIM(@IdAliquotaIva)), ''), REPLICATE('0', 16));
		SET @IdValuta = NULLIF(NULLIF(LTRIM(RTRIM(@IdValuta)), ''), REPLICATE('0', 3));
		SET @SplitPayment = ISNULL(@SplitPayment, 0);
		-- Giorno del mese, importo minimo fatturabile e ritenuta d'acconto non indicati valgono 0
		SET @RataGiorniInizio = ISNULL(@RataGiorniInizio, 0);
		SET @ImportoMinimoFatturabile = ISNULL(@ImportoMinimoFatturabile, 0);
		SET @RitenutaAcconto = ISNULL(@RitenutaAcconto, 0);
		-- IBAN e codice destinatario: maiuscolo e senza spazi interni
		SET @Iban = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@Iban)), ' ', '')), '');
		SET @CodiceDestinatario = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@CodiceDestinatario)), ' ', '')), '');
		SET @PecDestinatario = NULLIF(LOWER(LTRIM(RTRIM(@PecDestinatario))), '');
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);
		SET @IdRaggruppamento = NULLIF(UPPER(LTRIM(RTRIM(@IdRaggruppamento))), '');

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

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @tipo CHAR(1);
		DECLARE @idSedeAttuale CHAR(16);
		SELECT
			@idAzienda = c.IdAziendaInterna,
			@tipo = c.Tipo,
			@idSedeAttuale = c.IdSede
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: ANC per i clienti, ANF per i fornitori
		DECLARE @idFunzione CHAR(3) = IIF(@tipo = 'C', 'ANC', 'ANF');
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Soggetto: obbligatorio e di proprietà dell'azienda della scheda. Un soggetto visto tramite
		-- un'area appartiene a un'altra azienda e non può diventare cliente o fornitore
		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il soggetto';
			GOTO BRANCH_END;
		END

		DECLARE @sedeDisabilitata BIT;
		DECLARE @sedeTrovata BIT = 0;
		SELECT
			@sedeTrovata = 1,
			@sedeDisabilitata = ISNULL(s.Disabilitata, 0)
		FROM dbo.tblSedi s
		WHERE
			s.Id = @IdSede
			AND s.InternaEsterna = 'E'
			AND s.IdParent IS NULL
			AND s.Lock = 0
			AND s.IdAziendaInterna = @idAzienda;

		IF @sedeTrovata = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il soggetto non appartiene all''azienda';
			GOTO BRANCH_END;
		END
		-- Un soggetto disabilitato resta sulla scheda che lo ha già, ma non si sceglie su un'altra
		IF @sedeDisabilitata = 1 AND (@idSedeAttuale IS NULL OR @idSedeAttuale <> @IdSede)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il soggetto è disabilitato';
			GOTO BRANCH_END;
		END

		-- Una sola scheda attiva per soggetto e tipo nella stessa azienda
		IF EXISTS (
			SELECT 1
			FROM dbo.tblClientiFornitori
			WHERE
				Id <> @Id
				AND IdAziendaInterna = @idAzienda
				AND IdSede = @IdSede
				AND Tipo = @tipo
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'C', 'Il soggetto è già presente tra i clienti', 'Il soggetto è già presente tra i fornitori');
			GOTO BRANCH_END;
		END

		-- Condizioni di pagamento: la modalità è obbligatoria
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
		-- Decorrenza delle rate (campo "Da"): obbligatoria
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
		-- Giorno del mese per le scadenze posticipate rispetto alla fine del mese (0 o vuoto = nessuno)
		IF @RataGiorniInizio < 0 OR @RataGiorniInizio > 31
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il giorno del mese deve essere compreso tra 0 e 31';
			GOTO BRANCH_END;
		END
		IF @ImportoMinimoFatturabile < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo minimo fatturabile non può essere negativo';
			GOTO BRANCH_END;
		END
		IF @RitenutaAcconto < 0 OR @RitenutaAcconto > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La ritenuta d''acconto deve essere compresa tra 0 e 100';
			GOTO BRANCH_END;
		END

		-- Banca/cassa: solo dell'azienda della scheda
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

		-- Aliquota IVA: di sistema (IdSede NULL) o dell'azienda della scheda
		IF @IdAliquotaIva IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblAliquoteIva
			WHERE
				Id = @IdAliquotaIva
				AND (IdSede IS NULL OR IdSede = @idAzienda)
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''aliquota IVA indicata non esiste';
			GOTO BRANCH_END;
		END

		-- Il formato di IBAN, codice destinatario e PEC è controllato dall'applicazione (Strings.cs): qui si
		-- protegge solo la lunghezza delle colonne
		IF LEN(@Iban) > 34
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''IBAN non può superare i 34 caratteri';
			GOTO BRANCH_END;
		END
		-- RiBa (MP12) su un cliente: serve l'IBAN della sua banca d'appoggio
		IF @tipo = 'C' AND @IdModalita = 'MP12' AND @Iban IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con il pagamento RiBa indicare l''IBAN del cliente';
			GOTO BRANCH_END;
		END

		IF LEN(@CodiceDestinatario) > 7
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice destinatario non può superare i 7 caratteri';
			GOTO BRANCH_END;
		END

		-- Raggruppamento delle fatture della procedura automatica (tblFattureRaggruppamenti): solo per i clienti,
		-- per cliente (C) se non indicato; i fornitori non ne hanno
		IF @tipo = 'C'
		BEGIN
			SET @IdRaggruppamento = ISNULL(@IdRaggruppamento, 'C');
			IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureRaggruppamenti WHERE Id = @IdRaggruppamento)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il raggruppamento delle fatture indicato non esiste';
				GOTO BRANCH_END;
			END
		END
		ELSE
			SET @IdRaggruppamento = NULL;

		BEGIN TRANSACTION;
			UPDATE dbo.tblClientiFornitori
			SET
				Lock = 0,
				IdSede = @IdSede,
				IdModalita = @IdModalita,
				IdRata = @IdRata,
				IdRataInizio = @IdRataInizio,
				IdBancaCassa = @IdBancaCassa,
				IdAliquotaIva = @IdAliquotaIva,
				IdValuta = @IdValuta,
				SplitPayment = @SplitPayment,
				Iban = @Iban,
				RataGiorniInizio = @RataGiorniInizio,
				ImportoMinimoFatturabile = @ImportoMinimoFatturabile,
				RitenutaAcconto = @RitenutaAcconto,
				CodiceDestinatario = @CodiceDestinatario,
				PecDestinatario = @PecDestinatario,
				Note = @Note,
				IdRaggruppamento = @IdRaggruppamento
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = IIF(@tipo = 'C', 'Cliente non trovato o già eliminato', 'Fornitore non trovato o già eliminato');
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

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

-- ===== uspClientiFornitori_ins
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_ins
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));

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
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La scheda appartiene all'azienda interna corrente della sessione
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

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		-- Bozza: il soggetto si sceglie nella scheda. Valori predefiniti: valuta euro; decorrenza delle rate dalla data fattura (DF); giorno del mese, importo minimo fatturabile e ritenuta d'acconto a 0; per un cliente
		-- le fatture della procedura automatica raggruppate per cliente (C)
		BEGIN TRANSACTION;
			INSERT dbo.tblClientiFornitori (Id, IdAziendaInterna, Tipo, IdValuta, IdRataInizio, SplitPayment, RataGiorniInizio, ImportoMinimoFatturabile, RitenutaAcconto, IdRaggruppamento, Lock)
			VALUES (@returnId, @idAzienda, @Tipo, 'EUR', 'DF', 0, 0, 0, 0, IIF(@Tipo = 'C', 'C', NULL), 2);
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

-- ===== Dati: clienti senza raggruppamento
SET QUOTED_IDENTIFIER ON
GO
UPDATE dbo.tblClientiFornitori SET IdRaggruppamento = 'C' WHERE Tipo = 'C' AND IdRaggruppamento IS NULL;
GO
