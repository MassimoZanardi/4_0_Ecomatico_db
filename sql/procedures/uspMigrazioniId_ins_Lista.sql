SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Migrazione dalle versioni precedenti: Id 4.0 nuovi in blocco, versione set-based di uspMigrazioniId_ins per le
-- tabelle con molti record (movimenti, registrazioni). SP interna delle migrazioni, eseguita dentro la loro
-- transazione (non ne apre una propria).
-- Il chiamante riempie la tabella temporanea #nuoviId (Tabella, IdOrigine, DataInserimento) con i record di origine
-- non ancora migrati; la SP valorizza #nuoviId.Id con un Id nuovo per ogni riga, nello stesso formato di uspId_get, e
-- lo registra in tblId, in tblIdLog (una riga Operazione 'I' senza utente, con la data di inserimento originale se
-- nota) e in tblMigrazioniId (Creato = 1). Le collisioni (con tblId o tra le righe stesse) si risolvono rigenerando
-- solo gli Id in conflitto, prima di qualunque inserimento.
CREATE OR ALTER PROCEDURE dbo.uspMigrazioniId_ins_Lista
	@Versione CHAR(2) = NULL,
	@IdDominioA CHAR(16) = NULL,
	@IdMigrazione INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		IF @Versione IS NULL OR @IdDominioA IS NULL OR @IdMigrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Parametri della corrispondenza incompleti';
			GOTO BRANCH_END;
		END

		IF @@TRANCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'uspMigrazioniId_ins_Lista va eseguita dentro la transazione della migrazione';
			GOTO BRANCH_END;
		END

		IF EXISTS (SELECT 1
		FROM
			#nuoviId n
			INNER JOIN dbo.tblMigrazioniId mi ON mi.Versione = @Versione
				AND mi.IdDominioA = @IdDominioA
				AND mi.Tabella = n.Tabella
				AND mi.IdOrigine = n.IdOrigine)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Uno o piu'' record risultano gia'' migrati';
			GOTO BRANCH_END;
		END

		UPDATE #nuoviId
		SET Id = LOWER(LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 16));

		DECLARE @tentativi INT = 0;

		WHILE @tentativi < 10
		BEGIN
			-- Range riservato agli Id di sistema (come uspId_get), Id gia' esistenti e duplicati nel blocco
			;WITH conflitti AS (
				SELECT
					n.Id,
					Doppio = ROW_NUMBER() OVER (PARTITION BY n.Id ORDER BY n.Tabella, n.IdOrigine)
				FROM #nuoviId n
			)
			UPDATE n
			SET Id = LOWER(LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 16))
			FROM
				#nuoviId n
				INNER JOIN (
					SELECT n2.Tabella, n2.IdOrigine
					FROM
						#nuoviId n2
						INNER JOIN conflitti c ON n2.Id = c.Id
					WHERE
						c.Doppio > 1
						OR n2.Id LIKE '000000000000000[0-9a-f]'
						OR EXISTS (SELECT 1 FROM dbo.tblId t WITH (UPDLOCK, HOLDLOCK) WHERE t.Id = n2.Id)
				) x ON n.Tabella = x.Tabella AND n.IdOrigine = x.IdOrigine;

			IF @@ROWCOUNT = 0
				BREAK;

			SET @tentativi += 1;
		END

		IF @tentativi >= 10
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Impossibile generare Id univoci dopo 10 tentativi';
			GOTO BRANCH_END;
		END

		INSERT INTO dbo.tblId (Id)
		SELECT Id
		FROM #nuoviId;

		INSERT INTO dbo.tblIdLog (Id, Operazione, [Data], IdUtente)
		SELECT Id, 'I', ISNULL(DataInserimento, CONVERT(DATETIME2(0), GETDATE())), NULL
		FROM #nuoviId;

		INSERT INTO dbo.tblMigrazioniId (Versione, IdDominioA, Tabella, IdOrigine, IdDestinazione, Creato, IdMigrazione)
		SELECT @Versione, @IdDominioA, Tabella, IdOrigine, Id, 1, @IdMigrazione
		FROM #nuoviId;
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
