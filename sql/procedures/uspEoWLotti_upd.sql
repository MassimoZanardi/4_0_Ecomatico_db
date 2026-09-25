SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdMagazzino CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@Nome VARCHAR(50) = NULL,
	@DataApertura DATE = NULL,
	@DataChiusura DATE = NULL,
	@QuantitaMax DECIMAL(18, 2) = NULL,
	@Disabilitato BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdMagazzino = NULLIF(LTRIM(RTRIM(@IdMagazzino)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Disabilitato = ISNULL(@Disabilitato, 0);

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
		IF @IdMateriale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMateriale non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataApertura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataApertura non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataChiusura IS NOT NULL AND @DataChiusura < @DataApertura
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di chiusura non può essere precedente alla data di apertura';
			GOTO BRANCH_END;
		END
		IF @QuantitaMax IS NOT NULL AND @QuantitaMax <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità massima deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede reale del lotto
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblEoWLotti c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il materiale deve esistere in anagrafica (tblRifiutiMateriali, nessuna anagrafica EoW parallela)
		IF NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiMateriali WHERE Id = @IdMateriale)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il materiale indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Il magazzino, se indicato, deve appartenere alla stessa sede del lotto
		IF @IdMagazzino IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWMagazzini
			WHERE
				Id = @IdMagazzino
				AND IdSede = @idSede
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il magazzino selezionato non appartiene alla sede del lotto';
			GOTO BRANCH_END;
		END

		-- Non è possibile cambiare il materiale se il lotto ha già registrazioni M associate
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti
			WHERE
				Id = @Id
				AND Lock = 0
				AND IdMateriale <> @IdMateriale
				AND EXISTS (SELECT 1 FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdLotto = @Id)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare il materiale di un lotto con registrazioni associate';
			GOTO BRANCH_END;
		END

		-- La quantità massima non può scendere sotto la produzione già attribuita al lotto (quote
		-- di registrazioni M attive): il lotto EoW è una partita di produzione. Aumentarla è
		-- sempre possibile (riapre capienza, se il lotto non è chiuso).
		DECLARE @quantitaAttribuita DECIMAL(18, 2) = ISNULL((
			SELECT SUM(q.Quantita)
			FROM
				dbo.tblEoWLottiRifiutiRegistrazioni q
				INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id
			WHERE
				q.IdLotto = @Id
				AND rr.Lock < 2
		), 0);
		IF @QuantitaMax IS NOT NULL AND @QuantitaMax < @quantitaAttribuita
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità massima non può essere inferiore alla quantità già attribuita al lotto (' + FORMAT(@quantitaAttribuita, 'N2', 'it-IT') + ')';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro lotto attivo con lo stesso nome nella stessa sede
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti
			WHERE
				Id <> @Id
				AND IdSede = @idSede
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro lotto con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblEoWLotti
			SET
				Lock = 0,
				IdMagazzino = @IdMagazzino,
				IdMateriale = @IdMateriale,
				Nome = @Nome,
				DataApertura = @DataApertura,
				DataChiusura = @DataChiusura,
				QuantitaMax = @QuantitaMax,
				Disabilitato = @Disabilitato
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Lotto non trovato o già eliminato';
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
