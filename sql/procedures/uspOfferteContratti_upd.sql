SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva un contratto o un'offerta di un cliente e conferma la bozza (Lock 2 -> 0).
-- @Tipo: C contratto, O offerta. Si può cambiare: un'offerta accettata diventa contratto, con i suoi importi.
-- Solo gli importi di un contratto vengono applicati nella fatturazione, per i documenti con data compresa tra
-- inizio e fine: per questo le due date sono obbligatorie.
-- Ordine, CIG e CUP vengono riportati sulle fatture generate: stessi limiti della fattura (uspFatture_upd).
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@DataInizio DATE = NULL,
	@DataFine DATE = NULL,
	@Descrizione VARCHAR(1000) = NULL,
	@Protocollo VARCHAR(50) = NULL,
	@Ordine VARCHAR(50) = NULL,
	@DataOrdine DATE = NULL,
	@CodiceCig VARCHAR(20) = NULL,
	@CodiceCup VARCHAR(20) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @Tipo = NULLIF(UPPER(LTRIM(RTRIM(@Tipo))), '');
		SET @Descrizione = NULLIF(LTRIM(RTRIM(@Descrizione)), '');
		SET @Protocollo = dbo.ufnStringhe_get_SenzaSpazi(@Protocollo, 0, 1);
		SET @Ordine = dbo.ufnStringhe_get_SenzaSpazi(@Ordine, 0, 1);
		SET @CodiceCig = NULLIF(REPLACE(UPPER(@CodiceCig), ' ', ''), '');
		SET @CodiceCup = NULLIF(REPLACE(UPPER(@CodiceCup), ' ', ''), '');

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
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'O')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il tipo: contratto oppure offerta';
			GOTO BRANCH_END;
		END
		IF @IdClienteFornitore IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il cliente';
			GOTO BRANCH_END;
		END
		IF @DataInizio IS NULL OR @DataFine IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare le date di inizio e di fine della validità';
			GOTO BRANCH_END;
		END
		IF @DataFine < @DataInizio
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine non può precedere la data di inizio';
			GOTO BRANCH_END;
		END
		IF LEN(@Ordine) > 30
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''ordine non può superare i 30 caratteri';
			GOTO BRANCH_END;
		END
		IF LEN(@CodiceCig) > 10
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il CIG non può superare i 10 caratteri';
			GOTO BRANCH_END;
		END
		IF LEN(@CodiceCup) > 15
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il CUP non può superare i 15 caratteri';
			GOTO BRANCH_END;
		END
		IF @DataOrdine IS NOT NULL AND @DataOrdine > @DataFine
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data dell''ordine non può seguire la data di fine della validità';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @idClienteFornitoreAttuale CHAR(16);
		SELECT
			@idAzienda = oc.IdSede,
			@idClienteFornitoreAttuale = oc.IdClienteFornitore
		FROM
			dbo.tblOfferteContratti oc
			INNER JOIN dbo.tblSessioni e ON oc.IdSede = e.IdAzienda
		WHERE
			oc.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Cliente: una scheda cliente attiva dell'azienda; quella già sul contratto resta valida
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblClientiFornitori
			WHERE
				Id = @IdClienteFornitore
				AND IdAziendaInterna = @idAzienda
				AND Tipo = 'C'
				AND (Lock = 0 OR Id = @idClienteFornitoreAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il cliente indicato non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblOfferteContratti
			SET
				Lock = 0,
				IdClienteFornitore = @IdClienteFornitore,
				Tipo = @Tipo,
				ClienteFornitoreTipo = 'C',
				DataInizio = @DataInizio,
				DataFine = @DataFine,
				Descrizione = @Descrizione,
				Protocollo = @Protocollo,
				Ordine = @Ordine,
				DataOrdine = @DataOrdine,
				CodiceCig = @CodiceCig,
				CodiceCup = @CodiceCup
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Contratto non trovato o già eliminato';
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
