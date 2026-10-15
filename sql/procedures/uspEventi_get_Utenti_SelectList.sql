CREATE OR ALTER PROCEDURE [dbo].[uspEventi_get_Utenti_SelectList]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'SRA',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Gli utenti del dominio li vede, e li assegna, solo un amministratore
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

		-- Titolarità: mancava la verifica che @Id (l'Evento) appartenesse a un
		-- calendario/sede accessibile dalla sessione — presente invece nei SP
		-- "fratelli" upd_Utente/upd_Proprieta. Stesso pattern applicato qui.
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblEventi e
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE e.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Evento non trovato';
			GOTO BRANCH_END;
		END

		DECLARE @idDominio CHAR(16);
		SELECT @idDominio = IdDominio
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Sessione non valida o scaduta';
			GOTO BRANCH_END;
		END

		SELECT
			Id = u.Id,
			[Text] = u.Email,
			Selected = CAST(IIF(e.IdUtente IS NULL, 0, 1) AS BIT)
		FROM
			dbo.tblUtenti u
			LEFT JOIN dbo.tblEventiUtenti e ON u.Id = e.IdUtente AND e.Id = @Id
		WHERE
			u.IdDominio = @idDominio
			AND u.[Master] = 0
			AND u.Lock = 0
		ORDER BY
			Selected DESC, [Text];

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
