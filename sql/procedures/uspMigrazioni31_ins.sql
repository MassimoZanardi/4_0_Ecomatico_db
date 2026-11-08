SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione da Ecomatico 3.1 verso la 4.0 (tool da eseguire dal DBA, non chiamato dall'app). La 3.1 si legge solo
-- attraverso i sinonimi syn31* (tools/migrazione31_configurazione.sql) e non viene mai modificata.
-- 1) Perimetro e anomalie con uspMigrazioni31_get_Perimetro, la stessa SP di uspMigrazioni31_get_Verifica: con anche
--    una sola anomalia di livello E la migrazione non scrive nulla (esito E, anomalie nel log).
-- 2) Un'unica transazione, con un blocco esclusivo per dominio di destinazione (due migrazioni verso lo stesso dominio
--    non possono sovrapporsi), che esegue i passi:
--    - fase 3: aziende interne, sedi dei registri, registri (uspMigrazioni31_ins_Aziende);
--    - fase 4: sedi interne usate, soggetti e loro sedi, autorizzazioni (uspMigrazioni31_ins_Soggetti);
--    - fase 5: movimenti e registrazioni (uspMigrazioni31_ins_Registrazioni);
--    - fase 6: relazioni carico/scarico (uspMigrazioni31_ins_Relazioni) e rettifiche (uspMigrazioni31_ins_Rettifiche).
-- 3) @Simulazione = 1 (predefinito): tutto viene eseguito e poi annullato; esito A. @Simulazione = 0: conferma; esito S.
-- Idempotenza: ogni record scritto o abbinato e' registrato in tblMigrazioniId e non viene mai reinserito; una
-- seconda esecuzione importa solo cio' che manca.
-- Log: i passi scrivono nella tabella temporanea #log; prima del ROLLBACK (simulazione o errore) il log viene copiato in
-- una variabile tabella, che sopravvive al ROLLBACK, e poi salvato in tblMigrazioniLog. Per questo, in deroga al pattern
-- standard (CATCH con solo THROW), il CATCH annulla esplicitamente la transazione, salva log ed esito e poi rilancia
-- l'errore.
-- Restituisce due result set: riepilogo per fase e tabella, log completo dell'esecuzione.
CREATE OR ALTER PROCEDURE dbo.uspMigrazioni31_ins
	@IdDominioDa VARCHAR(50) = NULL,
	@IdSedeInternaDa VARCHAR(50) = NULL,
	@IdDominioA CHAR(16) = NULL,
	@Simulazione BIT = 1
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	DECLARE @returnValue INT = 0;
	DECLARE @returnMessage NVARCHAR(2000) = NULL;
	DECLARE @idMigrazione INT;
	DECLARE @log TABLE (
		Id INT IDENTITY(1, 1) NOT NULL,
		[Data] DATETIME2(3) NOT NULL,
		Fase VARCHAR(50) NOT NULL,
		Livello CHAR(1) NOT NULL,
		Tabella VARCHAR(50) NULL,
		IdOrigine VARCHAR(50) NULL,
		Righe INT NULL,
		Messaggio NVARCHAR(1000) NULL
	);

	BEGIN TRY
		SET @IdDominioDa = NULLIF(LTRIM(RTRIM(@IdDominioDa)), '');
		SET @IdSedeInternaDa = NULLIF(LTRIM(RTRIM(@IdSedeInternaDa)), '');
		SET @IdDominioA = NULLIF(LTRIM(RTRIM(@IdDominioA)), '');
		SET @Simulazione = ISNULL(@Simulazione, 1);

		IF @@TRANCOUNT > 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La migrazione gestisce la propria transazione: eseguirla fuori da una transazione aperta';
			GOTO BRANCH_END;
		END

		CREATE TABLE #aziende (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY
		);

		CREATE TABLE #registri (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IdSede CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAzienda CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdTipo CHAR(3) COLLATE DATABASE_DEFAULT NULL
		);

		CREATE TABLE #registrazioni (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IdMovimento UNIQUEIDENTIFIER NULL,
			IdRegistro CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdCausale CHAR(3) COLLATE DATABASE_DEFAULT NULL,
			Operazione31 CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			[Data] DATE NULL,
			Numero INT NULL,
			Lock TINYINT NULL,
			Inviata BIT NOT NULL,
			Importabile BIT NOT NULL,
			Gruppo CHAR(1) COLLATE DATABASE_DEFAULT NULL
		);

		CREATE TABLE #abbinamenti (
			IdAzienda31 CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			Mappata BIT NOT NULL,
			Abbinamenti INT NOT NULL,
			IdAzienda40 CHAR(16) COLLATE DATABASE_DEFAULT NULL
		);

		CREATE TABLE #autorizzazioni (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY
		);

		CREATE TABLE #sedi (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			Radice31 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			InternaEsterna CHAR(1) COLLATE DATABASE_DEFAULT NULL
		);

		CREATE TABLE #soggetti (
			IdSoggetto31 CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IdProprietario31 CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			ProprietarioCambiato BIT NOT NULL,
			Mappato BIT NOT NULL,
			Abbinamenti INT NOT NULL,
			IdSoggetto40 CHAR(16) COLLATE DATABASE_DEFAULT NULL
		);

		CREATE TABLE #anomalie (
			Livello CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL,
			Controllo VARCHAR(100) COLLATE DATABASE_DEFAULT NOT NULL,
			Tabella VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			IdOrigine VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			Dettaglio NVARCHAR(500) COLLATE DATABASE_DEFAULT NULL
		);

		CREATE TABLE #log (
			Id INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
			[Data] DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
			Fase VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
			Livello CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL,
			Tabella VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			IdOrigine VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			Righe INT NULL,
			Messaggio NVARCHAR(1000) COLLATE DATABASE_DEFAULT NULL
		);

		-- 1) Perimetro e anomalie (valida anche i parametri)
		EXEC dbo.uspMigrazioni31_get_Perimetro
			@IdDominioDa = @IdDominioDa,
			@IdSedeInternaDa = @IdSedeInternaDa,
			@IdDominioA = @IdDominioA;

		INSERT INTO dbo.tblMigrazioni (Versione, IdDominioDa, IdSedeInternaDa, IdDominioA, Simulazione, DataInizio)
		VALUES ('31', @IdDominioDa, @IdSedeInternaDa, @IdDominioA, @Simulazione, GETDATE());

		SET @idMigrazione = SCOPE_IDENTITY();

		INSERT INTO @log ([Data], Fase, Livello, Tabella, IdOrigine, Messaggio)
		SELECT SYSDATETIME(), 'Verifica', Livello, Tabella, IdOrigine, CONCAT(Controllo, ISNULL(': ' + Dettaglio, ''))
		FROM #anomalie
		ORDER BY
			CASE Livello
				WHEN 'E' THEN 1
				WHEN 'W' THEN 2
				ELSE 3
			END;

		IF EXISTS (SELECT 1
		FROM #anomalie
		WHERE Livello = 'E')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = CONCAT('Verifica non superata: ', (SELECT COUNT(*)
			FROM #anomalie
			WHERE Livello = 'E'), ' errori (migrazione ', @idMigrazione, ', vedere il log)');
		END
		ELSE
		BEGIN
			-- 2) Scrittura, in un'unica transazione
			BEGIN TRY
				BEGIN TRANSACTION;

				DECLARE @blocco INT;
				DECLARE @risorsa NVARCHAR(255) = N'Migrazione_' + @IdDominioA;

				EXEC @blocco = sys.sp_getapplock
					@Resource = @risorsa,
					@LockMode = 'Exclusive',
					@LockOwner = 'Transaction',
					@LockTimeout = 0;

				IF @blocco < 0
					THROW 50001, 'Un''altra migrazione verso lo stesso dominio e'' in corso', 1;

				EXEC dbo.uspMigrazioni31_ins_Aziende
					@IdMigrazione = @idMigrazione,
					@IdDominioA = @IdDominioA;

				EXEC dbo.uspMigrazioni31_ins_Soggetti
					@IdMigrazione = @idMigrazione,
					@IdDominioA = @IdDominioA;

				EXEC dbo.uspMigrazioni31_ins_Registrazioni
					@IdMigrazione = @idMigrazione,
					@IdDominioA = @IdDominioA;

				EXEC dbo.uspMigrazioni31_ins_Relazioni
					@IdMigrazione = @idMigrazione,
					@IdDominioA = @IdDominioA;

				EXEC dbo.uspMigrazioni31_ins_Rettifiche
					@IdMigrazione = @idMigrazione,
					@IdDominioA = @IdDominioA;

				INSERT INTO @log ([Data], Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				SELECT [Data], Fase, Livello, Tabella, IdOrigine, Righe, Messaggio
				FROM #log
				ORDER BY Id;

				IF @Simulazione = 1
					ROLLBACK TRANSACTION;
				ELSE
					COMMIT TRANSACTION;
			END TRY
			BEGIN CATCH
				-- Il log dei passi va copiato prima del ROLLBACK (la lettura e' ammessa anche a transazione non
				-- confermabile); la variabile tabella non e' toccata dal ROLLBACK
				INSERT INTO @log ([Data], Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
				SELECT [Data], Fase, Livello, Tabella, IdOrigine, Righe, Messaggio
				FROM #log
				ORDER BY Id;

				IF XACT_STATE() <> 0
					ROLLBACK TRANSACTION;

				SET @returnValue = -1;
				SET @returnMessage = CONCAT('Migrazione ', @idMigrazione, ' annullata per errore: ', ERROR_MESSAGE(), ' (', ISNULL(ERROR_PROCEDURE(), 'batch'), ', riga ', ERROR_LINE(), ')');

				INSERT INTO @log ([Data], Fase, Livello, Messaggio)
				VALUES (SYSDATETIME(), 'Errore', 'E', LEFT(@returnMessage, 1000));
			END CATCH
		END

		-- 3) Log ed esito, fuori dalla transazione
		INSERT INTO dbo.tblMigrazioniLog (IdMigrazione, [Data], Fase, Livello, Tabella, IdOrigine, Righe, Messaggio)
		SELECT @idMigrazione, [Data], Fase, Livello, Tabella, IdOrigine, Righe, Messaggio
		FROM @log
		ORDER BY Id;

		UPDATE dbo.tblMigrazioni
		SET
			DataFine = GETDATE(),
			Esito = CASE WHEN @returnValue < 0 THEN 'E' WHEN @Simulazione = 1 THEN 'A' ELSE 'S' END,
			Messaggio = CASE WHEN @returnValue < 0 THEN @returnMessage WHEN @Simulazione = 1 THEN 'Simulazione completata: nessuna modifica confermata' ELSE 'Migrazione completata' END
		WHERE Id = @idMigrazione;

		SELECT
			IdMigrazione = @idMigrazione,
			Fase,
			Tabella,
			Creati = SUM(IIF(Livello = 'I' AND Righe > 0, Righe, 0)),
			Abbinati = SUM(IIF(Livello = 'I' AND Righe = 0, 1, 0)),
			Avvisi = SUM(IIF(Livello = 'W', 1, 0)),
			Errori = SUM(IIF(Livello = 'E', 1, 0))
		FROM @log
		GROUP BY Fase, Tabella
		ORDER BY MIN(Id);

		SELECT Id, [Data], Fase, Livello, Tabella, IdOrigine, Righe, Messaggio
		FROM @log
		ORDER BY Id;
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
