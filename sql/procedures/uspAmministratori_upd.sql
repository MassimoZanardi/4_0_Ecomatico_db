SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAmministratori_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@Note VARCHAR(1000) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- La select propone come prima voce "(Selezionare)" con Id a zeri: vale come non indicato
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(NULLIF(LTRIM(RTRIM(@IdSede)), ''), REPLICATE('0', 16));
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);

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
		DECLARE @idSedeAttuale CHAR(16);
		SELECT
			@idAzienda = c.IdAziendaInterna,
			@idSedeAttuale = c.IdSede
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

		-- Soggetto: obbligatorio e di proprietà dell'azienda della scheda. Un soggetto visto tramite
		-- un'area appartiene a un'altra azienda e non può diventare amministratore
		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il soggetto';
			GOTO BRANCH_END;
		END

		DECLARE @sedeDisabilitata BIT;
		DECLARE @sedeTrovata BIT = 0;
		SELECT
			@sedeTrovata = 1,
			@sedeDisabilitata = ISNULL(s.Disabilitata, 0)
		FROM dbo.tblSedi s
		WHERE
			s.Id = @IdSede
			AND s.InternaEsterna = 'E'
			AND s.IdParent IS NULL
			AND s.Lock = 0
			AND s.IdAziendaInterna = @idAzienda;

		IF @sedeTrovata = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il soggetto non appartiene all''azienda';
			GOTO BRANCH_END;
		END
		-- Un soggetto disabilitato resta sulla scheda che lo ha già, ma non si sceglie su un'altra
		IF @sedeDisabilitata = 1 AND (@idSedeAttuale IS NULL OR @idSedeAttuale <> @IdSede)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il soggetto è disabilitato';
			GOTO BRANCH_END;
		END

		-- Una sola scheda attiva per soggetto nella stessa azienda
		IF EXISTS (
			SELECT 1
			FROM dbo.tblAmministratori
			WHERE
				Id <> @Id
				AND IdAziendaInterna = @idAzienda
				AND IdSede = @IdSede
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il soggetto è già presente tra gli amministratori';
			GOTO BRANCH_END;
		END

		-- Un amministratore non amministra se stesso
		IF EXISTS (SELECT 1 FROM dbo.tblAmministratoriSedi WHERE Id = @Id AND IdSede = @IdSede)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un amministratore non può amministrare se stesso: toglierlo dai soggetti amministrati';
			GOTO BRANCH_END;
		END

		-- Un amministratore non può essere a sua volta amministrato da un altro
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblAmministratoriSedi x
				INNER JOIN dbo.tblAmministratori a ON x.Id = a.Id
			WHERE
				x.IdSede = @IdSede
				AND a.Id <> @Id
				AND a.Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il soggetto è amministrato da un altro amministratore e non può essere amministratore';
			GOTO BRANCH_END;
		END

		-- I soggetti amministrati della scheda (aggiunti anche quando era in bozza) si ricontrollano
		-- alla conferma: uno solo amministratore per soggetto, e nessun amministrato che sia
		-- a sua volta amministratore
		DECLARE @conflitto VARCHAR(200);
		SELECT TOP 1 @conflitto = s.NomeCompleto
		FROM
			dbo.tblAmministratoriSedi x
			INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
		WHERE
			x.Id = @Id
			AND EXISTS (
				SELECT 1
				FROM
					dbo.tblAmministratoriSedi y
					INNER JOIN dbo.tblAmministratori a ON y.Id = a.Id
				WHERE
					y.IdSede = x.IdSede
					AND a.Id <> @Id
					AND a.Lock = 0
			)
		ORDER BY s.NomeCompleto;

		IF @conflitto IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = LEFT('Il soggetto ' + @conflitto + ' è già amministrato da un altro amministratore', 200);
			GOTO BRANCH_END;
		END

		SELECT TOP 1 @conflitto = s.NomeCompleto
		FROM
			dbo.tblAmministratoriSedi x
			INNER JOIN dbo.tblSedi s ON x.IdSede = s.Id
			INNER JOIN dbo.tblAmministratori a ON x.IdSede = a.IdSede
		WHERE
			x.Id = @Id
			AND a.Id <> @Id
			AND a.Lock = 0
		ORDER BY s.NomeCompleto;

		IF @conflitto IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = LEFT('Il soggetto ' + @conflitto + ' è un amministratore e non può essere amministrato', 200);
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblAmministratori
			SET
				Lock = 0,
				IdSede = @IdSede,
				Note = @Note
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Amministratore non trovato o già eliminato';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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
