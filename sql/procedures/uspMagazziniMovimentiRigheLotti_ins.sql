SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheLotti_ins
	@Id CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@Quantita DECIMAL(18, 2) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il lotto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NULL OR @Quantita <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare una quantità maggiore di zero';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La riga deve esistere, appartenere a un movimento non eliminato (bozza o
		-- già confermato: le allocazioni restano modificabili anche dopo la
		-- conferma, come le Registrazioni Rifiuti) e all'azienda interna corrente
		-- della sessione
		DECLARE @idSedeRiga CHAR(16), @idArticoloRiga CHAR(16), @quantitaRiga DECIMAL(18, 2), @idOperazione CHAR(1);
		SELECT
			@idSedeRiga = r.IdSede,
			@idArticoloRiga = r.IdArticolo,
			@quantitaRiga = r.Quantita,
			@idOperazione = m.IdOperazione
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblMagazziniMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
		WHERE
			r.Id = @Id
			AND e.Id = @IdSessione
			AND m.Lock IN (0, 2);

		IF @idSedeRiga IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il movimento non esiste';
			GOTO BRANCH_END;
		END

		-- Il lotto deve appartenere allo stesso Articolo+Sede della riga, essere attivo,
		-- non disabilitato e non chiuso
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniLotti
			WHERE
				Id = @IdLotto
				AND IdArticolo = @idArticoloRiga
				AND IdSede = @idSedeRiga
				AND Lock = 0
				AND ISNULL(Disabilitato, 0) = 0
				AND (DataChiusura IS NULL OR DataChiusura >= CAST(GETDATE() AS DATE))
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto selezionato non è valido per questa riga';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Lock di riga sulla disponibilità del lotto (UPDLOCK/HOLDLOCK), per
			-- serializzare eventuali allocazioni concorrenti sullo stesso lotto
			DECLARE @caricato DECIMAL(18, 2), @scaricato DECIMAL(18, 2);
			SELECT
				@caricato = SUM(CASE WHEN mv.IdOperazione = 'C' THEN rl.Quantita ELSE 0 END),
				@scaricato = SUM(CASE WHEN mv.IdOperazione = 'S' THEN rl.Quantita ELSE 0 END)
			FROM
				dbo.tblMagazziniMovimentiRigheLotti rl WITH (UPDLOCK, HOLDLOCK)
				INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rl.Id = r.Id
				INNER JOIN dbo.tblMagazziniMovimenti mv ON r.IdMovimento = mv.Id
			WHERE
				rl.IdLotto = @IdLotto
				AND r.Lock = 0
				AND mv.Lock = 0;

			DECLARE @disponibilita DECIMAL(18, 2) = ISNULL(@caricato, 0) - ISNULL(@scaricato, 0);

			-- Per uno scarico, la quantità allocata non può superare la disponibilità attuale
			-- del lotto (i carichi non hanno questo vincolo, vedi spec)
			IF @idOperazione = 'S' AND @Quantita > @disponibilita
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Quantità superiore alla disponibilità del lotto (' + FORMAT(@disponibilita, 'N2', 'it-IT') + ')';
				GOTO BRANCH_END;
			END

			-- La somma delle allocazioni della riga (inclusa questa aggiunta) non può
			-- superare la quantità della riga
			DECLARE @allocataRiga DECIMAL(18, 2) = ISNULL((SELECT SUM(Quantita) FROM dbo.tblMagazziniMovimentiRigheLotti WHERE Id = @Id), 0);

			IF (@allocataRiga + @Quantita) > @quantitaRiga
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità allocata supererebbe la quantità della riga';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheLotti WHERE Id = @Id AND IdLotto = @IdLotto)
				UPDATE dbo.tblMagazziniMovimentiRigheLotti
				SET Quantita = Quantita + @Quantita
				WHERE Id = @Id AND IdLotto = @IdLotto;
			ELSE
				INSERT dbo.tblMagazziniMovimentiRigheLotti (Id, IdLotto, Quantita)
				VALUES (@Id, @IdLotto, @Quantita);

		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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
