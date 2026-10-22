SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Esito di un'operazione su DIWASS (@Operazione come uspDiwassAllegatiVii_get_Invio): I invio riuscito (numero DIWASS,
-- stato Annunciato, firma; ricorda codice internazionale per l'EER e ruolo di firma dell'utente), A aggiornamento
-- riuscito, N annullamento riuscito, S stato letto da DIWASS
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAllegatiVii_upd_Invio]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Operazione CHAR(1) = NULL,
	@Numero VARCHAR(50) = NULL,
	@Stato VARCHAR(20) = NULL,
	@FirmaNome VARCHAR(100) = NULL,
	@FirmaEmail VARCHAR(100) = NULL,
	@FirmaData DATETIME2(0) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Operazione = NULLIF(LTRIM(RTRIM(@Operazione)), '');
		SET @Numero = NULLIF(LTRIM(RTRIM(@Numero)), '');
		SET @Stato = NULLIF(LTRIM(RTRIM(@Stato)), '');

		IF @Id IS NULL OR @IdSessione IS NULL OR ISNULL(@Operazione, '') NOT IN ('I', 'A', 'N', 'S')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Parametri non validi';
			GOTO BRANCH_END;
		END
		IF (@Operazione = 'I' AND @Numero IS NULL) OR (@Operazione = 'S' AND @Stato IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Risposta di DIWASS senza numero o stato del documento';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF IIF(@Operazione = 'S', 1, 2) > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda del contesto
		DECLARE @idAzienda CHAR(16);
		DECLARE @idUtente CHAR(16);
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@idUtente = e.IdUtente
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND a.Lock = 0
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblDiwassAllegatiVii
			SET
				Numero = IIF(@Operazione = 'I', @Numero, Numero),
				Stato = CASE @Operazione WHEN 'I' THEN 'ANNOUNCED' WHEN 'N' THEN 'CANCELLED' WHEN 'S' THEN @Stato ELSE Stato END,
				DataInvio = IIF(@Operazione = 'I', GETDATE(), DataInvio),
				DataStato = GETDATE(),
				DaInviare = IIF(@Operazione IN ('I', 'A'), NULL, DaInviare),
				FirmaNome = IIF(@Operazione IN ('I', 'A'), @FirmaNome, FirmaNome),
				FirmaEmail = IIF(@Operazione IN ('I', 'A'), @FirmaEmail, FirmaEmail),
				FirmaData = IIF(@Operazione IN ('I', 'A'), @FirmaData, FirmaData)
			WHERE Id = @Id;

			IF @Operazione IN ('I', 'A')
			BEGIN
				-- Proposte per i prossimi Allegati VII: codice internazionale per l'EER e ruolo di firma dell'utente
				MERGE dbo.tblDiwassCodiciRifiutiUsati AS t
				USING (
					SELECT IdAziendaInterna, IdEer, ListaCodice, Codice
					FROM dbo.tblDiwassAllegatiVii
					WHERE
						Id = @Id
						AND IdEer IS NOT NULL
						AND Codice IS NOT NULL
				) AS s
				ON t.IdAziendaInterna = s.IdAziendaInterna AND t.IdEer = s.IdEer
				WHEN MATCHED THEN UPDATE
				SET
					Lista = s.ListaCodice,
					Codice = s.Codice,
					Data = GETDATE() WHEN NOT MATCHED THEN INSERT (IdAziendaInterna, IdEer, Lista, Codice, Data) VALUES (s.IdAziendaInterna, s.IdEer, s.ListaCodice, s.Codice, GETDATE());

				MERGE dbo.tblDiwassFirmeRuoli AS t
				USING (
					SELECT IdUtente = @idUtente, IdAziendaInterna, FirmaRuolo
					FROM dbo.tblDiwassAllegatiVii
					WHERE
						Id = @Id
						AND FirmaRuolo IS NOT NULL
				) AS s
				ON t.IdUtente = s.IdUtente AND t.IdAziendaInterna = s.IdAziendaInterna
				WHEN MATCHED THEN UPDATE
				SET Ruolo = s.FirmaRuolo WHEN NOT MATCHED THEN INSERT (IdUtente, IdAziendaInterna, Ruolo) VALUES (s.IdUtente, s.IdAziendaInterna, s.FirmaRuolo);
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
