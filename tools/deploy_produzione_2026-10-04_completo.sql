/*
Deploy produzione 2026-10-04 - completo (sostituisce lo script "terminologia_giacenza_disponibilita")

A. Magazzino - righe di movimento: imballo, colli, alla rinfusa, righe descrittive, posizione
   1. Struttura (rieseguibile): tblMagazziniMovimentiRighe e tblMagazziniMovimentiRigheEoW ricevono
      IdImballo (FK tblImballi), Colli, AllaRinfusa, Pos; tblMagazziniMovimentiRighe anche Descrizione.
   2. SP modificate: uspMagazziniMovimentiRighe_ins, uspMagazziniMovimentiRigheEoW_ins (nuovi parametri
      facoltativi e Pos in coda), uspMagazziniMovimentiRighe_get_List, uspMagazziniMovimentiRigheEoW_get_List
      (nuove colonne, ordinamento per Pos), uspMagazziniMovimenti_upd (le righe descrittive non scaricano
      e da sole non bastano a confermare il movimento).
   3. SP nuove: uspMagazziniMovimentiRighe_ins_Descrizione (riga di solo testo, solo con DDT),
      uspMagazziniMovimentiRighe_upd e uspMagazziniMovimentiRigheEoW_upd (modifica di imballo, colli,
      alla rinfusa, descrizione), uspMagazziniMovimentiRighe_upd_Pos (sposta su / sposta giù).

B. Magazzino ed EoW - terminologia unica Giacenza / Disponibilità
   Giacenza = quanto c'è nel lotto (caricata o allocata, meno scaricata).
   Disponibilità = quantità massima meno caricata o allocata (quanto si può ancora caricare o allocare).
   1. uspEoWLotti_get: due nuove colonne restituite, QuantitaScaricata e Giacenza.
   2. Solo testi visibili all'utente: uspEoWLotti_get_List, uspEoWGiacenze_get_List,
      uspEoWLottiRifiutiRegistrazioni_ins, uspEoWLottiRifiutiRegistrazioni_upd, uspEoWAllocazioni_esegui,
      uspMagazziniMovimenti_upd ("Giacenza insufficiente").

Nessun dato modificato: le righe esistenti restano con Pos vuota (ordinate per prime) e vengono
rinumerate al primo spostamento. Rieseguibile.

ATTENZIONE: va deployato insieme all'app, prima lo script e poi l'app. Con l'app vecchia e le SP nuove
tutto continua a funzionare (i nuovi parametri sono facoltativi); con l'app nuova e le SP vecchie
"Aggiungi riga" in Magazzino > Movimenti darebbe errore.
*/
/*
Magazzino - righe di movimento: imballo, colli, alla rinfusa, descrizione, posizione

tblMagazziniMovimentiRighe e tblMagazziniMovimentiRigheEoW:
  IdImballo CHAR(2) NULL (FK tblImballi), Colli INT NULL, AllaRinfusa BIT NULL, Pos INT NULL
tblMagazziniMovimentiRighe:
  Descrizione VARCHAR(1000) NULL (riga descrittiva del DDT: senza articolo, lotto, criterio e quantità)

Pos ordina le righe del movimento ed è unica tra le due tabelle (articoli, descrizioni e materiali EoW
si alternano liberamente). Le righe esistenti restano con Pos NULL (ordinate per prime, per Id):
uspMagazziniMovimentiRighe_upd_Pos le rinumera al primo spostamento.

Rieseguibile.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF COL_LENGTH('dbo.tblMagazziniMovimentiRighe', 'IdImballo') IS NULL
	ALTER TABLE dbo.tblMagazziniMovimentiRighe ADD
		IdImballo CHAR(2) NULL,
		Colli INT NULL,
		AllaRinfusa BIT NULL,
		Descrizione VARCHAR(1000) NULL,
		Pos INT NULL;
GO
-- Descrizione nata a 100 caratteri (solo in sviluppo) e poi allargata a 1000
IF COL_LENGTH('dbo.tblMagazziniMovimentiRighe', 'Descrizione') < 1000
	ALTER TABLE dbo.tblMagazziniMovimentiRighe ALTER COLUMN Descrizione VARCHAR(1000) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblMagazziniMovimentiRighe_tblImballi')
BEGIN
	ALTER TABLE dbo.tblMagazziniMovimentiRighe WITH CHECK ADD CONSTRAINT FK_tblMagazziniMovimentiRighe_tblImballi FOREIGN KEY (IdImballo)
	REFERENCES dbo.tblImballi (Id);
	ALTER TABLE dbo.tblMagazziniMovimentiRighe CHECK CONSTRAINT FK_tblMagazziniMovimentiRighe_tblImballi;
END
GO
IF COL_LENGTH('dbo.tblMagazziniMovimentiRigheEoW', 'IdImballo') IS NULL
	ALTER TABLE dbo.tblMagazziniMovimentiRigheEoW ADD
		IdImballo CHAR(2) NULL,
		Colli INT NULL,
		AllaRinfusa BIT NULL,
		Pos INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblMagazziniMovimentiRigheEoW_tblImballi')
BEGIN
	ALTER TABLE dbo.tblMagazziniMovimentiRigheEoW WITH CHECK ADD CONSTRAINT FK_tblMagazziniMovimentiRigheEoW_tblImballi FOREIGN KEY (IdImballo)
	REFERENCES dbo.tblImballi (Id);
	ALTER TABLE dbo.tblMagazziniMovimentiRigheEoW CHECK CONSTRAINT FK_tblMagazziniMovimentiRigheEoW_tblImballi;
END
GO
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
	@Quantita DECIMAL(18, 2) = NULL,
	@IdLotto CHAR(16) = NULL,
	@IdImballo CHAR(2) = NULL,
	@Colli INT = NULL,
	@AllaRinfusa BIT = 0
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
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		-- Imballo: '00' è il segnaposto "(Selezionare)" di uspImballi_get_SelectList; alla
		-- rinfusa non c'è imballo (come nei Formulari)
		SET @IdImballo = NULLIF(NULLIF(LTRIM(RTRIM(@IdImballo)), ''), '00');
		SET @AllaRinfusa = ISNULL(@AllaRinfusa, 0);
		IF @AllaRinfusa = 1 SET @IdImballo = NULL;

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
		IF @Colli < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero di colli non può essere negativo';
			GOTO BRANCH_END;
		END
		IF @IdImballo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblImballi WHERE Id = @IdImballo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''imballo indicato non esiste';
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

		-- Articolo gestito a numero (unità di misura NR): quantità intera, non frazionabile
		IF @Quantita <> FLOOR(@Quantita) AND EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniArticoli
			WHERE
				Id = @IdArticolo
				AND IdUnitaMisura = 'NR'
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''articolo è gestito a numero: indicare una quantità intera';
			GOTO BRANCH_END;
		END

		-- Criterio di scarico: non si applica ai carichi; obbligatorio sugli scarichi
		-- (M Manuale, F/L/E per lotto, V/R per singolo carico)
		IF @idOperazione = 'C' AND @IdCriterio IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il criterio di scarico non è applicabile a un carico';
			GOTO BRANCH_END;
		END
		IF @idOperazione = 'S' AND @IdCriterio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il criterio di scarico';
			GOTO BRANCH_END;
		END
		IF @idOperazione = 'S' AND @IdCriterio NOT IN ('M', 'F', 'L', 'E', 'V', 'R')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Criterio di scarico non valido';
			GOTO BRANCH_END;
		END

		-- Lotto: la riga di carico indica il lotto in cui entra la merce (obbligatorio, attivo,
		-- non disabilitato, non chiuso) ed è essa stessa la giacenza. La riga di scarico indica
		-- il lotto solo con il criterio Manuale (obbligatorio): lo scarico preleverà dai carichi
		-- di quel lotto (relazioni costruite in uspMagazziniMovimenti_upd); il lotto può essere
		-- anche scaduto (DataChiusura passata), purché non disabilitato. Sempre stesso
		-- Articolo+Sede della riga.
		IF @idOperazione = 'C' AND @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il lotto di carico';
			GOTO BRANCH_END;
		END
		IF @idOperazione = 'S' AND @IdCriterio = 'M' AND @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con il criterio Manuale selezionare il lotto da cui scaricare';
			GOTO BRANCH_END;
		END
		IF @idOperazione = 'S' AND @IdCriterio <> 'M' AND @IdLotto IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto si indica sulla riga di scarico solo con il criterio Manuale';
			GOTO BRANCH_END;
		END
		IF @IdLotto IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniLotti
			WHERE
				Id = @IdLotto
				AND IdArticolo = @IdArticolo
				AND IdSede = @IdSede
				AND Lock = 0
				AND ISNULL(Disabilitato, 0) = 0
				AND (@idOperazione = 'S' OR DataChiusura IS NULL OR DataChiusura >= CAST(GETDATE() AS DATE))
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto selezionato non è valido per questa riga';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			-- Posizione: in coda alle righe del movimento, unica tra righe articolo/descrizione e righe EoW
			DECLARE @pos INT;
			SELECT @pos = ISNULL(MAX(x.Pos), 0) + 1
			FROM
				(
					SELECT Pos
					FROM dbo.tblMagazziniMovimentiRighe
					WHERE IdMovimento = @IdMovimento

					UNION ALL

					SELECT Pos
					FROM dbo.tblMagazziniMovimentiRigheEoW
					WHERE IdMovimento = @IdMovimento
				) x;

			INSERT dbo.tblMagazziniMovimentiRighe (Id, IdMovimento, IdSede, IdArticolo, IdCriterio, Quantita, Lock, IdLotto, IdImballo, Colli, AllaRinfusa, Pos)
			VALUES (@returnId, @IdMovimento, @IdSede, @IdArticolo, @IdCriterio, @Quantita, @lockMovimento, @IdLotto, @IdImballo, @Colli, @AllaRinfusa, @pos);
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
	@IdLotto CHAR(16) = NULL,
	@IdImballo CHAR(2) = NULL,
	@Colli INT = NULL,
	@AllaRinfusa BIT = 0
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
		-- Imballo: '00' è il segnaposto "(Selezionare)" di uspImballi_get_SelectList; alla
		-- rinfusa non c'è imballo (come nei Formulari)
		SET @IdImballo = NULLIF(NULLIF(LTRIM(RTRIM(@IdImballo)), ''), '00');
		SET @AllaRinfusa = ISNULL(@AllaRinfusa, 0);
		IF @AllaRinfusa = 1 SET @IdImballo = NULL;

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
		IF @Colli < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero di colli non può essere negativo';
			GOTO BRANCH_END;
		END
		IF @IdImballo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblImballi WHERE Id = @IdImballo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''imballo indicato non esiste';
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
			-- Posizione: in coda alle righe del movimento, unica tra righe articolo/descrizione e righe EoW
			DECLARE @pos INT;
			SELECT @pos = ISNULL(MAX(x.Pos), 0) + 1
			FROM
				(
					SELECT Pos
					FROM dbo.tblMagazziniMovimentiRighe
					WHERE IdMovimento = @IdMovimento

					UNION ALL

					SELECT Pos
					FROM dbo.tblMagazziniMovimentiRigheEoW
					WHERE IdMovimento = @IdMovimento
				) x;

			INSERT dbo.tblMagazziniMovimentiRigheEoW (Id, IdMovimento, IdSede, IdMateriale, IdCriterio, Quantita, Lock, IdLotto, IdImballo, Colli, AllaRinfusa, Pos)
			VALUES (@returnId, @IdMovimento, @IdSede, @IdMateriale, @IdCriterio, @Quantita, @lockMovimento, @IdLotto, @IdImballo, @Colli, @AllaRinfusa, @pos);
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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Riga descrittiva: solo testo libero, da stampare sul DDT nella posizione scelta. Ammessa solo
-- sui movimenti con un DDT associato; non ha articolo, lotto, criterio né quantità, quindi non
-- entra in giacenze e relazioni carico/scarico (tutte le letture filtrano per articolo o lotto).
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_ins_Descrizione
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Descrizione VARCHAR(1000) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Descrizione = NULLIF(LTRIM(RTRIM(@Descrizione)), '');

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
		IF @Descrizione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la descrizione';
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

		-- Il movimento deve esistere (in bozza o già confermato, non eliminato) e appartenere
		-- all'azienda interna corrente della sessione; la riga eredita il Lock del movimento
		DECLARE @lockMovimento INT;
		SELECT @lockMovimento = c.Lock
		FROM
			dbo.tblMagazziniMovimenti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @IdMovimento
			AND e.Id = @IdSessione
			AND c.Lock IN (0, 2);

		IF @lockMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il movimento non esiste';
			GOTO BRANCH_END;
		END

		-- Solo con un DDT associato: la riga prende la sede interna del DDT, come tutte le altre
		DECLARE @idSede CHAR(16);
		SELECT @idSede = IdSede
		FROM dbo.tblMagazziniDdt
		WHERE IdMovimento = @IdMovimento;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le righe descrittive si possono inserire solo in un movimento con DDT';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			-- Posizione: in coda alle righe del movimento, unica tra righe articolo/descrizione e righe EoW
			DECLARE @pos INT;
			SELECT @pos = ISNULL(MAX(x.Pos), 0) + 1
			FROM
				(
					SELECT Pos
					FROM dbo.tblMagazziniMovimentiRighe
					WHERE IdMovimento = @IdMovimento

					UNION ALL

					SELECT Pos
					FROM dbo.tblMagazziniMovimentiRigheEoW
					WHERE IdMovimento = @IdMovimento
				) x;

			INSERT dbo.tblMagazziniMovimentiRighe (Id, IdMovimento, IdSede, Lock, Descrizione, Pos)
			VALUES (@returnId, @IdMovimento, @idSede, @lockMovimento, @Descrizione, @pos);
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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Modifica dei soli dati "da documento" di una riga: imballo, colli e alla rinfusa per una riga
-- articolo, il testo per una riga descrittiva. Non toccano giacenze né relazioni carico/scarico,
-- quindi sono modificabili anche a movimento confermato. Sede, articolo, lotto, criterio e
-- quantità non si modificano: la riga va tolta e reinserita.
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdImballo CHAR(2) = NULL,
	@Colli INT = NULL,
	@AllaRinfusa BIT = 0,
	@Descrizione VARCHAR(1000) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		-- Imballo: '00' è il segnaposto "(Selezionare)" di uspImballi_get_SelectList; alla
		-- rinfusa non c'è imballo (come nei Formulari)
		SET @IdImballo = NULLIF(NULLIF(LTRIM(RTRIM(@IdImballo)), ''), '00');
		SET @AllaRinfusa = ISNULL(@AllaRinfusa, 0);
		IF @AllaRinfusa = 1 SET @IdImballo = NULL;
		SET @Descrizione = NULLIF(LTRIM(RTRIM(@Descrizione)), '');

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

		-- La riga deve appartenere a un movimento (in bozza o già confermato, non eliminato)
		-- dell'azienda interna corrente della sessione
		DECLARE @isDescrizione BIT = NULL;
		SELECT @isDescrizione = IIF(r.IdArticolo IS NULL, 1, 0)
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblMagazziniMovimenti c ON r.IdMovimento = c.Id
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			r.Id = @Id
			AND e.Id = @IdSessione
			AND c.Lock IN (0, 2);

		IF @isDescrizione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la riga non esiste';
			GOTO BRANCH_END;
		END

		IF @isDescrizione = 1
		BEGIN
			-- Riga descrittiva: solo il testo
			IF @Descrizione IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare la descrizione';
				GOTO BRANCH_END;
			END
			SET @IdImballo = NULL;
			SET @Colli = NULL;
			SET @AllaRinfusa = NULL;
		END
		ELSE
		BEGIN
			SET @Descrizione = NULL;
			IF @Colli < 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il numero di colli non può essere negativo';
				GOTO BRANCH_END;
			END
			IF @IdImballo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblImballi WHERE Id = @IdImballo)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''imballo indicato non esiste';
				GOTO BRANCH_END;
			END
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblMagazziniMovimentiRighe
			SET
				IdImballo = @IdImballo,
				Colli = @Colli,
				AllaRinfusa = @AllaRinfusa,
				Descrizione = @Descrizione
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Riga non trovata o già eliminata';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
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
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Modifica dei soli dati "da documento" di una riga EoW: imballo, colli e alla rinfusa. Non
-- toccano giacenze né lotti EoW scaricati, quindi sono modificabili anche a movimento
-- confermato. Sede, materiale, lotto, criterio e quantità non si modificano: la riga va tolta
-- e reinserita.
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheEoW_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdImballo CHAR(2) = NULL,
	@Colli INT = NULL,
	@AllaRinfusa BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		-- Imballo: '00' è il segnaposto "(Selezionare)" di uspImballi_get_SelectList; alla
		-- rinfusa non c'è imballo (come nei Formulari)
		SET @IdImballo = NULLIF(NULLIF(LTRIM(RTRIM(@IdImballo)), ''), '00');
		SET @AllaRinfusa = ISNULL(@AllaRinfusa, 0);
		IF @AllaRinfusa = 1 SET @IdImballo = NULL;

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
		IF @Colli < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero di colli non può essere negativo';
			GOTO BRANCH_END;
		END
		IF @IdImballo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblImballi WHERE Id = @IdImballo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''imballo indicato non esiste';
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

		-- La riga deve appartenere a un movimento (in bozza o già confermato, non eliminato)
		-- dell'azienda interna corrente della sessione. IdMovimento non ha FK: il join è
		-- comunque valido, solo non vincolato a livello DB.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniMovimentiRigheEoW r
				INNER JOIN dbo.tblMagazziniMovimenti c ON r.IdMovimento = c.Id
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				r.Id = @Id
				AND e.Id = @IdSessione
				AND c.Lock IN (0, 2)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la riga non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblMagazziniMovimentiRigheEoW
			SET
				IdImballo = @IdImballo,
				Colli = @Colli,
				AllaRinfusa = @AllaRinfusa
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Riga non trovata o già eliminata';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
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
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Sposta su (@Direzione = -1) o giù (@Direzione = 1) una riga del movimento. La posizione è unica
-- tra tblMagazziniMovimentiRighe (articoli e descrizioni) e tblMagazziniMovimentiRigheEoW
-- (materiali): @Id può essere una riga dell'una o dell'altra tabella. Prima dello scambio le
-- righe vengono rinumerate 1..n nell'ordine corrente, così Pos mancanti (righe precedenti
-- all'introduzione di Pos) o con buchi (righe tolte) non contano. Sulla prima riga "su" e
-- sull'ultima "giù" non fanno nulla.
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_upd_Pos
	@Id CHAR(16) = NULL,
	@Direzione SMALLINT = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
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
		IF @Direzione IS NULL OR @Direzione NOT IN (-1, 1)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Direzione deve essere -1 (su) o 1 (giù)';
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

		DECLARE @idMovimento CHAR(16);
		SELECT @idMovimento = IdMovimento
		FROM dbo.tblMagazziniMovimentiRighe
		WHERE Id = @Id;

		IF @idMovimento IS NULL
		BEGIN
			SELECT @idMovimento = IdMovimento
			FROM dbo.tblMagazziniMovimentiRigheEoW
			WHERE Id = @Id;
		END

		-- Il movimento della riga deve esistere (in bozza o già confermato, non eliminato) e
		-- appartenere all'azienda interna corrente della sessione
		IF @idMovimento IS NULL OR NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniMovimenti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @idMovimento
				AND e.Id = @IdSessione
				AND c.Lock IN (0, 2)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la riga non esiste';
			GOTO BRANCH_END;
		END

		DECLARE @righe TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IsEoW BIT NOT NULL,
			PosAttuale INT NULL,
			PosNuova INT NOT NULL
		);

		BEGIN TRANSACTION;
			-- Stesso ordinamento delle _get_List (Pos NULL per prime, poi Id), a parità le righe EoW dopo
			INSERT @righe (Id, IsEoW, PosAttuale, PosNuova)
			SELECT
				x.Id,
				x.IsEoW,
				x.Pos,
				ROW_NUMBER() OVER (ORDER BY ISNULL(x.Pos, 0), x.IsEoW, x.Id)
			FROM
				(
					SELECT
						Id,
						IsEoW = CAST(0 AS BIT),
						Pos
					FROM dbo.tblMagazziniMovimentiRighe WITH (UPDLOCK, HOLDLOCK)
					WHERE IdMovimento = @idMovimento

					UNION ALL

					SELECT
						Id,
						IsEoW = CAST(1 AS BIT),
						Pos
					FROM dbo.tblMagazziniMovimentiRigheEoW WITH (UPDLOCK, HOLDLOCK)
					WHERE IdMovimento = @idMovimento
				) x;

			DECLARE @pos INT, @posAltra INT;
			SELECT @pos = PosNuova
			FROM @righe
			WHERE Id = @Id;
			SET @posAltra = @pos + @Direzione;

			IF EXISTS (SELECT 1 FROM @righe WHERE PosNuova = @posAltra)
			BEGIN
				UPDATE @righe
				SET PosNuova = IIF(Id = @Id, @posAltra, @pos)
				WHERE PosNuova IN (@pos, @posAltra);
			END

			UPDATE r
			SET Pos = t.PosNuova
			FROM
				dbo.tblMagazziniMovimentiRighe r
				INNER JOIN @righe t ON r.Id = t.Id
			WHERE
				t.IsEoW = 0
				AND ISNULL(t.PosAttuale, -1) <> t.PosNuova;

			UPDATE r
			SET Pos = t.PosNuova
			FROM
				dbo.tblMagazziniMovimentiRigheEoW r
				INNER JOIN @righe t ON r.Id = t.Id
			WHERE
				t.IsEoW = 1
				AND ISNULL(t.PosAttuale, -1) <> t.PosNuova;
		COMMIT TRANSACTION;

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
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_get_List
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniMovimenti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @IdMovimento
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			r.Id,
			r.IdSede,
			SedeNome = s.Nome,
			r.IdArticolo,
			ArticoloNome = a.Nome,
			UnitaMisuraNome = u.Nome,
			r.IdCriterio,
			CriterioNome = cr.Nome,
			r.Quantita,
			-- Riga di scarico: quantità già relazionata alle righe di carico consumate
			-- (le righe di carico non hanno relazioni proprie, sono esse stesse la giacenza)
			Relazionata = ISNULL(q.Relazionata, 0),
			r.IdLotto,
			LottoNome = l.Nome,
			IsNumero = CAST(IIF(a.IdUnitaMisura = 'NR', 1, 0) AS BIT),
			-- Riga di scarico di un movimento confermato: quantità residua (giacenza attuale)
			-- del lotto da cui la riga ha scaricato; se i carichi consumati appartengono a più
			-- lotti, somma dei residui con il dettaglio per lotto. NULL su movimento in bozza
			-- (residuo non ancora noto) e sulle righe di carico.
			ResiduoLotti = IIF(m.Lock = 0, z.ResiduoLotti, NULL),
			ResiduoLottiDettaglio = IIF(m.Lock = 0, z.ResiduoLottiDettaglio, NULL),
			r.IdImballo,
			ImballoNome = im.Nome,
			r.Colli,
			AllaRinfusa = ISNULL(r.AllaRinfusa, 0),
			-- Riga descrittiva del DDT: solo Descrizione, senza articolo, lotto, criterio e quantità
			r.Descrizione,
			r.Pos,
			r.Lock
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblMagazziniMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id
			LEFT JOIN dbo.tblMagazziniArticoli a ON r.IdArticolo = a.Id
			LEFT JOIN dbo.tblUnitaMisura u ON a.IdUnitaMisura = u.Id
			LEFT JOIN dbo.tblMagazziniCriteriScarichiLotti cr ON r.IdCriterio = cr.Id
			LEFT JOIN dbo.tblMagazziniLotti l ON r.IdLotto = l.Id
			LEFT JOIN dbo.tblImballi im ON r.IdImballo = im.Id
			OUTER APPLY (SELECT Relazionata = SUM(rel.Quantita) FROM dbo.tblMagazziniMovimentiRigheRelazioni rel WHERE rel.IdParent = r.Id) q
			OUTER APPLY (
				SELECT
					ResiduoLotti = SUM(g.Giacenza),
					ResiduoLottiDettaglio = STRING_AGG(t.Testo, N' – ') WITHIN GROUP (ORDER BY g.Nome)
				FROM
					(
						SELECT DISTINCT rc.IdLotto
						FROM
							dbo.tblMagazziniMovimentiRigheRelazioni rel
							INNER JOIN dbo.tblMagazziniMovimentiRighe rc ON rel.Id = rc.Id
						WHERE rel.IdParent = r.Id
					) lu
					INNER JOIN dbo.tblMagazziniLotti lg ON lu.IdLotto = lg.Id
					-- Giacenza del lotto: righe di carico confermate meno relazioni di scarichi
					-- confermati (stesso calcolo di uspMagazziniLotti_get_List)
					CROSS APPLY (
						SELECT
							lg.Nome,
							Giacenza = ISNULL((
								SELECT SUM(rc2.Quantita)
								FROM
									dbo.tblMagazziniMovimentiRighe rc2
									INNER JOIN dbo.tblMagazziniMovimenti mc2 ON rc2.IdMovimento = mc2.Id
								WHERE
									rc2.IdLotto = lg.Id
									AND mc2.IdOperazione = 'C'
									AND rc2.Lock = 0
									AND mc2.Lock = 0
							), 0) - ISNULL((
								SELECT SUM(rel2.Quantita)
								FROM
									dbo.tblMagazziniMovimentiRigheRelazioni rel2
									INNER JOIN dbo.tblMagazziniMovimentiRighe rc3 ON rel2.Id = rc3.Id
									INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel2.IdParent = rp.Id
									INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
								WHERE
									rc3.IdLotto = lg.Id
									AND rp.Lock = 0
									AND mp.Lock = 0
							), 0)
					) g
					CROSS APPLY (SELECT Testo = CAST(g.Nome + ': ' + FORMAT(g.Giacenza, IIF(a.IdUnitaMisura = 'NR', 'N0', 'N2'), 'it-IT') AS NVARCHAR(MAX))) t
			) z
		WHERE r.IdMovimento = @IdMovimento
		-- Pos NULL (righe precedenti all'introduzione di Pos) per prime, in ordine di Id
		ORDER BY ISNULL(r.Pos, 0), r.Id
		OPTION (RECOMPILE);

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheEoW_get_List
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniMovimenti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @IdMovimento
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			r.Id,
			r.IdSede,
			SedeNome = s.Nome,
			r.IdMateriale,
			MaterialeNome = m.Nome,
			r.IdCriterio,
			CriterioNome = cr.Nome,
			r.Quantita,
			-- Quantità già relazionata ai lotti EoW consumati (costruita in uspMagazziniMovimenti_upd)
			Relazionata = ISNULL(q.Relazionata, 0),
			r.IdLotto,
			LottoNome = lr.Nome,
			-- Movimento confermato: quantità residua (giacenza attuale) del lotto EoW da cui la
			-- riga ha scaricato; su più lotti somma dei residui con il dettaglio per lotto.
			-- NULL su movimento in bozza (residuo non ancora noto).
			ResiduoLotti = IIF(mv.Lock = 0, z.ResiduoLotti, NULL),
			ResiduoLottiDettaglio = IIF(mv.Lock = 0, z.ResiduoLottiDettaglio, NULL),
			-- Anomalia "Scaricato più del prodotto": almeno un lotto EoW da cui la riga ha scaricato ha
			-- giacenza negativa (il registro operativo gli attribuisce meno di quanto già scaricato; il
			-- magazzino EoW prevale, i movimenti non vengono corretti in automatico)
			IsScaricatoPiuDelProdotto = CAST(IIF(mv.Lock = 0 AND ISNULL(z.LottiAnomali, 0) > 0, 1, 0) AS BIT),
			r.IdImballo,
			ImballoNome = im.Nome,
			r.Colli,
			AllaRinfusa = ISNULL(r.AllaRinfusa, 0),
			r.Pos,
			r.Lock
		FROM
			dbo.tblMagazziniMovimentiRigheEoW r
			INNER JOIN dbo.tblMagazziniMovimenti mv ON r.IdMovimento = mv.Id
			INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id
			LEFT JOIN dbo.tblRifiutiMateriali m ON r.IdMateriale = m.Id
			LEFT JOIN dbo.tblMagazziniCriteriScarichiLotti cr ON r.IdCriterio = cr.Id
			LEFT JOIN dbo.tblEoWLotti lr ON r.IdLotto = lr.Id
			LEFT JOIN dbo.tblImballi im ON r.IdImballo = im.Id
			OUTER APPLY (SELECT Relazionata = SUM(rl.Quantita)
			FROM dbo.tblMagazziniMovimentiRigheEoWLotti rl
			WHERE rl.Id = r.Id) q
			OUTER APPLY (
				SELECT
					ResiduoLotti = SUM(g.Giacenza),
					LottiAnomali = SUM(IIF(g.Giacenza < 0, 1, 0)),
					ResiduoLottiDettaglio = STRING_AGG(t.Testo, N' – ') WITHIN GROUP (ORDER BY g.Nome)
				FROM
					dbo.tblMagazziniMovimentiRigheEoWLotti rl
					INNER JOIN dbo.tblEoWLotti lg ON rl.IdLotto = lg.Id
					-- Giacenza del lotto EoW: quote di registrazioni M attive meno scarichi
					-- confermati di questo modulo
					CROSS APPLY (
						SELECT
							lg.Nome,
							Giacenza = ISNULL((
								SELECT SUM(qp.Quantita)
								FROM
									dbo.tblEoWLottiRifiutiRegistrazioni qp
									INNER JOIN dbo.tblRifiutiRegistrazioni rr ON qp.IdRegistrazione = rr.Id
								WHERE
									qp.IdLotto = lg.Id
									AND rr.Lock < 2
							), 0) - ISNULL((
								SELECT SUM(rs.Quantita)
								FROM
									dbo.tblMagazziniMovimentiRigheEoWLotti rs
									INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rp ON rs.Id = rp.Id
									INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
								WHERE
									rs.IdLotto = lg.Id
									AND rp.Lock = 0
									AND mp.Lock = 0
							), 0)
					) g
									CROSS APPLY (SELECT Testo = CAST(g.Nome + ': ' + FORMAT(g.Giacenza, 'N2', 'it-IT') AS NVARCHAR(MAX))) t
				WHERE rl.Id = r.Id) z
		WHERE r.IdMovimento = @IdMovimento
		-- Pos NULL (righe precedenti all'introduzione di Pos) per prime, in ordine di Id
		ORDER BY ISNULL(r.Pos, 0), r.Id
		OPTION (RECOMPILE);

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimenti_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Data DATE = NULL,
	@Numero INT = NULL,
	@DdtIdCausale CHAR(1) = NULL,
	@DdtNumeroFornitore VARCHAR(20) = NULL,
	@DdtSezionale CHAR(1) = NULL,
	@DdtData DATE = NULL,
	@DdtIdMittente CHAR(16) = NULL,
	@DdtIdDestinatario CHAR(16) = NULL,
	@DdtIdTrasportatore CHAR(16) = NULL,
	@DdtDataInizioTrasporto SMALLDATETIME = NULL,
	@DdtPeso DECIMAL(18, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @confermato BIT = 0;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
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
		IF @Numero IS NOT NULL AND @Numero <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero deve essere maggiore di zero';
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

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione.
		-- Come le Registrazioni Rifiuti (uspRifiutiRegistrazioni_upd): "Salva" conferma sempre
		-- il movimento (Lock 2->0) oppure si blocca con un errore, e un movimento già
		-- confermato (Lock = 0) si può risalvare modificando anche data e numero (l'operazione
		-- resta quella fissata alla creazione), con i controlli cronologici sulle relazioni.
		DECLARE @idAzienda CHAR(16), @idOperazione CHAR(1), @lockMovimento INT, @dataPrecedente DATE, @numeroPrecedente INT;
		SELECT
			@idAzienda = c.IdSede,
			@idOperazione = c.IdOperazione,
			@lockMovimento = c.Lock,
			@dataPrecedente = c.[Data],
			@numeroPrecedente = c.Numero
		FROM
			dbo.tblMagazziniMovimenti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF @lockMovimento NOT IN (0, 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Movimento non trovato o già eliminato';
			GOTO BRANCH_END;
		END
		IF @Data IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data del movimento';
			GOTO BRANCH_END;
		END
		-- Le righe descrittive del DDT (senza articolo) non bastano: serve almeno una riga di merce
		IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE IdMovimento = @Id AND IdArticolo IS NOT NULL)
			AND NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheEoW WHERE IdMovimento = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Aggiungere almeno una riga';
			GOTO BRANCH_END;
		END

		-- Movimento già confermato con data o numero modificati: le relazioni carico/scarico
		-- vanno ricontrollate/ricostruite rispetto alla nuova posizione cronologica
		DECLARE @dataNumeroModificati BIT = IIF(
			@lockMovimento = 0
			AND (@Data <> @dataPrecedente OR ISNULL(@Numero, -1) <> ISNULL(@numeroPrecedente, -1)), 1, 0);

		BEGIN TRANSACTION;

			-- Data/Numero: il numero digitato dall'utente viene validato/rinumerato più sotto,
			-- dopo le relazioni. IdOperazione è fissato alla creazione
			-- (uspMagazziniMovimenti_ins) e non è più modificabile.
			UPDATE dbo.tblMagazziniMovimenti
			SET
				Data = @Data,
				Numero = @Numero
			WHERE
				Id = @Id
				AND Lock IN (0, 2);

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Movimento non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			-- DDT: se presente e ancora in bozza, viene confermato insieme al movimento (Lock
			-- 2->0, Numero assegnato) nello stesso click e nella stessa SP; se i campi
			-- obbligatori (Causale, Data, Destinatario) non sono completi il salvataggio si
			-- blocca con un errore (come le Registrazioni Rifiuti). Se il DDT è già confermato
			-- (Lock = 0) resta immutabile.
			DECLARE @idDdt CHAR(16), @idSedeDdt CHAR(16), @lockDdt INT;
			SELECT @idDdt = Id, @idSedeDdt = IdSede, @lockDdt = Lock
			FROM dbo.tblMagazziniDdt
			WHERE IdMovimento = @Id;

			IF @idDdt IS NOT NULL AND @lockDdt = 2
			BEGIN
				SET @DdtIdCausale = NULLIF(LTRIM(RTRIM(@DdtIdCausale)), '');
				SET @DdtNumeroFornitore = dbo.ufnStringhe_get_SenzaSpazi(@DdtNumeroFornitore, 0, 1);
				SET @DdtSezionale = NULLIF(LTRIM(RTRIM(@DdtSezionale)), '');
				SET @DdtIdMittente = NULLIF(LTRIM(RTRIM(@DdtIdMittente)), '');
				SET @DdtIdDestinatario = NULLIF(LTRIM(RTRIM(@DdtIdDestinatario)), '');
				SET @DdtIdTrasportatore = NULLIF(LTRIM(RTRIM(@DdtIdTrasportatore)), '');

				-- DDT ricevuto (emesso da un fornitore esterno) = sezionale R, riservato: ammesso
				-- solo sui movimenti di carico e sempre con il numero del documento del fornitore;
				-- viceversa il numero fornitore esiste solo per i DDT ricevuti. Nessun controllo
				-- di univocità sul numero fornitore (scelta esplicita).
				IF @DdtSezionale = 'R'
					AND NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimenti WHERE Id = @Id AND IdOperazione = 'C')
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il sezionale R è riservato ai DDT ricevuti, ammessi solo sui movimenti di carico';
					GOTO BRANCH_END;
				END
				IF @DdtSezionale = 'R' AND @DdtNumeroFornitore IS NULL
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Indicare il numero fornitore del DDT ricevuto';
					GOTO BRANCH_END;
				END
				IF @DdtNumeroFornitore IS NOT NULL AND ISNULL(@DdtSezionale, '') <> 'R'
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il numero fornitore si indica solo per i DDT ricevuti';
					GOTO BRANCH_END;
				END

				IF @DdtIdCausale IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniCausali WHERE Id = @DdtIdCausale)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Causale del DDT non valida';
					GOTO BRANCH_END;
				END
				IF @DdtPeso IS NOT NULL AND @DdtPeso <= 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il peso del DDT deve essere maggiore di zero';
					GOTO BRANCH_END;
				END
				-- IdMittente è un campo libero della testata (valore stampato sul documento,
				-- l'utente lo compila a piacimento): nessuna relazione con la sede interna
				IF @DdtIdMittente IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @DdtIdMittente)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il mittente del DDT indicato non esiste';
					GOTO BRANCH_END;
				END
				IF @DdtIdDestinatario IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @DdtIdDestinatario)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il destinatario del DDT indicato non esiste';
					GOTO BRANCH_END;
				END
				IF @DdtIdTrasportatore IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @DdtIdTrasportatore)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il trasportatore del DDT indicato non esiste';
					GOTO BRANCH_END;
				END

				IF @DdtIdCausale IS NULL OR @DdtData IS NULL OR @DdtIdDestinatario IS NULL
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Completare il DDT: causale, data e destinatario';
					GOTO BRANCH_END;
				END

				-- Numerazione indipendente per sede interna + sezionale, calcolata dentro
				-- la transazione con lock di riga per evitare duplicati in caso di
				-- richieste concorrenti sulla stessa sede/sezionale
				DECLARE @numeroDdt INT;
				SELECT @numeroDdt = ISNULL(MAX(Numero), 0) + 1
				FROM dbo.tblMagazziniDdt WITH (UPDLOCK, HOLDLOCK)
				WHERE
					IdSede = @idSedeDdt
					AND (Sezionale = @DdtSezionale OR (Sezionale IS NULL AND @DdtSezionale IS NULL))
					AND Id <> @idDdt;

				UPDATE dbo.tblMagazziniDdt
				SET
					Lock = 0,
					IdCausale = @DdtIdCausale,
					Numero = @numeroDdt,
					NumeroFornitore = @DdtNumeroFornitore,
					Sezionale = @DdtSezionale,
					Data = @DdtData,
					IdMittente = @DdtIdMittente,
					IdDestinatario = @DdtIdDestinatario,
					IdTrasportatore = @DdtIdTrasportatore,
					DataInizioTrasporto = @DdtDataInizioTrasporto,
					Peso = @DdtPeso
				WHERE Id = @idDdt;
			END

			-- Relazioni carico/scarico delle righe tradizionali (stessa logica di
			-- uspRifiutiRegistrazioni_upd): la riga di carico è essa stessa la giacenza, la
			-- riga di scarico si relaziona alle righe di carico che consuma. L'unica variante
			-- è l'ordine di consumo, dato dal criterio di scarico della riga:
			--   M (Manuale) solo i carichi del lotto scelto sulla riga, dal più vecchio;
			--   F (FIFO per lotto) lotti per data di apertura crescente, poi carichi dal più vecchio;
			--   L (LIFO per lotto) lotti per data di apertura decrescente, poi carichi dal più recente;
			--   E (FEFO) lotti per scadenza (DataChiusura) crescente, poi carichi dal più vecchio;
			--   V (FIFO per carico) carichi per data/numero crescenti;
			--   R (LIFO per carico) carichi per data/numero decrescenti.
			-- Carichi candidati: stessa Sede+Articolo, movimento di carico confermato,
			-- cronologicamente precedente allo scarico (a parità di data, numero inferiore;
			-- scarico non ancora numerato = dopo tutti i confermati), residuo > 0. Il residuo
			-- di un carico è la sua quantità meno le relazioni di scarichi non eliminati.
			-- Si ricostruiscono tutte le righe in bozza o se sono cambiati data/numero di un
			-- movimento confermato; altrimenti, sul confermato, solo le righe non ancora
			-- completamente relazionate (le altre sono storia consolidata).
			IF @idOperazione = 'S'
			BEGIN
				DECLARE
					@idRiga CHAR(16),
					@idSedeRiga CHAR(16),
					@idArticoloRiga CHAR(16),
					@idCriterioRiga CHAR(1),
					@idLottoRiga CHAR(16),
					@quantitaRiga DECIMAL(18, 2),
					@articoloNome VARCHAR(50),
					@lottoNome VARCHAR(50),
					@isNumero BIT,
					@daRelazionare DECIMAL(18, 2),
					@idCarico CHAR(16),
					@residuoCarico DECIMAL(18, 2),
					@quotaCarico DECIMAL(18, 2),
					@rowNum INT,
					@maxRow INT;

				CREATE TABLE #Candidati (
					RowNum INT IDENTITY(1, 1) PRIMARY KEY,
					IdCarico CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
					Residuo DECIMAL(18, 2) NOT NULL
				);

				DECLARE cRighe CURSOR LOCAL FAST_FORWARD FOR
					SELECT
						r.Id,
						r.IdSede,
						r.IdArticolo,
						r.IdCriterio,
						r.IdLotto,
						r.Quantita,
						a.Nome,
						lr.Nome,
						CAST(IIF(a.IdUnitaMisura = 'NR', 1, 0) AS BIT)
					FROM
						dbo.tblMagazziniMovimentiRighe r
						LEFT JOIN dbo.tblMagazziniArticoli a ON r.IdArticolo = a.Id
						LEFT JOIN dbo.tblMagazziniLotti lr ON r.IdLotto = lr.Id
						OUTER APPLY (SELECT Relazionata = SUM(rel.Quantita) FROM dbo.tblMagazziniMovimentiRigheRelazioni rel WHERE rel.IdParent = r.Id) q
					WHERE
						r.IdMovimento = @Id
						-- Le righe descrittive del DDT (senza articolo) non scaricano nulla
						AND r.IdArticolo IS NOT NULL
						AND (@lockMovimento = 2 OR @dataNumeroModificati = 1 OR ISNULL(q.Relazionata, 0) <> r.Quantita)
					ORDER BY r.Id;

				OPEN cRighe;
				FETCH cRighe INTO @idRiga, @idSedeRiga, @idArticoloRiga, @idCriterioRiga, @idLottoRiga, @quantitaRiga, @articoloNome, @lottoNome, @isNumero;

				WHILE @@FETCH_STATUS = 0
				BEGIN
					IF @idCriterioRiga IS NULL OR (@idCriterioRiga = 'M' AND @idLottoRiga IS NULL)
					BEGIN
						CLOSE cRighe;
						DEALLOCATE cRighe;
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Completare il criterio di scarico della riga dell''articolo ' + ISNULL(@articoloNome, '');
						GOTO BRANCH_END;
					END

					-- Relazioni ricostruite da zero nell'ordine del criterio. Lock di riga
					-- (UPDLOCK/HOLDLOCK) sulle relazioni dei carichi candidati, per serializzare
					-- scarichi concorrenti sugli stessi carichi.
					TRUNCATE TABLE #Candidati;

					DELETE dbo.tblMagazziniMovimentiRigheRelazioni
					WHERE IdParent = @idRiga;

					INSERT INTO #Candidati (IdCarico, Residuo)
					SELECT
						rc.Id,
						rc.Quantita - ISNULL(c.Consumata, 0)
					FROM
						dbo.tblMagazziniMovimentiRighe rc
						INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
						LEFT JOIN dbo.tblMagazziniLotti l ON rc.IdLotto = l.Id
						OUTER APPLY (
							SELECT Consumata = SUM(rel.Quantita)
							FROM
								dbo.tblMagazziniMovimentiRigheRelazioni rel WITH (UPDLOCK, HOLDLOCK)
								INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
								INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
							WHERE
								rel.Id = rc.Id
								AND mp.Lock IN (0, 2)
						) c
					WHERE
						mc.IdOperazione = 'C'
						AND mc.Lock = 0
						AND rc.Lock = 0
						AND rc.IdSede = @idSedeRiga
						AND rc.IdArticolo = @idArticoloRiga
						AND (@idCriterioRiga <> 'M' OR rc.IdLotto = @idLottoRiga)
						AND (
							mc.[Data] < @Data
							OR (mc.[Data] = @Data AND (@Numero IS NULL OR mc.Numero < @Numero))
						)
						AND rc.Quantita - ISNULL(c.Consumata, 0) > 0
					ORDER BY
						CASE WHEN @idCriterioRiga = 'F' THEN l.DataApertura END ASC,
						CASE WHEN @idCriterioRiga = 'L' THEN l.DataApertura END DESC,
						CASE WHEN @idCriterioRiga = 'E' THEN ISNULL(l.DataChiusura, '9999-12-31') END ASC,
						CASE WHEN @idCriterioRiga IN ('L', 'R') THEN mc.[Data] END DESC,
						CASE WHEN @idCriterioRiga IN ('L', 'R') THEN mc.Numero END DESC,
						mc.[Data] ASC,
						mc.Numero ASC,
						rc.Id;

					-- Distribuzione greedy, carico per carico, fino al residuo di ciascuno
					SET @daRelazionare = @quantitaRiga;
					SET @rowNum = 1;
					SET @maxRow = ISNULL((SELECT MAX(RowNum) FROM #Candidati), 0);

					WHILE @daRelazionare > 0 AND @rowNum <= @maxRow
					BEGIN
						SELECT @idCarico = IdCarico, @residuoCarico = Residuo FROM #Candidati WHERE RowNum = @rowNum;
						SET @quotaCarico = IIF(@residuoCarico < @daRelazionare, @residuoCarico, @daRelazionare);

						IF @quotaCarico > 0
						BEGIN
							INSERT dbo.tblMagazziniMovimentiRigheRelazioni (Id, IdParent, Quantita, Pos)
							VALUES (@idCarico, @idRiga, @quotaCarico, @rowNum - 1);

							SET @daRelazionare = @daRelazionare - @quotaCarico;
						END

						SET @rowNum = @rowNum + 1;
					END

					IF @daRelazionare > 0
					BEGIN
						CLOSE cRighe;
						DEALLOCATE cRighe;
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage =
							'Giacenza insufficiente '
							+ IIF(@idCriterioRiga = 'M', 'nel lotto ' + ISNULL(@lottoNome, '') + ' ', '')
							+ 'per l''articolo ' + ISNULL(@articoloNome, '')
							+ ' (mancano ' + FORMAT(@daRelazionare, IIF(@isNumero = 1, 'N0', 'N2'), 'it-IT') + ')';
						GOTO BRANCH_END;
					END

					FETCH cRighe INTO @idRiga, @idSedeRiga, @idArticoloRiga, @idCriterioRiga, @idLottoRiga, @quantitaRiga, @articoloNome, @lottoNome, @isNumero;
				END

				CLOSE cRighe;
				DEALLOCATE cRighe;
			END

			-- Relazioni delle righe EoW (stessa logica delle righe tradizionali): per l'EoW il
			-- "carico" è il lotto EoW, alimentato dalle quote delle registrazioni rifiuti M
			-- (tblEoWLottiRifiutiRegistrazioni); la riga EoW di scarico si relaziona ai lotti EoW
			-- che consuma (tblMagazziniMovimentiRigheEoWLotti). Ordine di consumo dal criterio:
			--   M (Manuale) solo il lotto EoW scelto sulla riga;
			--   F (FIFO) lotti per data di apertura crescente; L (LIFO) decrescente;
			--   E (FEFO) lotti per scadenza (DataChiusura) crescente.
			-- Lotti candidati: stessa Sede+Materiale, attivi, non disabilitati. Disponibile alla
			-- data dello scarico = quote di registrazioni M attive con data <= data dello scarico
			-- (non si scarica materiale non ancora prodotto a quella data) meno quanto già
			-- scaricato dal lotto da scarichi non eliminati.
			DECLARE
				@idRigaEoW CHAR(16),
				@idSedeRigaEoW CHAR(16),
				@idMaterialeRigaEoW CHAR(2),
				@idCriterioRigaEoW CHAR(1),
				@idLottoRigaEoW CHAR(16),
				@quantitaRigaEoW DECIMAL(18, 2),
				@materialeNome VARCHAR(100),
				@lottoEoWNome VARCHAR(50),
				@daRelazionareEoW DECIMAL(18, 2),
				@idLottoEoW CHAR(16),
				@residuoLottoEoW DECIMAL(18, 2),
				@quotaLottoEoW DECIMAL(18, 2),
				@rowNumEoW INT,
				@maxRowEoW INT;

			CREATE TABLE #CandidatiEoW (
				RowNum INT IDENTITY(1, 1) PRIMARY KEY,
				IdLotto CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
				Residuo DECIMAL(18, 2) NOT NULL
			);

			DECLARE cRigheEoW CURSOR LOCAL FAST_FORWARD FOR
				SELECT
					r.Id,
					r.IdSede,
					r.IdMateriale,
					r.IdCriterio,
					r.IdLotto,
					r.Quantita,
					m.Nome,
					lr.Nome
				FROM
					dbo.tblMagazziniMovimentiRigheEoW r
					LEFT JOIN dbo.tblRifiutiMateriali m ON r.IdMateriale = m.Id
					LEFT JOIN dbo.tblEoWLotti lr ON r.IdLotto = lr.Id
					OUTER APPLY (SELECT Relazionata = SUM(rl.Quantita) FROM dbo.tblMagazziniMovimentiRigheEoWLotti rl WHERE rl.Id = r.Id) q
				WHERE
					r.IdMovimento = @Id
					AND (@lockMovimento = 2 OR @dataNumeroModificati = 1 OR ISNULL(q.Relazionata, 0) <> r.Quantita)
				ORDER BY r.Id;

			OPEN cRigheEoW;
			FETCH cRigheEoW INTO @idRigaEoW, @idSedeRigaEoW, @idMaterialeRigaEoW, @idCriterioRigaEoW, @idLottoRigaEoW, @quantitaRigaEoW, @materialeNome, @lottoEoWNome;

			WHILE @@FETCH_STATUS = 0
			BEGIN
				IF @idCriterioRigaEoW IS NULL OR @idCriterioRigaEoW NOT IN ('M', 'F', 'L', 'E') OR (@idCriterioRigaEoW = 'M' AND @idLottoRigaEoW IS NULL)
				BEGIN
					CLOSE cRigheEoW;
					DEALLOCATE cRigheEoW;
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Completare il criterio di scarico della riga del materiale ' + ISNULL(@materialeNome, '');
					GOTO BRANCH_END;
				END

				-- Relazioni ricostruite da zero nell'ordine del criterio. Lock di riga
				-- (UPDLOCK/HOLDLOCK) sulle relazioni dei lotti candidati, per serializzare
				-- scarichi concorrenti sugli stessi lotti EoW.
				TRUNCATE TABLE #CandidatiEoW;

				DELETE dbo.tblMagazziniMovimentiRigheEoWLotti
				WHERE Id = @idRigaEoW;

				INSERT INTO #CandidatiEoW (IdLotto, Residuo)
				SELECT
					l.Id,
					ISNULL(p.Prodotta, 0) - ISNULL(sc.Scaricata, 0)
				FROM
					dbo.tblEoWLotti l
					OUTER APPLY (
						SELECT Prodotta = SUM(qp.Quantita)
						FROM
							dbo.tblEoWLottiRifiutiRegistrazioni qp
							INNER JOIN dbo.tblRifiutiRegistrazioni rr ON qp.IdRegistrazione = rr.Id
						WHERE
							qp.IdLotto = l.Id
							AND rr.Lock < 2
							AND rr.[Data] <= @Data
					) p
					OUTER APPLY (
						SELECT Scaricata = SUM(rs.Quantita)
						FROM
							dbo.tblMagazziniMovimentiRigheEoWLotti rs WITH (UPDLOCK, HOLDLOCK)
							INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rp ON rs.Id = rp.Id
							INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
						WHERE
							rs.IdLotto = l.Id
							AND mp.Lock IN (0, 2)
					) sc
				WHERE
					l.IdSede = @idSedeRigaEoW
					AND l.IdMateriale = @idMaterialeRigaEoW
					AND l.Lock = 0
					AND ISNULL(l.Disabilitato, 0) = 0
					AND (@idCriterioRigaEoW <> 'M' OR l.Id = @idLottoRigaEoW)
					AND ISNULL(p.Prodotta, 0) - ISNULL(sc.Scaricata, 0) > 0
				ORDER BY
					CASE WHEN @idCriterioRigaEoW = 'L' THEN l.DataApertura END DESC,
					CASE WHEN @idCriterioRigaEoW = 'E' THEN ISNULL(l.DataChiusura, '9999-12-31') END ASC,
					l.DataApertura ASC,
					l.Id;

				-- Distribuzione greedy, lotto per lotto, fino al disponibile di ciascuno
				SET @daRelazionareEoW = @quantitaRigaEoW;
				SET @rowNumEoW = 1;
				SET @maxRowEoW = ISNULL((SELECT MAX(RowNum) FROM #CandidatiEoW), 0);

				WHILE @daRelazionareEoW > 0 AND @rowNumEoW <= @maxRowEoW
				BEGIN
					SELECT @idLottoEoW = IdLotto, @residuoLottoEoW = Residuo FROM #CandidatiEoW WHERE RowNum = @rowNumEoW;
					SET @quotaLottoEoW = IIF(@residuoLottoEoW < @daRelazionareEoW, @residuoLottoEoW, @daRelazionareEoW);

					IF @quotaLottoEoW > 0
					BEGIN
						INSERT dbo.tblMagazziniMovimentiRigheEoWLotti (Id, IdLotto, Quantita, Pos)
						VALUES (@idRigaEoW, @idLottoEoW, @quotaLottoEoW, @rowNumEoW - 1);

						SET @daRelazionareEoW = @daRelazionareEoW - @quotaLottoEoW;
					END

					SET @rowNumEoW = @rowNumEoW + 1;
				END

				IF @daRelazionareEoW > 0
				BEGIN
					CLOSE cRigheEoW;
					DEALLOCATE cRigheEoW;
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage =
						'Giacenza insufficiente '
						+ IIF(@idCriterioRigaEoW = 'M', 'nel lotto EoW ' + ISNULL(@lottoEoWNome, '') + ' ', '')
						+ 'per il materiale ' + ISNULL(@materialeNome, '')
						+ ' (mancano ' + FORMAT(@daRelazionareEoW, 'N2', 'it-IT') + ')';
					GOTO BRANCH_END;
				END

				FETCH cRigheEoW INTO @idRigaEoW, @idSedeRigaEoW, @idMaterialeRigaEoW, @idCriterioRigaEoW, @idLottoRigaEoW, @quantitaRigaEoW, @materialeNome, @lottoEoWNome;
			END

			CLOSE cRigheEoW;
			DEALLOCATE cRigheEoW;

			-- Conferma (o riconferma) del movimento: "Salva" conferma sempre, come le
			-- Registrazioni Rifiuti; ogni condizione non soddisfatta ha già bloccato sopra
			BEGIN
				-- Numerazione: progressivo annuale per Azienda + anno di Data, tra i soli
				-- movimenti già confermati (Lock = 0). UPDLOCK/HOLDLOCK per serializzare
				-- conferme concorrenti nello stesso anno/azienda.
				DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@Data), 1, 1);
				DECLARE @annoFine DATE = DATEADD(YEAR, 1, @annoInizio);

				IF @Numero IS NULL
				BEGIN
					SELECT @Numero = ISNULL(MAX(Numero), 0) + 1
					FROM dbo.tblMagazziniMovimenti WITH (UPDLOCK, HOLDLOCK)
					WHERE
						IdSede = @idAzienda
						AND Lock = 0
						AND Data >= @annoInizio
						AND Data < @annoFine;
				END
				ELSE
				BEGIN
					-- Collisione esatta con un altro movimento già confermato: rinumera (+1)
					-- tutti i movimenti con Numero >= quello scelto, nello stesso anno/azienda,
					-- per fare spazio - permette di riusare un "buco" lasciato da una
					-- cancellazione senza doverli spostare manualmente uno per uno.
					IF EXISTS (
						SELECT 1
						FROM dbo.tblMagazziniMovimenti WITH (UPDLOCK, HOLDLOCK)
						WHERE
							Id <> @Id
							AND IdSede = @idAzienda
							AND Lock = 0
							AND Data >= @annoInizio
							AND Data < @annoFine
							AND Numero = @Numero
					)
					BEGIN
						UPDATE dbo.tblMagazziniMovimenti
						SET Numero = Numero + 1
						WHERE
							Id <> @Id
							AND IdSede = @idAzienda
							AND Lock = 0
							AND Data >= @annoInizio
							AND Data < @annoFine
							AND Numero >= @Numero;
					END

					-- Coerenza cronologica: un movimento con Data precedente non può avere un
					-- numero maggiore o uguale, uno con Data successiva non può averne uno
					-- minore o uguale, nello stesso anno/azienda. Qui si blocca con un errore
					-- invece di tentare un riordino automatico più ampio, per non correggere
					-- inavvertitamente dati che potrebbero già essere corretti per altri motivi.
					IF EXISTS (
						SELECT 1
						FROM dbo.tblMagazziniMovimenti
						WHERE
							Id <> @Id
							AND IdSede = @idAzienda
							AND Lock = 0
							AND Data >= @annoInizio
							AND Data < @annoFine
							AND (
								(Data < @Data AND Numero >= @Numero)
								OR (Data > @Data AND Numero <= @Numero)
							)
					)
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Il numero indicato non è coerente con la data rispetto ad altri movimenti dello stesso anno';
						GOTO BRANCH_END;
					END
				END

				-- Carico già confermato spostato di data/numero: non può finire dopo gli scarichi
				-- (non eliminati) che ne consumano le righe (come il "Controllo data relazioni"
				-- delle Registrazioni Rifiuti)
				IF @idOperazione = 'C' AND @dataNumeroModificati = 1 AND EXISTS (
					SELECT 1
					FROM
						dbo.tblMagazziniMovimentiRighe rc
						INNER JOIN dbo.tblMagazziniMovimentiRigheRelazioni rel ON rel.Id = rc.Id
						INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
						INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
					WHERE
						rc.IdMovimento = @Id
						AND mp.Lock IN (0, 2)
						AND (
							mp.[Data] < @Data
							OR (mp.[Data] = @Data AND mp.Numero IS NOT NULL AND mp.Numero <= @Numero)
						)
				)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il carico è già utilizzato da scarichi con data e/o numero precedenti';
					GOTO BRANCH_END;
				END

				UPDATE dbo.tblMagazziniMovimenti
				SET
					Lock = 0,
					Numero = @Numero
				WHERE
					Id = @Id
					AND Lock IN (0, 2);

				UPDATE dbo.tblMagazziniMovimentiRighe
				SET Lock = 0
				WHERE IdMovimento = @Id;

				UPDATE dbo.tblMagazziniMovimentiRigheEoW
				SET Lock = 0
				WHERE IdMovimento = @Id;

				SET @confermato = IIF(@lockMovimento = 2, 1, 0);
			END

		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';
		IF @idDdt IS NOT NULL
			EXEC dbo.uspId_upd @Id = @idDdt, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue, Confermato = @confermato, Numero = @Numero;

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEoWLotti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWLotti
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lotto non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			l.Id,
			l.IdSede,
			SedeNome = s.Nome,
			l.IdMagazzino,
			MagazzinoNome = g.Nome,
			l.IdMateriale,
			MaterialeNome = m.Nome,
			l.Nome,
			l.DataApertura,
			l.DataChiusura,
			l.QuantitaMax,
			QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0),
			-- Scaricata dal magazzino e giacenza (allocata - scaricata): gli scarichi non liberano capienza
			QuantitaScaricata = sl.Scaricata,
			Giacenza = sl.Giacenza,
			CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAllocata, 0) END,
			Disabilitato = ISNULL(l.Disabilitato, 0),
			l.Lock
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.tblSedi s ON l.IdSede = s.Id
			LEFT JOIN dbo.tblEoWMagazzini g ON l.IdMagazzino = g.Id
			LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
			OUTER APPLY (
				-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
				-- mantiene le sue quote per un eventuale ripristino, ma non conta più
				SELECT QuantitaAllocata = SUM(r.Quantita)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
				WHERE
					r.IdLotto = l.Id
					AND rr.Lock < 2
			) q
			CROSS APPLY dbo.ufnEoWLotti_get_Saldo(l.Id) sl
		WHERE
			l.Id = @Id
			AND l.Lock <= 2;

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdMagazzino CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@Aperto BIT = NULL,
	@Disabilitato BIT = NULL,
	@DataAperturaDa DATE = NULL,
	@DataAperturaA DATE = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		-- Le select della ricerca usano gli zeri come "nessuna selezione" ((Nessuno)/(Selezionare))
		SET @IdMagazzino = NULLIF(NULLIF(LTRIM(RTRIM(@IdMagazzino)), ''), REPLICATE('0', 16));
		SET @IdMateriale = NULLIF(NULLIF(LTRIM(RTRIM(@IdMateriale)), ''), REPLICATE('0', 2));
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT
			l.Id,
			-- Stato: prima l'anomalia "Scaricato più del prodotto" (il magazzino tradizionale ha scaricato
			-- più di quanto il registro operativo alloca al lotto: il magazzino EoW prevale e non viene
			-- mai corretto in automatico), poi la capacità (solo con quantità massima impostata; il lotto EoW
			-- è una partita di produzione, gli scarichi non liberano capienza): 2 = anomalia o capacità
			-- superata, 1 = lotto pieno o capacità residua sotto il 30% della quantità massima, 0 = OK
			StatoValore = CASE
				WHEN s.Giacenza < 0 THEN 2
				WHEN l.QuantitaMax IS NULL THEN 0
				WHEN c.QuantitaAllocata > l.QuantitaMax THEN 2
				WHEN l.QuantitaMax - c.QuantitaAllocata < l.QuantitaMax * 0.3 THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN s.Giacenza < 0
					THEN 'Scaricato più del prodotto: prodotti ' + FORMAT(s.Prodotta, 'N2', 'it-IT') + ' kg, scaricati '
						+ FORMAT(s.Scaricata, 'N2', 'it-IT') + ' kg dal magazzino'
				WHEN l.QuantitaMax IS NULL THEN 'OK'
				WHEN c.QuantitaAllocata > l.QuantitaMax
					THEN 'Quantità massima superata di ' + FORMAT(c.QuantitaAllocata - l.QuantitaMax, 'N2', 'it-IT') + ' kg: allocati '
						+ FORMAT(c.QuantitaAllocata, 'N2', 'it-IT') + ' kg su ' + FORMAT(l.QuantitaMax, 'N2', 'it-IT') + ' kg'
				WHEN c.QuantitaAllocata = l.QuantitaMax THEN 'Lotto pieno: disponibilità esaurita'
				WHEN l.QuantitaMax - c.QuantitaAllocata < l.QuantitaMax * 0.3
					THEN 'Disponibilità sotto il 30%: ' + FORMAT(l.QuantitaMax - c.QuantitaAllocata, 'N2', 'it-IT') + ' kg su '
						+ FORMAT(l.QuantitaMax, 'N2', 'it-IT') + ' kg'
				ELSE 'OK'
			END,
			NumeroRegistrazioni = ISNULL(q.NumeroRegistrazioni, 0),
			l.Nome,
			MaterialeNome = m.Nome,
			MagazzinoNome = g.Nome,
			l.DataApertura,
			l.DataChiusura,
			l.QuantitaMax,
			QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0),
			CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAllocata, 0) END,
			Disabilitato = ISNULL(l.Disabilitato, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
			LEFT JOIN dbo.tblEoWMagazzini g ON l.IdMagazzino = g.Id
			OUTER APPLY (
				-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
				-- mantiene le sue quote per un eventuale ripristino, ma non conta più
				SELECT
					QuantitaAllocata = SUM(r.Quantita),
					NumeroRegistrazioni = COUNT(DISTINCT r.IdRegistrazione)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
				WHERE
					r.IdLotto = l.Id
					AND rr.Lock < 2
			) q
					CROSS APPLY (SELECT QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0)) c
					CROSS APPLY dbo.ufnEoWLotti_get_Saldo(l.Id) s
		WHERE
			l.Lock = 0
			AND l.IdSede = @idSede
			AND
				(
				@IdMagazzino IS NULL
				OR l.IdMagazzino = @IdMagazzino
				)
			AND
				(
				@IdMateriale IS NULL
				OR l.IdMateriale = @IdMateriale
				)
			AND
				(
				@Aperto IS NULL
				OR
					(
					@Aperto = 1
					AND l.DataChiusura IS NULL
					)
				OR
					(
					@Aperto = 0
					AND l.DataChiusura IS NOT NULL
					)
				)
			AND
				(
				@Disabilitato IS NULL
				OR ISNULL(l.Disabilitato, 0) = @Disabilitato
				)
			AND
				(
				@DataAperturaDa IS NULL
				OR l.DataApertura >= @DataAperturaDa
				)
			AND
				(
				@DataAperturaA IS NULL
				OR l.DataApertura <= @DataAperturaA
				)
			AND
				(
				@Search IS NULL
				OR l.Nome LIKE '%' + @Search + '%'
				)
		ORDER BY l.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWGiacenze_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Vista NOT IN ('L', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve essere L (Lotto) o M (Magazzino)';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Giacenza (coerente con Rifiuti/Giacenze): Quantita = quanto c'è oggi nel lotto, cioè le
		-- quote di registrazioni M attive (Lock < 2: una registrazione eliminata mantiene le sue
		-- quote per un eventuale ripristino, ma non conta più) meno gli scarichi dei movimenti di
		-- magazzino confermati; solo le righe con giacenza diversa da 0: una giacenza negativa è
		-- l'anomalia "Scaricato più del prodotto" (il magazzino EoW deriva dal registro operativo e
		-- prevale sul magazzino tradizionale, non viene mai corretto in automatico). GiacenzaGiorni = giorni dalla
		-- prima registrazione M del lotto. La capacità residua resta riferita alla produzione
		-- (QuantitaMax - quantità allocata): il lotto EoW è una partita di produzione, gli
		-- scarichi non liberano capienza.
		IF @Vista = 'L'
		BEGIN
			SELECT
				l.Id,
				-- 2 = anomalia (scaricato più del prodotto), 1 = lotto pieno (la produzione allocata ha
				-- raggiunto la quantità massima), 0 = OK
				StatoValore = CASE
					WHEN ISNULL(q.QuantitaAllocata, 0) - ISNULL(sc.Scaricata, 0) < 0 THEN 2
					WHEN l.QuantitaMax IS NOT NULL AND ISNULL(q.QuantitaAllocata, 0) >= l.QuantitaMax THEN 1
					ELSE 0
				END,
				StatoDescrizione = CASE
					WHEN ISNULL(q.QuantitaAllocata, 0) - ISNULL(sc.Scaricata, 0) < 0
						THEN 'Scaricato più del prodotto: prodotti ' + FORMAT(ISNULL(q.QuantitaAllocata, 0), 'N2', 'it-IT') + ' kg, scaricati '
							+ FORMAT(ISNULL(sc.Scaricata, 0), 'N2', 'it-IT') + ' kg dal magazzino'
					WHEN l.QuantitaMax IS NOT NULL AND ISNULL(q.QuantitaAllocata, 0) >= l.QuantitaMax THEN 'Lotto pieno: disponibilità esaurita'
					ELSE 'OK'
				END,
				l.Nome,
				MaterialeNome = m.Nome,
				l.QuantitaMax,
				QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0),
				Quantita = ISNULL(q.QuantitaAllocata, 0) - ISNULL(sc.Scaricata, 0),
				GiacenzaGiorni = DATEDIFF(DAY, q.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAllocata, 0) END,
				CarichiNumero = ISNULL(q.CarichiNumero, 0),
				RowsCount = COUNT(*) OVER ()
			FROM
				dbo.tblEoWLotti l
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
				LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
				OUTER APPLY (
					SELECT
						QuantitaAllocata = SUM(r.Quantita),
						CarichiNumero = COUNT(*),
						PrimaData = MIN(rr.[Data])
					FROM
						dbo.tblEoWLottiRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
					WHERE
						r.IdLotto = l.Id
						AND rr.Lock < 2
				) q
						OUTER APPLY (
					SELECT Scaricata = SUM(rs.Quantita)
					FROM
						dbo.tblMagazziniMovimentiRigheEoWLotti rs
						INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rs.Id = rg.Id
						INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
					WHERE
						rs.IdLotto = l.Id
						AND rg.Lock = 0
						AND ms.Lock = 0
						) sc
			WHERE
				l.Lock = 0
				AND l.IdSede = @idSede
				AND
					(
					@Search IS NULL
					OR l.Nome LIKE '%' + @Search + '%'
					)
				AND ISNULL(q.QuantitaAllocata, 0) - ISNULL(sc.Scaricata, 0) <> 0
			ORDER BY l.Nome
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
			OPTION (RECOMPILE);
		END
		ELSE
		BEGIN
			SELECT
				g.Id,
				-- 2 = almeno un lotto del magazzino in anomalia (nella somma un lotto negativo resterebbe
				-- nascosto dagli altri)
				StatoValore = IIF(ISNULL(an.LottiAnomali, 0) > 0, 2, 0),
				StatoDescrizione = IIF(ISNULL(an.LottiAnomali, 0) > 0,
					'Scaricato più del prodotto in ' + CAST(an.LottiAnomali AS VARCHAR(10)) + IIF(an.LottiAnomali = 1, ' lotto', ' lotti'),
					'OK'),
				g.Nome,
				MaterialeNome = CAST(NULL AS VARCHAR(100)),
				QuantitaMax = CAST(NULL AS DECIMAL(18, 2)),
				QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0),
				Quantita = ISNULL(q.QuantitaAllocata, 0) - ISNULL(sc.Scaricata, 0),
				GiacenzaGiorni = DATEDIFF(DAY, q.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CAST(NULL AS DECIMAL(18, 2)),
				CarichiNumero = ISNULL(q.CarichiNumero, 0),
				RowsCount = COUNT(*) OVER ()
			FROM
				dbo.tblEoWMagazzini g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
				OUTER APPLY (
					SELECT
						QuantitaAllocata = SUM(r.Quantita),
						CarichiNumero = COUNT(*),
						PrimaData = MIN(rr.[Data])
					FROM
						dbo.tblEoWLotti l
						INNER JOIN dbo.tblEoWLottiRifiutiRegistrazioni r ON r.IdLotto = l.Id
						INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
					WHERE
						l.IdMagazzino = g.Id
						AND rr.Lock < 2
				) q
						OUTER APPLY (
					SELECT Scaricata = SUM(rs.Quantita)
					FROM
						dbo.tblEoWLotti l
						INNER JOIN dbo.tblMagazziniMovimentiRigheEoWLotti rs ON rs.IdLotto = l.Id
						INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rs.Id = rg.Id
						INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
					WHERE
						l.IdMagazzino = g.Id
						AND rg.Lock = 0
						AND ms.Lock = 0
						) sc
						OUTER APPLY (
					SELECT LottiAnomali = COUNT(*)
					FROM
						dbo.tblEoWLotti l
						CROSS APPLY dbo.ufnEoWLotti_get_Saldo(l.Id) sl
					WHERE
						l.IdMagazzino = g.Id
						AND l.Lock = 0
						AND sl.Giacenza < 0
						) an
			WHERE
				g.Lock = 0
				AND g.IdSede = @idSede
				AND
					(
					@Search IS NULL
					OR g.Nome LIKE '%' + @Search + '%'
					)
				AND
					(
					ISNULL(q.QuantitaAllocata, 0) - ISNULL(sc.Scaricata, 0) <> 0
					OR ISNULL(an.LottiAnomali, 0) > 0
					)
			ORDER BY g.Nome
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
			OPTION (RECOMPILE);
		END

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLottiRifiutiRegistrazioni_ins
	@IdRegistrazione CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@Quantita DECIMAL(18, 2) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdLotto non può essere vuoto';
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
			SET @returnMessage = 'La quantità deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati della registrazione (deve essere causale M, cioè
		-- tblRifiutiOperazioni.IsMateriale = 1 - vedi feedback_rentri_codice_lookup_pattern,
		-- mai confrontare IdOperazione con un letterale hardcoded)
		DECLARE @idSedeRegistrazione CHAR(16);
		DECLARE @idMovimento CHAR(16);
		DECLARE @idMaterialeRegistrazione CHAR(2);
		SELECT
			@idSedeRegistrazione = g.IdSede,
			@idMovimento = m.Id,
			@idMaterialeRegistrazione = r.IdMateriale
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			r.Id = @IdRegistrazione
			AND r.Lock < 2
			AND o.IsMateriale = 1;

		IF @idSedeRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata, non di causale materiale prodotto, o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idMaterialeRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non ha un materiale prodotto valorizzato';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica o annullamento non è un movimento reale: non riceve quote EoW
		IF EXISTS (SELECT 1
		FROM dbo.viewRifiutiRegistrazioniEffettive
		WHERE
			Id = @IdRegistrazione
			AND IsRettifica = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può ricevere quote EoW';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati del lotto
		DECLARE @idSedeLotto CHAR(16);
		DECLARE @idMaterialeLotto CHAR(2);
		DECLARE @dataChiusuraLotto DATE;
		DECLARE @disabilitatoLotto BIT;
		DECLARE @quantitaMaxLotto DECIMAL(18, 2);
		SELECT
			@idSedeLotto = l.IdSede,
			@idMaterialeLotto = l.IdMateriale,
			@dataChiusuraLotto = l.DataChiusura,
			@disabilitatoLotto = l.Disabilitato,
			@quantitaMaxLotto = l.QuantitaMax
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
		WHERE
			l.Id = @IdLotto
			AND l.Lock = 0;

		IF @idSedeLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lotto non trovato o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idSedeLotto <> @idSedeRegistrazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto selezionato non appartiene alla sede della registrazione';
			GOTO BRANCH_END;
		END

		IF @idMaterialeLotto <> @idMaterialeRegistrazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il materiale del lotto non coincide con il materiale della registrazione';
			GOTO BRANCH_END;
		END

		IF @dataChiusuraLotto IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto è chiuso, non può ricevere nuove quantità';
			GOTO BRANCH_END;
		END

		IF ISNULL(@disabilitatoLotto, 0) = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto è disabilitato, non può ricevere nuove quantità';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Lock in ordine stabile (sempre Lotto, poi Movimento) per evitare deadlock con
			-- esecuzioni concorrenti che toccano insiemi di lotti/registrazioni sovrapposti.
			DECLARE @lockRow CHAR(16);
			SELECT @lockRow = Id
			FROM dbo.tblEoWLotti WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @IdLotto;

			DECLARE @quantitaAllocataLotto DECIMAL(18, 2) = (
				-- Capienza occupata solo dalle quote di registrazioni attive (Lock < 2)
				SELECT SUM(q.Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni q INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id
				WHERE
					q.IdLotto = @IdLotto
					AND rr.Lock < 2
			);
			IF @quantitaMaxLotto IS NOT NULL AND ISNULL(@quantitaAllocataLotto, 0) + @Quantita > @quantitaMaxLotto
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la disponibilità del lotto';
				GOTO BRANCH_END;
			END

			SELECT @lockRow = Id
			FROM dbo.tblRifiutiMovimenti WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @idMovimento;

			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			DECLARE @quantitaMovimento DECIMAL(18, 2) = (SELECT Quantita
			FROM dbo.viewRifiutiRegistrazioniEffettive
			WHERE Id = @IdRegistrazione);
			DECLARE @quantitaAllocataRegistrazione DECIMAL(18, 2) = (
				SELECT SUM(Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdRegistrazione = @IdRegistrazione);
			IF ISNULL(@quantitaAllocataRegistrazione, 0) + @Quantita > ISNULL(@quantitaMovimento, 0)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la quantità residua della registrazione';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblEoWLottiRifiutiRegistrazioni
			WHERE
				IdRegistrazione = @IdRegistrazione
				AND IdLotto = @IdLotto
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Questo lotto è già associato alla registrazione: modificare la quantità esistente';
				GOTO BRANCH_END;
			END

			-- Pos = ordine di riempimento: se la quantita' operativa della M scende, le allocazioni si riducono
			-- partendo dall'ultimo lotto riempito (uspEoWLottiRifiutiRegistrazioni_upd_Allinea)
			INSERT dbo.tblEoWLottiRifiutiRegistrazioni (IdRegistrazione, IdLotto, Quantita, Pos)
			SELECT
				@IdRegistrazione,
				@IdLotto,
				@Quantita,
				ISNULL(MAX(Pos), 0) + 1
			FROM dbo.tblEoWLottiRifiutiRegistrazioni
			WHERE IdRegistrazione = @IdRegistrazione;

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLottiRifiutiRegistrazioni_upd
	@IdRegistrazione CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@Quantita DECIMAL(18, 2) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdLotto non può essere vuoto';
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
			SET @returnMessage = 'La quantità deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sulla registrazione (deve restare causale M, coerenza con l'insert)
		DECLARE @idMovimento CHAR(16);
		SELECT @idMovimento = m.Id
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			r.Id = @IdRegistrazione
			AND r.Lock < 2
			AND o.IsMateriale = 1;

		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata, non di causale materiale prodotto, o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sul lotto
		DECLARE @quantitaMaxLotto DECIMAL(18, 2);
		SELECT @quantitaMaxLotto = l.QuantitaMax
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
		WHERE l.Id = @IdLotto;

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWLottiRifiutiRegistrazioni
		WHERE
			IdRegistrazione = @IdRegistrazione
			AND IdLotto = @IdLotto
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Associazione non trovata';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Lock in ordine stabile (sempre Lotto, poi Movimento), stesso ordine di _ins
			DECLARE @lockRow CHAR(16);
			SELECT @lockRow = Id
			FROM dbo.tblEoWLotti WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @IdLotto;

			DECLARE @quantitaAllocataLotto DECIMAL(18, 2) = (
				-- Capienza occupata solo dalle quote di registrazioni attive (Lock < 2)
				SELECT SUM(q.Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni q INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id
				WHERE
					q.IdLotto = @IdLotto
					AND rr.Lock < 2
					AND q.IdRegistrazione <> @IdRegistrazione
			);
			IF @quantitaMaxLotto IS NOT NULL AND ISNULL(@quantitaAllocataLotto, 0) + @Quantita > @quantitaMaxLotto
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la disponibilità del lotto';
				GOTO BRANCH_END;
			END

			SELECT @lockRow = Id
			FROM dbo.tblRifiutiMovimenti WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @idMovimento;

			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			DECLARE @quantitaMovimento DECIMAL(18, 2) = (SELECT Quantita
			FROM dbo.viewRifiutiRegistrazioniEffettive
			WHERE Id = @IdRegistrazione);
			DECLARE @quantitaAllocataRegistrazione DECIMAL(18, 2) = (
				SELECT SUM(Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE
					IdRegistrazione = @IdRegistrazione
					AND IdLotto <> @IdLotto
			);
			IF ISNULL(@quantitaAllocataRegistrazione, 0) + @Quantita > ISNULL(@quantitaMovimento, 0)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la quantità residua della registrazione';
				GOTO BRANCH_END;
			END

			-- Quantita' decisa a mano: l'allocazione diventa manuale (IdAllocazioneTipo NULL), una riduzione
			-- automatica successiva non la tratta piu' come parte di un'allocazione in percentuale/priorita'
			UPDATE dbo.tblEoWLottiRifiutiRegistrazioni
			SET
				Quantita = @Quantita,
				IdAllocazioneTipo = NULL
			WHERE
				IdRegistrazione = @IdRegistrazione
				AND IdLotto = @IdLotto;

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
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_esegui
	@IdRegistrazione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistrazione = NULLIF(LTRIM(RTRIM(@IdRegistrazione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazione non può essere vuoto';
			GOTO BRANCH_END;
		END
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati della registrazione (deve essere causale M)
		DECLARE @idSedeRegistrazione CHAR(16);
		DECLARE @idMovimento CHAR(16);
		DECLARE @idMaterialeRegistrazione CHAR(2);
		SELECT
			@idSedeRegistrazione = g.IdSede,
			@idMovimento = m.Id,
			@idMaterialeRegistrazione = r.IdMateriale
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			r.Id = @IdRegistrazione
			AND r.Lock < 2
			AND o.IsMateriale = 1;

		IF @idSedeRegistrazione IS NULL OR @idMaterialeRegistrazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata, non di causale materiale prodotto, o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica o annullamento non è un movimento reale: non riceve quote EoW
		IF EXISTS (SELECT 1
		FROM dbo.viewRifiutiRegistrazioniEffettive
		WHERE
			Id = @IdRegistrazione
			AND IsRettifica = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può ricevere quote EoW';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati dell'allocazione
		DECLARE @idSedeAllocazione CHAR(16);
		DECLARE @idAllocazioneTipo CHAR(1);
		SELECT
			@idSedeAllocazione = c.IdSede,
			@idAllocazioneTipo = c.IdAllocazioneTipo
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE
			c.Id = @Id
			AND c.Lock = 0;

		IF @idSedeAllocazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allocazione non trovata o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idSedeAllocazione <> @idSedeRegistrazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''allocazione selezionata non appartiene alla sede della registrazione';
			GOTO BRANCH_END;
		END

		IF @idAllocazioneTipo = 'M'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questo tipo di allocazione non supporta l''esecuzione automatica';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Lock di tutti i lotti coinvolti in un unico statement (ordine di acquisizione stabile,
			-- via index seek sulla PK, per ridurre il rischio di deadlock con esecuzioni concorrenti
			-- su insiemi di lotti sovrapposti), poi del movimento - stesso ordine di
			-- uspEoWLottiRifiutiRegistrazioni_ins.
			DECLARE @lockRow CHAR(16);
			SELECT @lockRow = l.Id
			FROM dbo.tblEoWLotti l WITH (UPDLOCK, HOLDLOCK)
			WHERE l.Id IN (SELECT IdLotto FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id)
			ORDER BY l.Id;

			SELECT @lockRow = Id
			FROM dbo.tblRifiutiMovimenti WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @idMovimento;

			-- Righe di configurazione + quantità già allocata ad ognuno dei lotti coinvolti, lette
			-- sotto lock (fonte unica di verità, nessun ricalcolo su dati stimati prima del lock)
			DECLARE @righe TABLE (IdLotto CHAR(16) PRIMARY KEY, Valore DECIMAL(18, 2) NULL, QuantitaMax DECIMAL(18, 2) NULL, QuantitaAllocata DECIMAL(18, 2) NOT NULL);
			INSERT INTO @righe (IdLotto, Valore, QuantitaMax, QuantitaAllocata)
			SELECT
				la.IdLotto,
				la.Valore,
				l.QuantitaMax,
				QuantitaAllocata = ISNULL((SELECT SUM(r.Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni r INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
				WHERE
					r.IdLotto = la.IdLotto
					AND rr.Lock < 2
				), 0)
			FROM
				dbo.tblEoWLottiAllocazioni la
				INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
			WHERE la.IdAllocazione = @Id;

			IF NOT EXISTS (SELECT 1
			FROM @righe)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'L''allocazione non ha lotti configurati';
				GOTO BRANCH_END;
			END

			-- Lotti non utilizzabili: chiusi (data di chiusura impostata), disabilitati o eliminati,
			-- come per l'attribuzione manuale (uspEoWLottiRifiutiRegistrazioni_ins). Con il tipo C
			-- (priorità/capacità) vengono saltati come i lotti pieni e si passa al successivo; con
			-- U e P (lotto unico / percentuale) non c'è un lotto successivo: errore bloccante.
			DECLARE @lottoNonUtilizzabile VARCHAR(50) = (
				SELECT TOP 1 l.Nome
				FROM
					@righe r
					INNER JOIN dbo.tblEoWLotti l ON r.IdLotto = l.Id
				WHERE
					l.Lock <> 0
					OR l.DataChiusura IS NOT NULL
					OR ISNULL(l.Disabilitato, 0) = 1
				ORDER BY l.Nome
			);
			IF @lottoNonUtilizzabile IS NOT NULL AND @idAllocazioneTipo IN ('U', 'P')
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Il lotto ' + @lottoNonUtilizzabile + ' dell''allocazione è chiuso o disabilitato';
				GOTO BRANCH_END;
			END
			IF @lottoNonUtilizzabile IS NOT NULL
			BEGIN
				DELETE r
				FROM
					@righe r
					INNER JOIN dbo.tblEoWLotti l ON r.IdLotto = l.Id
				WHERE
					l.Lock <> 0
					OR l.DataChiusura IS NOT NULL
					OR ISNULL(l.Disabilitato, 0) = 1;

				IF NOT EXISTS (SELECT 1
				FROM @righe)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Tutti i lotti dell''allocazione sono chiusi o disabilitati';
					GOTO BRANCH_END;
				END
			END

			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			DECLARE @quantitaMovimento DECIMAL(18, 2) = (SELECT Quantita
			FROM dbo.viewRifiutiRegistrazioniEffettive
			WHERE Id = @IdRegistrazione);
			DECLARE @quantitaAllocataRegistrazione DECIMAL(18, 2) = ISNULL((
				SELECT SUM(Quantita)
				FROM dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdRegistrazione = @IdRegistrazione), 0);
			DECLARE @quantitaDaAllocare DECIMAL(18, 2) = ISNULL(@quantitaMovimento, 0) - @quantitaAllocataRegistrazione;

			IF @quantitaDaAllocare <= 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Non c''è quantità residua da allocare per questa registrazione';
				GOTO BRANCH_END;
			END

			-- Piano di ripartizione calcolato per tipo (U = Lotto unico, P = Percentuale, C = Priorità/Capacità)
			DECLARE @piano TABLE (IdLotto CHAR(16) PRIMARY KEY, Quantita DECIMAL(18, 2) NOT NULL);

			IF @idAllocazioneTipo = 'U'
			BEGIN
				IF (SELECT COUNT(*)
				FROM @righe) <> 1
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Un''allocazione di tipo Lotto unico deve avere esattamente un lotto configurato';
					GOTO BRANCH_END;
				END

				INSERT INTO @piano (IdLotto, Quantita)
				SELECT IdLotto, @quantitaDaAllocare
				FROM @righe;
			END
			ELSE IF @idAllocazioneTipo = 'P'
			BEGIN
				DECLARE @sommaPercentuali DECIMAL(18, 2) = (SELECT SUM(ISNULL(Valore, 0))
				FROM @righe);
				IF @sommaPercentuali > 100
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Le percentuali configurate non possono superare 100';
					GOTO BRANCH_END;
				END

				-- Arrotondamento a 2 decimali per riga. Il resto viene pareggiato sull'ultimo lotto (per
				-- Id) solo se le percentuali configurate coprono l'intero 100%: in quel caso il resto è
				-- puro errore di arrotondamento da correggere. Se invece sommano a meno di 100 (allocazione
				-- volutamente parziale, es. un solo lotto al 60%), il resto è quantità non allocata per
				-- scelta e deve restare tale, non va scaricato sull'ultimo lotto.
				INSERT INTO @piano (IdLotto, Quantita)
				SELECT
					IdLotto,
					Quantita = ROUND(@quantitaDaAllocare * Valore / 100.0, 2)
				FROM @righe;

				IF @sommaPercentuali = 100
				BEGIN
					DECLARE @idUltimoLotto CHAR(16) = (SELECT TOP 1 IdLotto
					FROM @righe ORDER BY IdLotto DESC);
					DECLARE @resto DECIMAL(18, 2) = @quantitaDaAllocare - (SELECT SUM(Quantita)
					FROM @piano);
					UPDATE @piano
					SET Quantita = Quantita + @resto
					WHERE IdLotto = @idUltimoLotto;
				END
			END
			ELSE IF @idAllocazioneTipo = 'C'
			BEGIN
				-- Ripartizione greedy per priorità (Valore crescente = priorità più alta): iterazione
				-- riga per riga, nessun pattern set-based equivalente per un bin-packing sequenziale.
				DECLARE @rimanente DECIMAL(18, 2) = @quantitaDaAllocare;
				DECLARE @curIdLotto CHAR(16), @curQuantitaMax DECIMAL(18, 2), @curQuantitaAllocata DECIMAL(18, 2);

				DECLARE curRighe CURSOR LOCAL FAST_FORWARD FOR
					SELECT IdLotto, QuantitaMax, QuantitaAllocata
					FROM @righe
					ORDER BY ISNULL(Valore, 999999999), IdLotto;

				OPEN curRighe;
				FETCH NEXT
				FROM curRighe INTO @curIdLotto, @curQuantitaMax, @curQuantitaAllocata;
				WHILE @@FETCH_STATUS = 0 AND @rimanente > 0
				BEGIN
					DECLARE @capacitaResidua DECIMAL(18, 2) = CASE
						WHEN @curQuantitaMax IS NULL THEN @rimanente
						ELSE @curQuantitaMax - @curQuantitaAllocata
					END;
					IF @capacitaResidua > 0
					BEGIN
						DECLARE @presoQui DECIMAL(18, 2) = IIF(@capacitaResidua < @rimanente, @capacitaResidua, @rimanente);
						INSERT INTO @piano (IdLotto, Quantita) VALUES (@curIdLotto, @presoQui);
						SET @rimanente -= @presoQui;
					END
					FETCH NEXT
					FROM curRighe INTO @curIdLotto, @curQuantitaMax, @curQuantitaAllocata;
				END
				CLOSE curRighe;
				DEALLOCATE curRighe;

				IF @rimanente > 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'La disponibilità dei lotti configurati è insufficiente per la quantità da allocare';
					GOTO BRANCH_END;
				END
			END

			-- Verifica finale capacità per riga (ridondante per U/P dove già implicito, ma protegge
			-- comunque da una configurazione QuantitaMax incoerente) e upsert nella tabella risultato
			IF EXISTS (
				SELECT 1
				FROM @piano p INNER JOIN @righe r ON p.IdLotto = r.IdLotto
				WHERE
					r.QuantitaMax IS NOT NULL
					AND r.QuantitaAllocata + p.Quantita > r.QuantitaMax
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità calcolata supera la disponibilità di uno o più lotti';
				GOTO BRANCH_END;
			END

			-- Pos = ordine di riempimento e IdAllocazioneTipo = metodo: quando la quantita' operativa della M scende,
			-- uspEoWLottiRifiutiRegistrazioni_upd_Allinea riduce partendo dall'ultima allocazione fatta rispettando
			-- il metodo (P in proporzione, C/U dall'ultimo lotto riempito). I lotti di questa esecuzione seguono
			-- quelli gia' allocati, nell'ordine di configurazione (Valore crescente = per il tipo C la priorita'
			-- con cui sono stati riempiti). Un lotto gia' allocato prende metodo e Pos di questa esecuzione
			-- (l'ultima operazione).
			DECLARE @posMax INT = ISNULL((SELECT MAX(Pos)
			FROM dbo.tblEoWLottiRifiutiRegistrazioni
			WHERE IdRegistrazione = @IdRegistrazione), 0);

			MERGE dbo.tblEoWLottiRifiutiRegistrazioni AS target
			USING (
				SELECT
					p.IdLotto,
					p.Quantita,
					Pos = @posMax + ROW_NUMBER() OVER (ORDER BY ISNULL(r.Valore, 999999999), p.IdLotto)
				FROM
					@piano p
					INNER JOIN @righe r ON p.IdLotto = r.IdLotto
			) AS source
				ON target.IdRegistrazione = @IdRegistrazione AND target.IdLotto = source.IdLotto
			WHEN MATCHED THEN
				UPDATE SET
					Quantita = target.Quantita + source.Quantita,
					Pos = source.Pos,
					IdAllocazioneTipo = @idAllocazioneTipo
			WHEN NOT MATCHED THEN
				INSERT (IdRegistrazione, IdLotto, Quantita, Pos, IdAllocazioneTipo)
				VALUES (@IdRegistrazione, source.IdLotto, source.Quantita, source.Pos, @idAllocazioneTipo);

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
