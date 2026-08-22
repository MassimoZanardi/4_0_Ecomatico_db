CREATE PROCEDURE [dbo].[uspRifiutiFormulari_ins]
	@IdSessione CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@IdModello CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');
		SET @IdModello = NULLIF(LTRIM(RTRIM(@IdModello)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idRegistro CHAR(16);
		SELECT @idRegistro = IdRegistro
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il registro';
			GOTO BRANCH_END;
		END

		-- Titolarità sul modello: senza questo controllo, chiunque avesse permesso RFR
		-- poteva creare un formulario copiando i dati (EER, autorizzazioni, imballo, ecc.)
		-- di un modello di un'altra azienda, conoscendone l'Id — stesso pattern già usato
		-- in uspRifiutiModelli_get.
		IF @IdModello IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @IdModello)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- uspId_get gestisce la propria transazione internamente: chiamata FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		DECLARE @idMovimento CHAR(16);
		-- Genera l'Id del movimento FUORI dalla transazione: usato in entrambi i rami IF/ELSE IF
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;

		BEGIN TRANSACTION;

			IF @IdOperazione IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimenti
					(Id, IdRegistro, IdOperazione)
				VALUES
					(@idMovimento, @idRegistro, @IdOperazione);

				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, Lock)
				VALUES
					(@returnId, @idMovimento, 2);
			END
			ELSE IF @IdModello IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimenti
					(Id, IdRegistro, IdOperazione, IdUnitaMisura, IdEer, IdStatoFisico, IdAttivita, Note)
				SELECT @idMovimento, @idRegistro, IdOperazione, IdUnitaMisura, IdEer, IdStatoFisico, IdAttivita, UtenteNote
				FROM dbo.tblRifiutiModelli
				WHERE Id = @IdModello;

				IF EXISTS (SELECT 1
				FROM dbo.tblRifiutiModelli
				WHERE
					Id = @IdModello
					AND IdAutorizzazioneProduttoreDetentore IS NOT NULL
				)
					INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Pos)
					SELECT @idMovimento, IdAutorizzazioneProduttoreDetentore, 0
					FROM dbo.tblRifiutiModelli
					WHERE Id = @IdModello;

				IF EXISTS (SELECT 1
				FROM dbo.tblRifiutiModelli
				WHERE
					Id = @IdModello
					AND IdAutorizzazioneDestinatario IS NOT NULL
				)
					INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
					SELECT @idMovimento, IdAutorizzazioneDestinatario, 0
					FROM dbo.tblRifiutiModelli
					WHERE Id = @IdModello;

				IF EXISTS (SELECT 1
				FROM dbo.tblRifiutiModelli
				WHERE
					Id = @IdModello
					AND IdAutorizzazioneTrasportatore1 IS NOT NULL
				)
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					SELECT @idMovimento, IdAutorizzazioneTrasportatore1, IdTipoTrasporto1, 0
					FROM dbo.tblRifiutiModelli
					WHERE Id = @IdModello;

				IF EXISTS (SELECT 1
				FROM dbo.tblRifiutiModelli
				WHERE
					Id = @IdModello
					AND IdAutorizzazioneIntermediario1 IS NOT NULL
				)
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					SELECT @idMovimento, IdAutorizzazioneIntermediario1, 0
					FROM dbo.tblRifiutiModelli
					WHERE Id = @IdModello;

				IF EXISTS (SELECT 1
				FROM dbo.tblRifiutiModelliClassiPericolo
				WHERE Id = @IdModello)
					INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
					SELECT @idMovimento, IdClasse
					FROM dbo.tblRifiutiModelliClassiPericolo
					WHERE Id = @IdModello;

				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, IdImballo, IdAdr, Note, Lock)
				SELECT @returnId, @idMovimento, IdImballo, IdAdr, Note, 2
				FROM dbo.tblRifiutiModelli
				WHERE Id = @IdModello;

				IF EXISTS (SELECT 1
				FROM dbo.tblRifiutiModelliEtichette
				WHERE Id = @IdModello)
					INSERT dbo.tblRifiutiFormulariEtichette (Id, IdEtichetta)
					SELECT @returnId, IdEtichetta
					FROM dbo.tblRifiutiModelliEtichette
					WHERE Id = @IdModello;
			END
			ELSE
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Parametro per Operazione o Modello non disponibile';
				GOTO BRANCH_END;
			END

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
