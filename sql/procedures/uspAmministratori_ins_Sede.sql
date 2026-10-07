SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAmministratori_ins_Sede
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@DataInizio DATE = NULL,
	@DataFine DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(NULLIF(LTRIM(RTRIM(@IdSede)), ''), REPLICATE('0', 16));

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

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @idSedeAmministratore CHAR(16);
		DECLARE @lock INT;
		SELECT
			@idAzienda = c.IdAziendaInterna,
			@idSedeAmministratore = c.IdSede,
			@lock = c.Lock
		FROM
			dbo.tblAmministratori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANM',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF ISNULL(@lock, 4) > 2
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Amministratore non trovato o già eliminato';
			GOTO BRANCH_END;
		END

		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il soggetto da amministrare';
			GOTO BRANCH_END;
		END
		IF @DataInizio IS NOT NULL AND @DataFine IS NOT NULL AND @DataInizio > @DataFine
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine incarico non può precedere la data di inizio';
			GOTO BRANCH_END;
		END

		-- Il soggetto già presente sulla scheda si aggiorna (date dell'incarico): i controlli
		-- sull'anagrafica valgono solo per un soggetto nuovo
		DECLARE @presente BIT = 0;
		IF EXISTS (SELECT 1 FROM dbo.tblAmministratoriSedi WHERE Id = @Id AND IdSede = @IdSede)
			SET @presente = 1;

		IF @presente = 0
		BEGIN
			-- Soggetto radice, attivo, non disabilitato e di proprietà dell'azienda della scheda
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi s
				WHERE
					s.Id = @IdSede
					AND s.InternaEsterna = 'E'
					AND s.IdParent IS NULL
					AND s.Lock = 0
					AND s.IdAziendaInterna = @idAzienda
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il soggetto non appartiene all''azienda';
				GOTO BRANCH_END;
			END
			IF EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @IdSede AND Disabilitata = 1)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il soggetto è disabilitato';
				GOTO BRANCH_END;
			END

			-- Un amministratore non amministra se stesso
			IF @idSedeAmministratore = @IdSede
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un amministratore non può amministrare se stesso';
				GOTO BRANCH_END;
			END

			-- Un amministratore non può essere a sua volta amministrato
			IF EXISTS (
				SELECT 1
				FROM dbo.tblAmministratori
				WHERE
					IdSede = @IdSede
					AND Id <> @Id
					AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il soggetto è un amministratore e non può essere amministrato';
				GOTO BRANCH_END;
			END
		END

		BEGIN TRANSACTION;
			-- Un solo amministratore per soggetto, tra le schede attive. Controllo dentro la
			-- transazione con lock di intervallo, contro due inserimenti concorrenti dello stesso soggetto
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblAmministratoriSedi x WITH (UPDLOCK, HOLDLOCK)
					INNER JOIN dbo.tblAmministratori a ON x.Id = a.Id
				WHERE
					x.IdSede = @IdSede
					AND a.Id <> @Id
					AND a.Lock = 0
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Il soggetto è già amministrato da un altro amministratore';
				GOTO BRANCH_END;
			END

			IF @presente = 1
				UPDATE dbo.tblAmministratoriSedi
				SET
					DataInizio = @DataInizio,
					DataFine = @DataFine
				WHERE
					Id = @Id
					AND IdSede = @IdSede;
			ELSE
				INSERT INTO dbo.tblAmministratoriSedi (Id, IdSede, DataInizio, DataFine)
				VALUES (@Id, @IdSede, @DataInizio, @DataFine);
		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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
