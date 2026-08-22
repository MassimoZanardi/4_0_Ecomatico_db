CREATE PROCEDURE [dbo].[uspScadenze_ins]
	@IdSessione CHAR(16) = NULL,
	@IdTipo CHAR(16) = NULL,
	@IdEvento CHAR(16) = NULL,
	@Data SMALLDATETIME = NULL,
	@OccorrenzaESuccessive BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametro obbligatorio
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controllo permesso sulla funzione (SCD = Gestione Scadenze)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SCD',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Legge il calendario: dalla sessione per nuove scadenze, dall'evento per ricorrenti
		DECLARE @idCalendario CHAR(16);
		IF @IdEvento IS NULL
			SELECT @idCalendario = s.IdCalendario
			FROM dbo.tblSessioni s
			INNER JOIN dbo.tblCalendari c ON s.IdCalendario = c.Id
											   AND c.IdModulo = 'SCD'
			WHERE s.Id = @IdSessione;
		ELSE
		BEGIN
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblEventi e
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
						   ON c.IdSede = i.Id
				WHERE e.Id = @IdEvento)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			SELECT @idCalendario = IdCalendario
			FROM dbo.tblEventi
			WHERE Id = @IdEvento;
		END

		IF @idCalendario IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il calendario';
			GOTO BRANCH_END;
		END

		-- Genera i nuovi Id FUORI dalla transazione:
		-- uspId_get gestisce la propria transazione internamente
		DECLARE @returnIdEvento CHAR(16) = NULL;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @returnIdEvento OUTPUT;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;

			IF @IdEvento IS NULL
			BEGIN
				-- Nuova scadenza da zero
				INSERT INTO dbo.tblEventi
					(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Lock)
				VALUES
					(@returnIdEvento, @idCalendario, 'D', 'S', @Data, 0, 0, 2);

				INSERT INTO dbo.tblScadenze (Id, IdEvento, IdTipo)
				VALUES (@returnId, @returnIdEvento, @IdTipo);
			END
			ELSE
			BEGIN
				-- Nuova occorrenza da evento ricorrente esistente: copia i dati
				INSERT INTO dbo.tblEventi
					(Id, IdCalendario, IdStato, IdTipo, [Data], InGiornata, AvvisoAnticipo, Email, Etichette, Lock)
				SELECT
					@returnIdEvento, @idCalendario, 'D', 'S', @Data,
					InGiornata, AvvisoAnticipo, Email, Etichette, 2
				FROM dbo.tblEventi
				WHERE Id = @IdEvento;

				-- Copia le etichette dell'evento originale
				INSERT INTO dbo.tblEventiEtichette (Id, IdEtichetta)
				SELECT @returnIdEvento, IdEtichetta
				FROM dbo.tblEventiEtichette
				WHERE Id = @IdEvento;

				IF @OccorrenzaESuccessive = 1
				BEGIN
					-- Copia la ricorrenza dell'evento originale
					INSERT INTO dbo.tblRicorrenze
						(Id, IdParent, IdIntervallo, Frequenza, DataFine, Ripetizioni, Relativo)
					SELECT
						@returnIdEvento, @IdEvento,
						IdIntervallo, Frequenza, DataFine, Ripetizioni, Relativo
					FROM dbo.tblRicorrenze
					WHERE Id = @IdEvento;
				END
				ELSE
				BEGIN
					-- Aggiunge un'eccezione per questa singola occorrenza
					DELETE dbo.tblRicorrenzeEccezioni
					WHERE
						Id = @IdEvento
						AND [Data] = @Data;

					INSERT INTO dbo.tblRicorrenzeEccezioni (Id, [Data], IdEvento, Lock)
					VALUES (@IdEvento, @Data, @returnIdEvento, 2);
				END

				-- Copia la scadenza originale
				INSERT INTO dbo.tblScadenze (Id, IdEvento, IdTipo, Descrizione)
				SELECT @returnId, @returnIdEvento, IdTipo, Descrizione
				FROM dbo.tblScadenze
				WHERE IdEvento = @IdEvento;

				-- Copia gli Osepe associati alla scadenza originale
				INSERT INTO dbo.tblScadenzeOsepe (Id, IdOsepe)
				SELECT @returnId, o.IdOsepe
				FROM dbo.tblScadenze s
				INNER JOIN dbo.tblScadenzeOsepe o ON s.Id = o.Id
				WHERE s.IdEvento = @IdEvento;
			END

		COMMIT TRANSACTION;

		SELECT @returnId AS Id;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
