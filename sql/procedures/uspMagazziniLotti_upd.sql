SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniLotti_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdArticolo CHAR(16) = NULL,
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
		SET @IdArticolo = NULLIF(LTRIM(RTRIM(@IdArticolo)), '');
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
		IF @IdArticolo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''articolo';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il nome';
			GOTO BRANCH_END;
		END
		IF @DataApertura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data di apertura';
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
			@IdFunzione = 'MGC',
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
			dbo.tblMagazziniLotti c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'articolo deve esistere, essere attivo, e appartenere alla stessa azienda della
		-- sede del lotto (Sede = Azienda stessa, oppure Sede.IdParent = Azienda dell'articolo)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniArticoli art
				INNER JOIN dbo.tblSedi s ON s.Id = @idSede
			WHERE
				art.Id = @IdArticolo
				AND art.Lock = 0
				AND (art.IdSede = @idSede OR art.IdSede = s.IdParent)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''articolo selezionato non appartiene all''azienda della sede del lotto';
			GOTO BRANCH_END;
		END

		-- Non è possibile cambiare l'articolo se il lotto ha già ripartizioni associate
		IF EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniLotti
			WHERE
				Id = @Id
				AND Lock = 0
				AND IdArticolo <> @IdArticolo
				AND EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE IdLotto = @Id)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare l''articolo di un lotto con movimenti associati';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro lotto attivo con lo stesso nome nella stessa sede
		IF EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniLotti
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
			UPDATE dbo.tblMagazziniLotti
			SET
				Lock = 0,
				IdArticolo = @IdArticolo,
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
