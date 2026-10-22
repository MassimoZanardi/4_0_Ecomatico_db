SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Collega una sede all'operatore DIWASS (Collega) o ne aggiorna la copia dei dati (Aggiorna da DIWASS). I dati
-- arrivano dal dettaglio letto da DIWASS dall'applicazione, non dalla pagina. Regole (docs/regole/diwass.md, D4):
-- l'azienda si collega a una sede principale DIWASS, una sua sede a un sito registrato sotto l'operatore
-- dell'azienda; i soggetti condivisi da altre aziende sono in sola lettura
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassOperatori_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@OperatorInternalId BIGINT = NULL,
	@LinkedOperatorInternalId BIGINT = NULL,
	@Nome VARCHAR(250) = NULL,
	@Indirizzo VARCHAR(500) = NULL,
	@Paese CHAR(2) = NULL,
	@Identificativo VARCHAR(100) = NULL,
	@Stato VARCHAR(20) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = NULLIF(LTRIM(RTRIM(@Nome)), '');
		SET @Indirizzo = NULLIF(LTRIM(RTRIM(@Indirizzo)), '');
		SET @Paese = NULLIF(LTRIM(RTRIM(@Paese)), '');
		SET @Identificativo = NULLIF(LTRIM(RTRIM(@Identificativo)), '');
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');

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
		IF @OperatorInternalId IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @OperatorInternalId non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWO',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): solo le sedi dell'azienda del contesto, non quelle condivise
		DECLARE @condivisa BIT;
		SELECT @condivisa = Condivisa
		FROM dbo.ufnDiwassOperatori_get_SediBySessione_List(@IdSessione)
		WHERE Id = @Id;

		IF @condivisa IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF @condivisa = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il soggetto è condiviso da un''altra azienda: il collegamento a DIWASS lo gestisce l''azienda che lo ha creato';
			GOTO BRANCH_END;
		END

		DECLARE @idParent CHAR(16);
		DECLARE @aziendaNome VARCHAR(200);
		SELECT
			@idParent = s.IdParent,
			@aziendaNome = p.NomeCompleto
		FROM
			dbo.tblSedi s
			LEFT JOIN dbo.tblSedi p ON s.IdParent = p.Id
		WHERE s.Id = @Id;

		DECLARE @operatoreAttuale BIGINT = (SELECT OperatorInternalId
		FROM dbo.tblDiwassOperatori
		WHERE Id = @Id);
		DECLARE @nuovoCollegamento BIT = IIF(@operatoreAttuale IS NULL OR @operatoreAttuale <> @OperatorInternalId, 1, 0);

		-- Un nuovo collegamento solo verso un operatore con il ruolo WSR Operator nuovo o valido; l'aggiornamento dello
		-- stesso operatore invece registra anche uno stato non più valido (lo mostra l'elenco)
		IF @nuovoCollegamento = 1 AND (@Stato IS NULL OR @Stato NOT IN ('NEW', 'VALID'))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@Stato IS NULL,
				'L''operatore non ha il ruolo WSR Operator su DIWASS: non si può usare nelle spedizioni',
				'L''operatore ha il ruolo WSR Operator nello stato ' + @Stato + ' su DIWASS: non si può collegare');
			GOTO BRANCH_END;
		END

		IF @idParent IS NULL
		BEGIN
			-- Azienda: sede principale DIWASS, non un sito
			IF @LinkedOperatorInternalId IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Per l''azienda scegliere la sede principale registrata su DIWASS, non un sito';
				GOTO BRANCH_END;
			END

			-- Cambiando l'operatore dell'azienda i siti collegati alle sue sedi non sarebbero più coerenti
			IF @nuovoCollegamento = 1 AND @operatoreAttuale IS NOT NULL
				AND EXISTS (
					SELECT 1
					FROM
						dbo.tblSedi s
						INNER JOIN dbo.tblDiwassOperatori o ON s.Id = o.Id
					WHERE s.IdParent = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Scollegare prima le sedi dell''azienda collegate a DIWASS';
				GOTO BRANCH_END;
			END
		END
		ELSE
		BEGIN
			-- Sede di un'azienda: sito registrato su DIWASS sotto l'operatore dell'azienda
			DECLARE @operatoreAzienda BIGINT = (SELECT OperatorInternalId
			FROM dbo.tblDiwassOperatori
			WHERE Id = @idParent);

			IF @operatoreAzienda IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Collegare prima l''azienda ' + ISNULL(@aziendaNome, '') + ' a DIWASS';
				GOTO BRANCH_END;
			END
			IF @LinkedOperatorInternalId IS NULL OR @LinkedOperatorInternalId <> @operatoreAzienda
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Scegliere un sito registrato su DIWASS sotto la sede principale dell''azienda';
				GOTO BRANCH_END;
			END
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblDiwassOperatori
			SET
				OperatorInternalId = @OperatorInternalId,
				LinkedOperatorInternalId = @LinkedOperatorInternalId,
				Nome = @Nome,
				Indirizzo = @Indirizzo,
				Paese = @Paese,
				Identificativo = @Identificativo,
				Stato = @Stato,
				DataVerifica = GETDATE()
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
				INSERT INTO dbo.tblDiwassOperatori (Id, OperatorInternalId, LinkedOperatorInternalId, Nome, Indirizzo, Paese, Identificativo, Stato, DataVerifica)
				VALUES (@Id, @OperatorInternalId, @LinkedOperatorInternalId, @Nome, @Indirizzo, @Paese, @Identificativo, @Stato, GETDATE());
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
