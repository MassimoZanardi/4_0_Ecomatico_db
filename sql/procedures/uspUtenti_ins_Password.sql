CREATE PROCEDURE [dbo].[uspUtenti_ins_Password]
	@Id CHAR(16) = NULL,
	@Email NVARCHAR(255) = NULL,
	@Password NVARCHAR(200) = NULL,
	@Temporanea BIT = 1,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Validazione: almeno uno tra @Id e @Email deve essere valorizzato
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Email = NULLIF(LTRIM(RTRIM(@Email)), '');
		SET @Password = NULLIF(LTRIM(RTRIM(@Password)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL AND @Email IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Specificare @Id oppure @Email';
			GOTO BRANCH_END;
		END

		IF @Password IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Password non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controllo permesso sulla funzione (UTE = Gestione Utenti)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'UTE',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Risolve @IdUtente da @Id oppure da @Email (forgot password)
		DECLARE @IdUtente CHAR(16);

		IF @Id IS NOT NULL
			SET @IdUtente = @Id;
		ELSE
			SELECT @IdUtente = Id
			FROM dbo.tblUtenti
			WHERE Email = @Email COLLATE Latin1_General_CI_AS;

		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Utente non trovato';
			GOTO BRANCH_END;
		END

		DECLARE @idDominioSessione CHAR(16);
		SELECT @idDominioSessione = a.IdDominio
		FROM dbo.tblSessioni s INNER JOIN dbo.tblUtenti a ON a.Id = s.IdUtente
		WHERE s.Id = @IdSessione;

		-- Titolarità: Admin dello stesso Dominio dell'utente target, oppure Admin di un Dominio Master.
		-- Aggiunto perché @Id arriva da un campo hidden del form (Utenti/Edit): un valore hidden è
		-- testo semplice manipolabile lato client, quindi va sempre validato lato server.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblUtenti
		WHERE
			Id = @IdUtente
			AND IdDominio = @idDominioSessione
		)
		AND NOT EXISTS (SELECT 1
		FROM dbo.tblDomini
		WHERE
			Id = @idDominioSessione
			AND [Master] = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Determina se è la prima password dell'utente
		-- 0 = aveva già password → C# SendEmailForPasswordChange
		-- 1 = prima password     → C# SendEmailForStart
		DECLARE @GiaEsiste BIT = CASE
			WHEN EXISTS (
				SELECT 1
				FROM dbo.tblUtentiPassword
				WHERE Id = @IdUtente)
			THEN 1 ELSE 0
		END;

		BEGIN TRANSACTION;

			-- Aggiunge la nuova password in cima allo storico
			INSERT INTO dbo.tblUtentiPassword (Id, [Password], [Data], Temporanea)
			VALUES (@IdUtente, @Password, GETDATE(), @Temporanea);

			-- Mantiene solo le ultime 5 password per utente:
			-- elimina tutte le righe oltre la quinta più recente
			DELETE dbo.tblUtentiPassword
			WHERE
				Id = @IdUtente
				AND [Data] NOT IN ( SELECT TOP 5 [Data] FROM dbo.tblUtentiPassword WHERE Id = @IdUtente ORDER BY [Data] DESC );

		COMMIT TRANSACTION;

		SET @returnValue = CASE @GiaEsiste
			WHEN 1 THEN 0 -- aveva già password → SendEmailForPasswordChange
			WHEN 0 THEN 1 -- prima password     → SendEmailForStart
		END;

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
