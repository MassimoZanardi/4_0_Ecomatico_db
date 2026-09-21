SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_ins_CaricoAuto]
	@IdSessione CHAR(16) = NULL,
	@IdRegistrazioneOrigine CHAR(16) = NULL,
	@IdRegistrazioneAuto CHAR(16) = NULL,
	@Quantita DECIMAL(18, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistrazioneOrigine = NULLIF(LTRIM(RTRIM(@IdRegistrazioneOrigine)), '');
		SET @IdRegistrazioneAuto = NULLIF(LTRIM(RTRIM(@IdRegistrazioneAuto)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistrazioneOrigine IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazioneOrigine non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistrazioneAuto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazioneAuto non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NULL OR @Quantita <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RRG', @Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Registrazione di origine (scarico 'I'): titolarità + dati da ereditare (stessa Sede/Data/Registro).
		-- Il produttore/detentore NON viene dalla registrazione di origine (uno scarico a trattamento
		-- interno non ne ha uno), ma dal Modello usato per configurare la registrazione automatica.
		DECLARE @idRegistro CHAR(16);
		DECLARE @idModello CHAR(16);
		DECLARE @data DATE;

		SELECT
			@idRegistro = m.IdRegistro,
			@idModello = m.IdModello,
			@data = r.[Data]
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE r.Id = @IdRegistrazioneOrigine;

		IF @idRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione di origine non trovata o non disponibile';
			GOTO BRANCH_END;
		END

		DECLARE @idAutorizzazioneProduttoreDetentore CHAR(16);
		SELECT @idAutorizzazioneProduttoreDetentore = IdAutorizzazioneProduttoreDetentore
		FROM dbo.tblRifiutiModelli
		WHERE Id = @idModello;

		IF @idAutorizzazioneProduttoreDetentore IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il modello non ha impostato il produttore o detentore, obbligatorio per le registrazioni automatiche';
			GOTO BRANCH_END;
		END

		-- Riga di configurazione (tblRifiutiModelliRegistrazioniAuto): deve appartenere allo stesso
		-- Modello della registrazione di origine, non a un Modello arbitrario passato dal chiamante.
		DECLARE @idEer CHAR(6);
		DECLARE @idMateriale CHAR(2);
		DECLARE @idStatoFisico CHAR(1);
		DECLARE @idUnitaMisura CHAR(2);

		SELECT
			@idEer = ra.IdEer,
			@idMateriale = ra.IdMateriale,
			@idStatoFisico = ra.IdStatoFisico,
			@idUnitaMisura = ra.IdUnitaMisura
		FROM dbo.tblRifiutiModelliRegistrazioniAuto ra
		WHERE
			ra.Id = @IdRegistrazioneAuto
			AND ra.IdModello = @idModello
			AND ra.Lock = 0;

		IF @idEer IS NULL AND @idMateriale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione automatica non trovata o non appartenente al modello di origine';
			GOTO BRANCH_END;
		END

		-- Operazione destinazione via lookup su Codice (mai sul singolo carattere Id, che non è
		-- mnemonico: Id='M' ha Codice='NP', Id='K' ha Codice='M'). @operazioneGruppo è la colonna
		-- 'Operazione' (raggruppamento S/C/X usato da tblRifiutiRegistrazioni.Operazione), diversa
		-- dall'Id specifico che invece va su tblRifiutiMovimenti.IdOperazione — stesso schema di
		-- uspRifiutiRegistrazioni_ins (@mOperazione vs @mIdOperazione).
		DECLARE @idOperazioneDestinazione CHAR(1);
		DECLARE @operazioneGruppo CHAR(1);
		SELECT
			@idOperazioneDestinazione = Id,
			@operazioneGruppo = Operazione
		FROM dbo.tblRifiutiOperazioni
		WHERE Codice = IIF(@idMateriale IS NOT NULL, 'M', 'NP');

		IF @idOperazioneDestinazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Operazione di destinazione non configurata';
			GOTO BRANCH_END;
		END

		DECLARE @eerDescrizione VARCHAR(200);
		DECLARE @materialeDescrizione VARCHAR(200);
		SELECT @eerDescrizione = Descrizione FROM dbo.tblRifiutiEer WHERE Id = @idEer;
		SELECT @materialeDescrizione = Nome FROM dbo.tblRifiutiMateriali WHERE Id = @idMateriale;

		-- Prossimo numero disponibile per Registro/anno (stesso schema di uspRifiutiRegistrazioni_upd,
		-- ramo di rinumerazione: 1 + MAX(Numero) tra le registrazioni confermate/bozza dell'anno).
		DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@data), 1, 1);
		DECLARE @annoFine DATE = DATEFROMPARTS(YEAR(@data) + 1, 1, 1);
		DECLARE @numero INT = 1 + ISNULL((
			SELECT MAX(r.Numero)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			WHERE
				r.Lock < 2
				AND m.IdRegistro = @idRegistro
				AND r.[Data] >= @annoInizio
				AND r.[Data] < @annoFine
		), 0);

		DECLARE @idMovimento CHAR(16);

		-- Posizione della nuova relazione tra le eventuali altre già esistenti sotto lo stesso padre
		-- (stesso schema di uspRifiutiRegistrazioni_ins_Relazione)
		DECLARE @pos INT;
		SELECT @pos = ISNULL(MAX(s.Pos), -1) + 1
		FROM dbo.tblRifiutiRegistrazioniRelazioni s
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON s.Id = r.Id
		WHERE
			s.IdParent = @IdRegistrazioneOrigine
			AND r.Lock < 2;

		-- uspId_get gestisce la propria transazione internamente: chiamate FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;

			INSERT dbo.tblRifiutiMovimenti
				(Id, IdRegistro, IdOperazione, IdEer, EerDescrizione, IdStatoFisico, IdUnitaMisura, Quantita)
			VALUES
				(@idMovimento, @idRegistro, @idOperazioneDestinazione, @idEer, @eerDescrizione, @idStatoFisico, @idUnitaMisura, @Quantita);

			INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Pos)
			VALUES (@idMovimento, @idAutorizzazioneProduttoreDetentore, 0);

			INSERT dbo.tblRifiutiRegistrazioni
				(Id, IdMovimento, Operazione, [Data], Numero, QuantitaVerificata, IdMateriale, MaterialeDescrizione, Lock)
			VALUES
				(@returnId, @idMovimento, @operazioneGruppo, @data, @numero, @Quantita, @idMateriale, @materialeDescrizione, 0);

			-- Relazione carico(figlio, il nuovo @returnId)/scarico(padre, la registrazione di origine) -
			-- mancava del tutto, il carico auto restava senza legame con lo scarico che lo ha generato.
			-- Operazione = @operazioneGruppo, l'Operazione del FIGLIO (sempre 'C' per NP/M, già
			-- calcolata sopra), non quella del padre (che essendo uno scarico 'I' sarebbe 'S').
			-- Il padre resta volutamente a Lock=0 (non 1 "da confermare" come nel percorso manuale di
			-- uspRifiutiRegistrazioni_ins_Relazione): è già stato confermato nello stesso salvataggio
			-- che genera i carichi automatici, riportarlo a "da confermare" vanificherebbe il flusso a
			-- salvataggio unico voluto per questa funzionalità.
			INSERT dbo.tblRifiutiRegistrazioniRelazioni (Id, IdParent, Operazione, Quantita, Pos)
			VALUES (@returnId, @IdRegistrazioneOrigine, @operazioneGruppo, @Quantita, @pos);

			INSERT dbo.tblRifiutiRegistrazioniEtichette (Id, IdEtichetta)
			SELECT @returnId, IdEtichetta
			FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette
			WHERE Id = @IdRegistrazioneAuto;

			UPDATE dbo.tblRifiutiRegistrazioni
			SET Etichette = dbo.ufnRifiutiRegistrazioni_get_Etichette(Id)
			WHERE Id = @returnId;

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
