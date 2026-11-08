SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione dalle versioni precedenti: Id 4.0 di un record di origine e sua corrispondenza in tblMigrazioniId.
-- SP interna delle migrazioni, eseguita dentro la loro transazione (non ne apre una propria).
-- - @Id NULL in ingresso: genera un Id nuovo con lo stesso formato di uspId_get e lo registra in tblId e in tblIdLog
--   (una sola riga Operazione 'I', senza utente, con la data di inserimento originale @DataInserimento se nota: e' la
--   data che leggono le viste, es. viewRentriRegistrazioniConservazione); corrispondenza con Creato = 1.
-- - @Id valorizzato: record 4.0 gia' esistente abbinato a quello di origine (es. azienda interna con lo stesso codice
--   fiscale); corrispondenza con Creato = 0, nessuna scrittura in tblId/tblIdLog.
-- Diversamente da uspId_get, la collisione si evita controllando tblId prima dell'inserimento e non intercettando la
-- violazione di chiave: con XACT_ABORT ON una violazione dentro la transazione la renderebbe non confermabile.
CREATE OR ALTER PROCEDURE dbo.uspMigrazioniId_ins
	@Versione CHAR(2) = NULL,
	@IdDominioA CHAR(16) = NULL,
	@Tabella VARCHAR(50) = NULL,
	@IdOrigine VARCHAR(50) = NULL,
	@IdMigrazione INT = NULL,
	@DataInserimento DATETIME2(0) = NULL,
	@Id CHAR(16) = NULL OUTPUT
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Versione = NULLIF(LTRIM(RTRIM(@Versione)), '');
		SET @IdDominioA = NULLIF(LTRIM(RTRIM(@IdDominioA)), '');
		SET @Tabella = NULLIF(LTRIM(RTRIM(@Tabella)), '');
		SET @IdOrigine = NULLIF(LTRIM(RTRIM(@IdOrigine)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @Versione IS NULL OR @IdDominioA IS NULL OR @Tabella IS NULL OR @IdOrigine IS NULL OR @IdMigrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Parametri della corrispondenza incompleti';
			GOTO BRANCH_END;
		END

		IF @@TRANCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'uspMigrazioniId_ins va eseguita dentro la transazione della migrazione';
			GOTO BRANCH_END;
		END

		IF EXISTS (SELECT 1
		FROM dbo.tblMigrazioniId
		WHERE
			Versione = @Versione
			AND IdDominioA = @IdDominioA
			AND Tabella = @Tabella
			AND IdOrigine = @IdOrigine
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = CONCAT('Record gia'' migrato: ', @Tabella, ' ', @IdOrigine);
			GOTO BRANCH_END;
		END

		DECLARE @creato BIT = IIF(@Id IS NULL, 1, 0);

		IF @creato = 1
		BEGIN
			DECLARE @tentativi INT = 0;

			WHILE @Id IS NULL AND @tentativi < 10
			BEGIN
				SET @tentativi += 1;
				SET @Id = LOWER(LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 16));

				-- Range riservato agli Id di sistema (come uspId_get) e collisioni
				IF @Id LIKE '000000000000000[0-9a-f]'
					OR EXISTS (SELECT 1
					FROM dbo.tblId WITH (UPDLOCK, HOLDLOCK)
					WHERE Id = @Id)
					SET @Id = NULL;
			END

			IF @Id IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Impossibile generare un Id univoco dopo 10 tentativi';
				GOTO BRANCH_END;
			END

			INSERT INTO dbo.tblId (Id)
			VALUES (@Id);

			INSERT INTO dbo.tblIdLog (Id, Operazione, [Data], IdUtente)
			VALUES (@Id, 'I', ISNULL(@DataInserimento, CONVERT(DATETIME2(0), GETDATE())), NULL);
		END

		INSERT INTO dbo.tblMigrazioniId (Versione, IdDominioA, Tabella, IdOrigine, IdDestinazione, Creato, IdMigrazione)
		VALUES (@Versione, @IdDominioA, @Tabella, @IdOrigine, @Id, @creato, @IdMigrazione);
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
