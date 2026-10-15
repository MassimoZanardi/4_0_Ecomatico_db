CREATE OR ALTER PROCEDURE [dbo].[uspEventi_upd_Utente]
	@Id CHAR(16) = NULL,
	@IdUtente CHAR(16) = NULL,
	@Reset BIT = 0,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- Senza utente, con @Reset = 1, si tolgono tutte le assegnazioni dell'evento (nessun utente spuntato)
		IF @IdUtente IS NULL AND ISNULL(@Reset, 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Gli utenti li assegna solo un amministratore, l'unico che vede gli utenti del dominio
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSessioni s
			INNER JOIN dbo.tblUtenti u ON s.IdUtente = u.Id
			WHERE
				s.Id = @IdSessione
				AND u.IdRuolo = 'AD'
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Togliere tutte le assegnazioni: basta che l'evento sia di un calendario accessibile
		IF @IdUtente IS NULL
		BEGIN
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblEventi e
				INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
				WHERE e.Id = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Evento o utente non validi';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				DELETE dbo.tblEventiUtenti
				WHERE Id = @Id;
			COMMIT TRANSACTION;

			SELECT @returnValue AS ReturnValue;
			GOTO BRANCH_END;
		END

		-- Verifica che l'evento appartenga a un calendario/sede accessibile dalla sessione
		-- e che l'utente da associare appartenga allo stesso dominio della sede
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblEventi e
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSediInterne si ON c.IdSede = si.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			INNER JOIN dbo.tblUtenti u ON u.IdDominio = si.IdDominio
			WHERE
				e.Id = @Id
				AND u.Id = @IdUtente
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Evento o utente non validi';
			GOTO BRANCH_END;
		END

		IF EXISTS (
			SELECT 1
			FROM dbo.tblEventi e
			LEFT JOIN dbo.tblRicorrenze r ON e.Id = r.Id
			LEFT JOIN dbo.tblRicorrenzeEccezioni z ON e.Id = z.IdEvento AND z.Lock = 0
			WHERE
				e.Id = @Id
				AND r.Id IS NOT NULL
				AND z.IdEvento IS NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Gli utenti possono essere associati solo ad eventi non ricorrenti o ad occorrenze modificate';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			IF @Reset = 1
				DELETE dbo.tblEventiUtenti
				WHERE Id = @Id;
			ELSE
				DELETE dbo.tblEventiUtenti
				WHERE
					Id = @Id
					AND IdUtente = @IdUtente;

			INSERT INTO dbo.tblEventiUtenti (Id, IdUtente)
			VALUES (@Id, @IdUtente);
		COMMIT TRANSACTION;

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
