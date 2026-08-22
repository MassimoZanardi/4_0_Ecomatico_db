CREATE PROCEDURE [dbo].[uspRifiutiAutorizzazioni_upd_Attivita]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Attivita VARCHAR(8000) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Attivita = NULLIF(LTRIM(RTRIM(@Attivita)), '');
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
			@IdFunzione = 'RAT',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sull'autorizzazione padre: senza questo controllo, chiunque avesse
		-- permesso RAT sul modulo (anche di un'altra azienda) poteva modificare le attività
		-- di un'autorizzazione non propria conoscendone l'Id.
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiAutorizzazioni a
			INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
			INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				a.Id = @Id
				AND e.Id = @IdSessione
				AND a.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''autorizzazione condivisa da altre aziende non può essere modificata';
			GOTO BRANCH_END;
		END

		-- @Attivita: lista di codici attività separati da ';' — es. 'R1;R2;D1'
		-- Se NULL o vuoto, tutte le attività vengono rimosse (nessuna selezionata).
		BEGIN TRANSACTION;

			DELETE dbo.tblRifiutiAutorizzazioniAttivita
			WHERE Id = @Id;

			IF @Attivita IS NOT NULL
				INSERT INTO dbo.tblRifiutiAutorizzazioniAttivita (Id, IdAttivita)
				SELECT
					@Id,
					a.Id
				FROM
					STRING_SPLIT(@Attivita, ';') s
					INNER JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento a ON s.value = a.Id
				WHERE s.value <> '';

		COMMIT TRANSACTION;

		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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
		THROW 50001, @returnMessage, 1
	END

END;
