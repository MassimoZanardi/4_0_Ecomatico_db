SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RFR', @Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: verifica prima di tutto se il formulario esiste, indipendentemente dalla
		-- titolarità sottostante — mai esistito o già cancellato (es. doppio invio della
		-- richiesta di annullamento lato UI) viene trattato come cancellazione già avvenuta con
		-- successo, non come errore.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRifiutiFormulari
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Titolarità: prima non esisteva alcun controllo che @Id appartenesse
		-- all'azienda della sessione (via registro/sede) — stesso pattern di
		-- uspRifiutiFormulari_get.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
				INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE f.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblRifiutiFormulari
		WHERE Id = @Id);

		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		SELECT @rentriIdentificativo = r.RentriIdentificativo, @rentriData = r.RentriData
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento AND r.Lock < 2
		WHERE f.Id = @Id;

		-- Se la registrazione associata è già stata trasmessa a RENTRI, il formulario non può
		-- più essere cancellato (un formulario senza registrazione associata resta cancellabile)
		IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione associata è già stata inviata al RENTRI: il formulario non può più essere cancellato';
			GOTO BRANCH_END;
		END

		-- Se il record è già stato aggiunto
		IF @lock = 0
		BEGIN
			BEGIN TRANSACTION;

				UPDATE dbo.tblRifiutiFormulari
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT dbo.tblIdCancellati (Id, IdSessione, [Data]) VALUES (@Id, @IdSessione, GETDATE());

			COMMIT TRANSACTION;

			-- Aggiorna il log (fuori dalla transazione)
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END
		ELSE IF @lock = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione non confermata non può essere cancellata';
			GOTO BRANCH_END;
		END
		ELSE IF @lock = 2
		BEGIN
			DECLARE @idMovimento CHAR(16);
			SELECT @idMovimento = IdMovimento
			FROM dbo.tblRifiutiFormulari
			WHERE Id = @Id;

			BEGIN TRANSACTION;

				DELETE dbo.tblRifiutiMovimentiClassiPericolo
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiMovimentiProduttori
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiMovimentiDestinatari
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiMovimentiTrasportatori
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiMovimentiIntermediari
				WHERE Id = @idMovimento;
				-- Mancante in precedenza: dettaglio 1:1 a chiave condivisa (Id NOT NULL) di
				-- tblRifiutiMovimenti, blocca la DELETE su tblRifiutiMovimenti se esistono righe
				DELETE dbo.tblRifiutiMovimentiLog
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiFormulariEtichette
				WHERE Id = @Id;
				-- Aggiunte per il recente cambio di schema: dettagli 1:1 a chiave condivisa
				-- (Id NOT NULL) di tblRifiutiFormulari, bloccano la DELETE su tblRifiutiFormulari
				-- se esistono righe
				DELETE dbo.tblRifiutiFormulariTrasportiFerroviari
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulariTrasportiMarittimi
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulariTrasportiTerresti
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulari
				WHERE IdMovimento = @idMovimento;
				DELETE dbo.tblRifiutiMovimenti
				WHERE Id = @idMovimento;
				DELETE dbo.tblIdLog
				WHERE
					Id = @Id
					OR Id = @idMovimento;
				DELETE dbo.tblId
				WHERE
					Id = @Id
					OR Id = @idMovimento;

			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il formulario è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

		END

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
		THROW 50001, @returnMessage, 1
	END

END;

