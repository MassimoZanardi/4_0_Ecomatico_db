CREATE OR ALTER PROCEDURE [dbo].[uspSessione_get_FunzionePermesso]
	@Id CHAR(16),
	@IdFunzione CHAR(3),
	@Permesso INT = NULL OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY

		-- Validazione: se i parametri sono NULL non ha senso interrogare la cache
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdFunzione = NULLIF(LTRIM(RTRIM(@IdFunzione)), '');

		IF @Id IS NULL OR @IdFunzione IS NULL
		BEGIN
			SET @Permesso = 0; -- fail-safe: nessun permesso se parametri non validi
			RETURN;
		END

		-- Cerca il permesso in cache
		SELECT @Permesso = IdPermesso
		FROM dbo.tblSessioniFunzioniPermessi
		WHERE
			Id = @Id
			AND IdFunzione = @IdFunzione;

		-- Cache miss: calcola il permesso e salvalo
		IF @Permesso IS NULL
		BEGIN
			-- Calcola il permesso tramite la funzione (operazione costosa)
			SET @Permesso = dbo.ufnFunzioni_get_PermessoBySessione(@IdFunzione, @Id);

			-- Salva in cache: ignora i duplicati (race condition tra thread concorrenti)
			INSERT INTO dbo.tblSessioniFunzioniPermessi (Id, IdFunzione, IdPermesso)
			SELECT @Id, @IdFunzione, @Permesso
			WHERE NOT EXISTS ( SELECT 1 FROM dbo.tblSessioniFunzioniPermessi WITH (UPDLOCK) WHERE Id = @Id AND IdFunzione = @IdFunzione );
		END

	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() IN (2627, 2601)
		BEGIN
			-- Duplicato: un thread concorrente ha già inserito la cache
			-- Rileggi il valore corretto invece di restituire 0
			SELECT @Permesso = IdPermesso
			FROM dbo.tblSessioniFunzioniPermessi
			WHERE
				Id = @Id
				AND IdFunzione = @IdFunzione;
		END
		ELSE
		BEGIN
			-- Errore reale → fail-safe: nega l'accesso
			-- Non propagare: questa SP è chiamata da ogni controllo permessi,
			-- un THROW qui farebbe saltare tutta la catena chiamante
			SET @Permesso = 0;
		END
	END CATCH

END;
