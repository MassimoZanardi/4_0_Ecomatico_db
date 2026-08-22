CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiAutorizzazioni_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@Numero VARCHAR(50) = NULL,
	@IsNumero BIT = 1,
	@IdTipo CHAR(1) = NULL,
	@IdNumeroTipo CHAR(1) = NULL,
	@Identificativo VARCHAR(50) = NULL,
	@Note VARCHAR(500) = NULL,
	@DataInizio DATE = NULL,
	@DataFine DATE = NULL,
	@Disabilitata BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdTipo = NULLIF(LTRIM(RTRIM(@IdTipo)), '');
		SET @IdNumeroTipo = NULLIF(LTRIM(RTRIM(@IdNumeroTipo)), '');

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
		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataInizio IS NOT NULL AND @DataFine IS NOT NULL AND @DataInizio > @DataFine
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di inizio non può essere successiva alla data di fine';
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

		-- Titolarità sull'autorizzazione stessa: prima non esisteva alcun controllo che
		-- @Id appartenesse all'azienda della sessione — solo la nuova @IdSede (se esterna)
		-- e il blocco cambio-sede su autorizzazioni con movimenti erano verificati, ma
		-- un'autorizzazione di un'altra azienda senza movimenti attivi, passando la stessa
		-- @IdSede già presente, poteva essere modificata o riassegnata da chiunque.
		-- Nessun filtro su Lock qui: un'autorizzazione già cancellata (Lock=4) del
		-- proprietario legittimo deve fallire più avanti con il messaggio corretto
		-- ("non trovata o già eliminata") dal controllo @@ROWCOUNT sull'UPDATE, non qui.
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiAutorizzazioni a
			INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
			INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				a.Id = @Id
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''autorizzazione condivisa da altre aziende non può essere modificata';
			GOTO BRANCH_END;
		END

		-- Sede esterna condivisa da altre aziende: solo il proprietario può modificare
		IF EXISTS (SELECT 1
		FROM dbo.tblSedi
		WHERE
			InternaEsterna = 'E'
			AND Id = @IdSede
		)
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblSedi
			WHERE
				Id = @IdSede
				AND Lock = 0
			)
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi s
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
				WHERE
					s.Id = @IdSede
					AND e.Id = @IdSessione
					AND s.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''autorizzazione condivisa da altre sedi non può essere modificata';
				GOTO BRANCH_END;
			END
		END

		-- Non è possibile cambiare sede ad un'autorizzazione già associata a movimenti attivi
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiAutorizzazioni a
			WHERE
				a.Id = @Id
				AND a.Lock = 0
				AND a.IdSede <> @IdSede
				AND EXISTS ( SELECT 1 FROM dbo.tblRifiutiMovimenti m LEFT JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp1 ON m.Id = mp1.Id AND mp1.Pos = 0 LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0 LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0 LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi1 ON m.Id = mi1.Id AND mi1.Pos = 0 WHERE (r.Lock < 2 OR f.Lock < 2) AND ( mp1.IdAutorizzazione = a.Id OR md.IdAutorizzazione = a.Id OR mt1.IdAutorizzazione = a.Id OR mi1.IdAutorizzazione = a.Id) )
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare la sede ad un''autorizzazione già associata ad uno o più movimenti';
			GOTO BRANCH_END;
		END

		-- Normalizzazione parametri
		IF @IsNumero = 1
			SET @Numero = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Numero, 0, 1));
		ELSE
		BEGIN
			SET @Numero = NULL;
			SET @IdNumeroTipo = NULL;
		END

		IF @IdTipo = '0' OR @IdNumeroTipo = 'A' OR EXISTS (SELECT 1
		FROM dbo.tblRifiutiAutorizzazioni
		WHERE
			Id = @Id
			AND IdRuolo IN('T', 'I')
		)
			SET @IdTipo = NULL;

		SET @Identificativo = dbo.ufnStringhe_get_SenzaSpazi(@Identificativo, 0, 1);
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);

		BEGIN TRANSACTION;
			UPDATE dbo.tblRifiutiAutorizzazioni
			SET
				Lock = 0,
				IdSede = @IdSede,
				IdTipo = @IdTipo,
				IdNumeroTipo = @IdNumeroTipo,
				Numero = @Numero,
				Identificativo = @Identificativo,
				Note = @Note,
				DataInizio = @DataInizio,
				DataFine = @DataFine,
				Disabilitata = @Disabilitata
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Autorizzazione non trovata o già eliminata';
				GOTO BRANCH_END;
			END
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
		THROW 50001, @returnMessage, 1;
	END

END;
