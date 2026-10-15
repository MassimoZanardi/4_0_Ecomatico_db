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
