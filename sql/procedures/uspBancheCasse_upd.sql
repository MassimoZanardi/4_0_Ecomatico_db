SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Iban VARCHAR(50) = NULL,
	@CodiceSia VARCHAR(20) = NULL,
	@Bic VARCHAR(20) = NULL,
	@SaldoIniziale DECIMAL(18, 2) = NULL,
	@DataSaldoIniziale DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		-- IBAN, codice SIA e BIC: maiuscolo e senza spazi interni
		SET @Iban = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@Iban)), ' ', '')), '');
		SET @CodiceSia = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@CodiceSia)), ' ', '')), '');
		SET @Bic = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@Bic)), ' ', '')), '');

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
		IF @Tipo IS NULL OR @Tipo NOT IN ('B', 'C')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il tipo (banca o cassa)';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL OR LEN(@Nome) < 3
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@Tipo = 'B', 'Indicare il nome della banca (almeno 3 caratteri)', 'Indicare il nome della cassa (almeno 3 caratteri)');
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = c.IdSede
		FROM
			dbo.tblBancheCasse c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Una cassa non ha coordinate bancarie
		IF @Tipo = 'C'
		BEGIN
			SET @Iban = NULL;
			SET @CodiceSia = NULL;
			SET @Bic = NULL;
		END

		-- Banca: IBAN obbligatorio. Il formato di IBAN, BIC e codice SIA è controllato dall'applicazione
		-- (Strings.cs): qui si protegge solo la lunghezza delle colonne
		IF @Tipo = 'B' AND @Iban IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il codice IBAN';
			GOTO BRANCH_END;
		END
		IF LEN(@Iban) > 34
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''IBAN non può superare i 34 caratteri';
			GOTO BRANCH_END;
		END
		IF LEN(@Bic) > 11
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice BIC non può superare gli 11 caratteri';
			GOTO BRANCH_END;
		END
		IF LEN(@CodiceSia) > 5
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice SIA non può superare i 5 caratteri';
			GOTO BRANCH_END;
		END

		-- Saldo iniziale, per la prima nota: importo (anche negativo) e data si indicano insieme. È il saldo
		-- all'inizio del giorno indicato: il saldo progressivo parte da lì
		IF (@SaldoIniziale IS NULL AND @DataSaldoIniziale IS NOT NULL) OR (@SaldoIniziale IS NOT NULL AND @DataSaldoIniziale IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Per il saldo iniziale indicare sia l''importo sia la data';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un'altra banca o cassa attiva con lo stesso nome nella stessa azienda
		IF EXISTS (
			SELECT 1
			FROM dbo.tblBancheCasse
			WHERE
				Id <> @Id
				AND IdSede = @idAzienda
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra banca o cassa con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblBancheCasse
			SET
				Lock = 0,
				Tipo = @Tipo,
				Nome = @Nome,
				Iban = @Iban,
				CodiceSia = @CodiceSia,
				Bic = @Bic,
				SaldoIniziale = @SaldoIniziale,
				DataSaldoIniziale = @DataSaldoIniziale
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Banca o cassa non trovata o già eliminata';
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
