SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheEoW_ins
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@IdCriterio CHAR(1) = NULL,
	@Quantita DECIMAL(18, 2) = NULL,
	@IdLotto CHAR(16) = NULL
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
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdCriterio = NULLIF(LTRIM(RTRIM(@IdCriterio)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');

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
		IF @IdMateriale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il materiale';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NULL OR @Quantita <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare una quantità maggiore di zero';
			GOTO BRANCH_END;
		END
		-- Criterio obbligatorio: M (Manuale, lotto EoW scelto sulla riga), F/L (data di apertura
		-- del lotto EoW), E (scadenza del lotto EoW). V/R (per singolo carico) non si applicano
		-- all'EoW: il "carico" è il lotto EoW stesso.
		IF @IdCriterio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il criterio di scarico';
			GOTO BRANCH_END;
		END
		IF @IdCriterio NOT IN ('M', 'F', 'L', 'E')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Criterio di scarico non valido per un materiale EoW';
			GOTO BRANCH_END;
		END
		IF @IdCriterio = 'M' AND @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con il criterio Manuale selezionare il lotto EoW da cui scaricare';
			GOTO BRANCH_END;
		END
		IF @IdCriterio <> 'M' AND @IdLotto IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto EoW si indica solo con il criterio Manuale';
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

		-- I moduli sono opzionali per dominio: righe di materiale EoW solo con il modulo
		-- Gestione EoW attivo
		IF dbo.ufnModuli_get_IsAttivoBySessione('EOW', @IdSessione) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il modulo Gestione EoW non è attivo sul dominio';
			GOTO BRANCH_END;
		END

		-- Il movimento deve esistere (bozza o già confermato, non eliminato) e
		-- appartenere all'azienda interna corrente della sessione. IdMovimento non
		-- ha FK verso tblMagazziniMovimenti sullo schema reale: la relazione va
		-- validata qui. La riga eredita il Lock del movimento (vedi Righe_ins).
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

		-- Il magazzino EoW si carica solo dal registro rifiuti (operazione M delle
		-- Registrazioni): un movimento di carico di magazzino non può avere righe EoW
		IF @idOperazione = 'C'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il magazzino EoW si carica solo dal registro rifiuti (operazione M)';
			GOTO BRANCH_END;
		END

		-- La sede della riga deve appartenere alla stessa azienda del movimento
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

		-- Il materiale deve esistere in anagrafica (tblRifiutiMateriali, nessuna anagrafica
		-- EoW parallela - stessa convenzione già usata dal modulo EoW esistente)
		IF NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiMateriali WHERE Id = @IdMateriale)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il materiale indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Lotto EoW del criterio Manuale: stessa Sede+Materiale della riga, attivo, non
		-- disabilitato (anche se scaduto: si scarica da ciò che resta)
		IF @IdLotto IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti
			WHERE
				Id = @IdLotto
				AND IdSede = @IdSede
				AND IdMateriale = @IdMateriale
				AND Lock = 0
				AND ISNULL(Disabilitato, 0) = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto EoW selezionato non è valido per questa riga';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblMagazziniMovimentiRigheEoW (Id, IdMovimento, IdSede, IdMateriale, IdCriterio, Quantita, Lock, IdLotto)
			VALUES (@returnId, @IdMovimento, @IdSede, @IdMateriale, @IdCriterio, @Quantita, @lockMovimento, @IdLotto);
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
