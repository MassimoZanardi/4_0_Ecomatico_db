SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheEoWLotti_ins
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
			SET @returnMessage = 'Selezionare il lotto EoW';
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

		-- La riga EoW deve esistere, appartenere a un movimento non eliminato (bozza
		-- o già confermato) e all'azienda interna corrente della sessione
		DECLARE @idSedeRiga CHAR(16), @idMaterialeRiga CHAR(2), @quantitaRiga DECIMAL(18, 2);
		SELECT
			@idSedeRiga = r.IdSede,
			@idMaterialeRiga = r.IdMateriale,
			@quantitaRiga = r.Quantita
		FROM
			dbo.tblMagazziniMovimentiRigheEoW r
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

		-- Il lotto EoW deve appartenere alla stessa Sede+Materiale della riga, essere
		-- attivo, non disabilitato e non chiuso (stesse regole già in vigore nel modulo EoW)
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti
			WHERE
				Id = @IdLotto
				AND IdMateriale = @idMaterialeRiga
				AND IdSede = @idSedeRiga
				AND Lock = 0
				AND ISNULL(Disabilitato, 0) = 0
				AND (DataChiusura IS NULL OR DataChiusura >= CAST(GETDATE() AS DATE))
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto EoW selezionato non è valido per questa riga';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Disponibilità del lotto EoW = quantità prodotta (registrazioni M attribuite,
			-- gestione EoW esistente, non toccata) - scarichi già eseguiti da questo modulo
			-- Magazzino. Lock di riga (UPDLOCK/HOLDLOCK) sulle allocazioni Magazzino già
			-- presenti, per serializzare eventuali scarichi concorrenti sullo stesso lotto.
			DECLARE @prodotta DECIMAL(18, 2) = ISNULL((
				SELECT SUM(Quantita) FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdLotto = @IdLotto
			), 0);
			DECLARE @scaricata DECIMAL(18, 2) = ISNULL((
				SELECT SUM(rl.Quantita)
				FROM
					dbo.tblMagazziniMovimentiRigheEoWLotti rl WITH (UPDLOCK, HOLDLOCK)
					INNER JOIN dbo.tblMagazziniMovimentiRigheEoW r ON rl.Id = r.Id
					INNER JOIN dbo.tblMagazziniMovimenti mv ON r.IdMovimento = mv.Id
				WHERE
					rl.IdLotto = @IdLotto
					AND r.Lock = 0
					AND mv.Lock = 0
			), 0);
			DECLARE @disponibilita DECIMAL(18, 2) = @prodotta - @scaricata;

			-- Le righe EoW rappresentano sempre uno scarico (il carico del materiale EoW
			-- avviene nel modulo EoW esistente, tramite attribuzione delle registrazioni M)
			IF @Quantita > @disponibilita
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Quantità superiore alla disponibilità del lotto EoW (' + FORMAT(@disponibilita, 'N2', 'it-IT') + ')';
				GOTO BRANCH_END;
			END

			-- La somma delle allocazioni della riga (inclusa questa aggiunta) non può
			-- superare la quantità della riga
			DECLARE @allocataRiga DECIMAL(18, 2) = ISNULL((SELECT SUM(Quantita) FROM dbo.tblMagazziniMovimentiRigheEoWLotti WHERE Id = @Id), 0);

			IF (@allocataRiga + @Quantita) > @quantitaRiga
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità allocata supererebbe la quantità della riga';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheEoWLotti WHERE Id = @Id AND IdLotto = @IdLotto)
				UPDATE dbo.tblMagazziniMovimentiRigheEoWLotti
				SET Quantita = Quantita + @Quantita
				WHERE Id = @Id AND IdLotto = @IdLotto;
			ELSE
				INSERT dbo.tblMagazziniMovimentiRigheEoWLotti (Id, IdLotto, Quantita)
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
