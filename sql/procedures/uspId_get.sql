CREATE OR ALTER PROCEDURE [dbo].[uspId_get]
	@Conferma BIT = 0,
	@IdSessione CHAR(16) = NULL,
	@NoLog BIT = 0,
	@Id CHAR(16) = NULL OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Risolve @IdUtente una sola volta, prima del loop
		DECLARE @IdUtente CHAR(16);
		IF @NoLog = 0
		BEGIN
			SELECT @IdUtente = IdUtente
			FROM dbo.tblSessioni
			WHERE Id = @IdSessione;
		END

		DECLARE @Data DATETIME2(0) = GETDATE();
		DECLARE @tentativi INT = 0;

		WHILE @Id IS NULL AND @tentativi < 10
		BEGIN
			SET @tentativi += 1;
			BEGIN TRY

				-- Genera ID: rimuove TUTTI i trattini prima di troncare a 16 char
				SET @Id = LOWER(LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 16));

				-- Esclude il range riservato agli ID di sistema
				-- (0000000000000000 → 000000000000000F)
				IF @Id LIKE '000000000000000[0-9a-f]'
				BEGIN
					SET @Id = NULL;
					CONTINUE;
				END

				-- Tenta l'inserimento: fallisce se già esiste (collisione GUID troncato)
				INSERT INTO dbo.tblId (Id) VALUES (@Id);

				-- Inserisce il log solo se richiesto
				IF @NoLog = 0
				BEGIN
					INSERT INTO dbo.tblIdLog (Id, Operazione, [Data], IdUtente)
					VALUES (@Id, 'I', @Data, @IdUtente);

					IF @Conferma = 1
						INSERT INTO dbo.tblIdLog (Id, Operazione, [Data], IdUtente)
						VALUES (@Id, 'U', @Data, @IdUtente);
				END

			END TRY
			BEGIN CATCH
				-- 2627 = PRIMARY KEY violation
				-- 2601 = UNIQUE index violation
				-- Solo per duplicati: reimposta @Id e riprova il loop
				IF ERROR_NUMBER() IN (2627, 2601)
					SET @Id = NULL;
				ELSE
					THROW; -- qualsiasi altro errore: interrompe il loop e propaga
			END CATCH
		END

		-- Verifica che il loop sia uscito con un Id valido
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Impossibile generare un Id univoco dopo 10 tentativi';
			GOTO BRANCH_END;
		END

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;



