SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Prima nota: salva un movimento manuale, cioè un'entrata o un'uscita dell'azienda non legata a rate di fatture
-- (spese bancarie, prelievi, versamenti, stipendi; un giroconto sono due movimenti). Con @Id vuoto lo
-- inserisce, altrimenti lo modifica. @Tipo: E entrata, U uscita.
-- Si modificano solo i movimenti manuali: i pagamenti delle fatture (quelli con quote in tblFattureRatePagamenti)
-- si registrano e si annullano nello scadenziario.
-- Restituisce l'Id del movimento.
CREATE OR ALTER PROCEDURE dbo.uspPagamenti_upd_Manuale
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@DataRegistrazione DATE = NULL,
	@DataContabile DATE = NULL,
	@IdBancaCassa CHAR(16) = NULL,
	@IdModalita CHAR(4) = NULL,
	@IdConto CHAR(16) = NULL,
	@Causale VARCHAR(150) = NULL,
	@Importo DECIMAL(18, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Le select propongono come prima voce "(Selezionare)" con Id a zeri: vale come non indicato
		SET @Id = NULLIF(NULLIF(LTRIM(RTRIM(@Id)), ''), REPLICATE('0', 16));
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @IdBancaCassa = NULLIF(NULLIF(LTRIM(RTRIM(@IdBancaCassa)), ''), REPLICATE('0', 16));
		SET @IdModalita = NULLIF(NULLIF(LTRIM(RTRIM(@IdModalita)), ''), REPLICATE('0', 4));
		SET @IdConto = NULLIF(NULLIF(LTRIM(RTRIM(@IdConto)), ''), REPLICATE('0', 16));
		SET @Causale = dbo.ufnStringhe_get_SenzaSpazi(@Causale, 0, 1);
		SET @DataRegistrazione = ISNULL(@DataRegistrazione, CAST(GETDATE() AS DATE));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('E', 'U')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare se il movimento è un''entrata o un''uscita';
			GOTO BRANCH_END;
		END
		IF @DataContabile IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data contabile del movimento';
			GOTO BRANCH_END;
		END
		IF @IdBancaCassa IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la banca o la cassa';
			GOTO BRANCH_END;
		END
		IF ISNULL(@Importo, 0) <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo del movimento deve essere maggiore di zero';
			GOTO BRANCH_END;
		END
		IF @Causale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la causale del movimento';
			GOTO BRANCH_END;
		END
		IF LEN(@Causale) > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La causale non può superare i 100 caratteri';
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

		-- Il movimento appartiene all'azienda interna corrente della sessione
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

		-- Movimento esistente: attivo, dell'azienda e manuale. Banca, cassa e conto già sul movimento restano
		-- validi anche se nel frattempo sono stati cancellati
		DECLARE @idBancaCassaAttuale CHAR(16);
		DECLARE @idContoAttuale CHAR(16);
		IF @Id IS NOT NULL
		BEGIN
			DECLARE @trovato BIT = 0;
			SELECT
				@trovato = 1,
				@idBancaCassaAttuale = IdBancaCassa,
				@idContoAttuale = IdConto
			FROM dbo.tblPagamenti
			WHERE
				Id = @Id
				AND IdSede = @idAzienda
				AND Lock = 0;

			IF @trovato = 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari, o il movimento non esiste o è già stato cancellato';
				GOTO BRANCH_END;
			END
			IF EXISTS (SELECT 1 FROM dbo.tblFattureRatePagamenti WHERE IdPagamento = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il pagamento di una fattura si registra e si annulla nello scadenziario';
				GOTO BRANCH_END;
			END
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblBancheCasse
			WHERE
				Id = @IdBancaCassa
				AND IdSede = @idAzienda
				AND (Lock = 0 OR Id = @idBancaCassaAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La banca o cassa indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @IdModalita IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = @IdModalita)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La modalità di pagamento indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @IdConto IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblFattureConti
			WHERE
				Id = @IdConto
				AND IdSede = @idAzienda
				AND (Lock = 0 OR Id = @idContoAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il conto indicato non esiste';
			GOTO BRANCH_END;
		END

		IF @Id IS NULL
		BEGIN
			-- uspId_get FUORI dalla transazione
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @Id OUTPUT;

			BEGIN TRANSACTION;
				INSERT dbo.tblPagamenti (Id, IdSede, IdBancaCassa, IdModalita, IdConto, Tipo, Causale, DataRegistrazione, DataContabile, Importo, Lock)
				VALUES (@Id, @idAzienda, @IdBancaCassa, @IdModalita, @IdConto, @Tipo, @Causale, @DataRegistrazione, @DataContabile, @Importo, 0);
			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			BEGIN TRANSACTION;
				UPDATE dbo.tblPagamenti
				SET
					IdBancaCassa = @IdBancaCassa,
					IdModalita = @IdModalita,
					IdConto = @IdConto,
					Tipo = @Tipo,
					Causale = @Causale,
					DataRegistrazione = @DataRegistrazione,
					DataContabile = @DataContabile,
					Importo = @Importo
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Movimento non trovato o già cancellato';
					GOTO BRANCH_END;
				END
			COMMIT TRANSACTION;

			-- Log FUORI dalla transazione
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';
		END

		SELECT Id = @Id;

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
