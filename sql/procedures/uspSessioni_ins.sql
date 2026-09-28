CREATE OR ALTER PROCEDURE [dbo].[uspSessioni_ins]
	@Id CHAR(16) = NULL,
	@IdUtente CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione parametri
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Risolve i valori di default FUORI dalla transazione:
		-- sono letture pure, non hanno motivo di prolungare i lock
		DECLARE @idAzienda CHAR(16);
		DECLARE @idSede CHAR(16);
		DECLARE @idCalendario CHAR(16);

		-- Imposta il valore solo se l'utente ha accesso a esattamente una azienda
		SELECT @idAzienda = CASE COUNT(*) WHEN 1 THEN MAX(Id) ELSE NULL END
		FROM dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente);

		-- Imposta il valore solo se l'utente ha accesso a esattamente una sede
		SELECT @idSede = CASE COUNT(*) WHEN 1 THEN MAX(Id) ELSE NULL END
		FROM dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente);

		-- Imposta il calendario solo se la sede è unica e ha un solo calendario
		IF @idSede IS NOT NULL
			SELECT @idCalendario = CASE COUNT(*) WHEN 1 THEN MAX(Id) ELSE NULL END
			FROM dbo.tblCalendari
			WHERE
				IdSede = @idSede
				AND Lock = 0;

		BEGIN TRANSACTION;

			-- Pulizia sessioni scadute (piggyback cleanup)
			SELECT Id
			INTO #tSessioni
			FROM dbo.tblSessioni
			WHERE [Data] < DATEADD(HOUR, -24, GETDATE());

			DELETE dbo.tblUrlNavigazione
			WHERE IdSessione IN (SELECT Id FROM #tSessioni);
			DELETE dbo.tblIdCancellati
			WHERE IdSessione IN (SELECT Id FROM #tSessioni);
			DELETE dbo.tblSessioniFunzioniPermessi
			WHERE Id IN (SELECT Id FROM #tSessioni);
			DELETE dbo.tblSessioni
			WHERE Id IN (SELECT Id FROM #tSessioni);

			-- Inserisce la nuova sessione
			INSERT INTO dbo.tblSessioni
				(Id, IdUtente, [Data], IdDominio, IdAzienda, IdSede, IdCalendario)
			SELECT
				@Id, @IdUtente, GETDATE(), IdDominio,
				@idAzienda, @idSede, @idCalendario
			FROM dbo.tblUtenti
			WHERE Id = @IdUtente;

		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW; -- propaga l'eccezione originale: C# la logga come SqlException inattesa
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
