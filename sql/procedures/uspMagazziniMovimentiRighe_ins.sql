SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_ins
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@IdArticolo CHAR(16) = NULL,
	@IdCriterio CHAR(1) = NULL,
	@Quantita DECIMAL(18, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdArticolo = NULLIF(LTRIM(RTRIM(@IdArticolo)), '');
		SET @IdCriterio = NULLIF(LTRIM(RTRIM(@IdCriterio)), '');

		IF @IdMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMovimento non può essere vuoto';
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
			SET @returnMessage = 'Selezionare la sede';
			GOTO BRANCH_END;
		END
		IF @IdArticolo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''articolo';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NULL OR @Quantita <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare una quantità maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
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

		-- Il movimento deve esistere (in bozza o già confermato, non eliminato) e
		-- appartenere all'azienda interna corrente della sessione. Anche dopo la
		-- conferma le righe restano modificabili (come le Registrazioni Rifiuti):
		-- la nuova riga eredita il Lock del movimento, cosicché se il movimento è
		-- già confermato la riga conta immediatamente in giacenza (parzialmente,
		-- in base a quanto verrà allocato sui lotti).
		DECLARE @idAzienda CHAR(16), @idOperazione CHAR(1), @lockMovimento INT;
		SELECT
			@idAzienda = c.IdSede,
			@idOperazione = c.IdOperazione,
			@lockMovimento = c.Lock
		FROM
			dbo.tblMagazziniMovimenti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @IdMovimento
			AND e.Id = @IdSessione
			AND c.Lock IN (0, 2);

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il movimento non esiste';
			GOTO BRANCH_END;
		END
		IF @idOperazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare prima l''operazione (carico/scarico) sulla testata del movimento';
			GOTO BRANCH_END;
		END

		-- La sede della riga deve appartenere alla stessa azienda del movimento
		-- (la sede stessa, se il magazzino opera sull'azienda, oppure una sua sede figlia)
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSedi
			WHERE
				Id = @IdSede
				AND (Id = @idAzienda OR IdParent = @idAzienda)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede indicata non appartiene all''azienda del movimento';
			GOTO BRANCH_END;
		END

		-- Se il movimento ha un DDT associato, tutte le righe devono appartenere alla
		-- sola sede interna del DDT (IdSede, non IdMittente: quest'ultimo è un
		-- campo libero della testata, senza relazione con la sede operativa)
		IF EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniDdt
			WHERE
				IdMovimento = @IdMovimento
				AND IdSede <> @IdSede
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con un DDT associato, la riga deve appartenere alla sede interna del DDT';
			GOTO BRANCH_END;
		END

		-- L'articolo deve esistere, essere attivo e appartenere alla stessa azienda del movimento
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniArticoli
			WHERE
				Id = @IdArticolo
				AND Lock = 0
				AND IdSede = @idAzienda
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''articolo indicato non appartiene all''azienda del movimento';
			GOTO BRANCH_END;
		END

		-- Il criterio di scarico non si applica ai carichi (vedi spec: "per il carico non
		-- applicare FIFO/LIFO/FEFO"); per gli scarichi, solo i criteri per-lotto F/L/E sono
		-- attivi in questa fase (V/R fuori scope)
		IF @idOperazione = 'C' AND @IdCriterio IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il criterio di scarico non è applicabile a un carico';
			GOTO BRANCH_END;
		END
		IF @idOperazione = 'S' AND @IdCriterio IS NOT NULL AND @IdCriterio NOT IN ('F', 'L', 'E')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Criterio di scarico non valido';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblMagazziniMovimentiRighe (Id, IdMovimento, IdSede, IdArticolo, IdCriterio, Quantita, Lock)
			VALUES (@returnId, @IdMovimento, @IdSede, @IdArticolo, @IdCriterio, @Quantita, @lockMovimento);
		COMMIT TRANSACTION;

		SELECT Id = @returnId;

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
