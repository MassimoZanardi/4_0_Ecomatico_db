CREATE PROCEDURE [dbo].[uspEtichette_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;

	DECLARE @returnValue INT = 0;
	DECLARE @returnMessage NVARCHAR(200) = NULL;
	DECLARE @permesso TINYINT;
	DECLARE @lock INT;
	DECLARE @idModulo CHAR(3);

	BEGIN TRY

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

		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ETC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: verifica prima di tutto se l'etichetta esiste, indipendentemente dalla
		-- titolarità sottostante — mai esistita o già cancellata (es. doppio invio della
		-- richiesta di annullamento lato UI) viene trattata come cancellazione già avvenuta con
		-- successo, non come errore.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEtichette
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Verifica che l'etichetta appartenga a una sede accessibile dalla sessione
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblEtichette e
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON e.IdSede = i.Id
			WHERE e.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT @lock = Lock,
			   @idModulo = IdModulo
		FROM dbo.tblEtichette
		WHERE Id = @Id;

		-- Controllo permesso sul modulo: allineato a get/get_List/ins, prima assente qui
		IF dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @lock = 0
		BEGIN
			BEGIN TRANSACTION;

				UPDATE dbo.tblEtichette
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'L''etichetta è già in uno stato non modificabile (modificata da altro processo)';
					GOTO BRANCH_END;
				END

				IF @idModulo IN ('SRV', 'SCD')
				BEGIN
					UPDATE e
					SET Etichette = ( SELECT et.Nome, Colore = IIF(et.Visualizzazione = 'C', c.Hex, c.Css), et.Descrizione, et.Visualizzazione FROM dbo.tblEventiEtichette x INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id INNER JOIN dbo.tblColori c ON et.IdColore = c.Id WHERE x.Id = e.Id AND et.Lock = 0 ORDER BY et.Nome FOR JSON PATH )
					FROM dbo.tblEventi e
					INNER JOIN dbo.tblEventiEtichette t ON e.Id = t.Id
					WHERE t.IdEtichetta = @Id;
				END
				ELSE IF @idModulo = 'RIF'
				BEGIN
					UPDATE e
					SET Etichette = ( SELECT et.Nome, Colore = IIF(et.Visualizzazione = 'C', c.Hex, c.Css), et.Descrizione, et.Visualizzazione FROM dbo.tblRifiutiRegistrazioniEtichette x INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id INNER JOIN dbo.tblColori c ON et.IdColore = c.Id WHERE x.Id = e.Id AND et.Lock = 0 ORDER BY et.Nome FOR JSON PATH )
					FROM dbo.tblRifiutiRegistrazioni e
					INNER JOIN dbo.tblRifiutiRegistrazioniEtichette t ON e.Id = t.Id
					WHERE t.IdEtichetta = @Id;

					UPDATE e
					SET Etichette = ( SELECT et.Nome, Colore = IIF(et.Visualizzazione = 'C', c.Hex, c.Css), et.Descrizione, et.Visualizzazione FROM dbo.tblRifiutiFormulariEtichette x INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id INNER JOIN dbo.tblColori c ON et.IdColore = c.Id WHERE x.Id = e.Id AND et.Lock = 0 ORDER BY et.Nome FOR JSON PATH )
					FROM dbo.tblRifiutiFormulari e
					INNER JOIN dbo.tblRifiutiFormulariEtichette t ON e.Id = t.Id
					WHERE t.IdEtichetta = @Id;

					UPDATE e
					SET Etichette = ( SELECT et.Nome, Colore = IIF(et.Visualizzazione = 'C', c.Hex, c.Css), et.Descrizione, et.Visualizzazione FROM dbo.tblRifiutiModelliEtichette x INNER JOIN dbo.tblEtichette et ON x.IdEtichetta = et.Id INNER JOIN dbo.tblColori c ON et.IdColore = c.Id WHERE x.Id = e.Id AND et.Lock = 0 ORDER BY et.Nome FOR JSON PATH )
					FROM dbo.tblRifiutiModelli e
					INNER JOIN dbo.tblRifiutiModelliEtichette t ON e.Id = t.Id
					WHERE t.IdEtichetta = @Id;
				END

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());

			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblEtichette
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''etichetta è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

		END

		SELECT @returnValue AS ReturnValue;

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

