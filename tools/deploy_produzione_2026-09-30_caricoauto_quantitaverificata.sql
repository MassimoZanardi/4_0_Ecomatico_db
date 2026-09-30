-- Deploy produzione 2026-09-30: carichi automatici (M/NP da scarico I) generati senza QuantitaVerificata.
-- 1 stored procedure: uspRifiutiRegistrazioni_ins_CaricoAuto. Indipendente dal bundle eow_allineamento_registro.
-- Eseguire con: sqlcmd -S <server> -d 4_0_ecomatico -E -f 65001 -I -b -i <questo file>
-- Poi: tools\verifica_crlf_accenti.sql su tutto il DB (deve restituire 0 righe).
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
		DECLARE @quantitaOrigine DECIMAL(18, 2);
		DECLARE @isRettificaOrigine BIT;
		DECLARE @isAnnullataOrigine BIT;

		-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale,
		-- il valore operativo è quello dell'ultima rettifica confermata (annullamento operativo = 0)
		SELECT
			@idRegistro = m.IdRegistro,
			@idModello = m.IdModello,
			@data = r.[Data],
			@quantitaOrigine = v.Quantita,
			@isRettificaOrigine = v.IsRettifica,
			@isAnnullataOrigine = v.IsAnnullata
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE r.Id = @IdRegistrazioneOrigine;

		IF @idRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione di origine non trovata o non disponibile';
			GOTO BRANCH_END;
		END
		IF @isRettificaOrigine = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può generare carichi';
			GOTO BRANCH_END;
		END
		IF @isAnnullataOrigine = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione annullata non può generare carichi';
			GOTO BRANCH_END;
		END

		-- Verifica quantità già scaricata (stesso pattern di uspRifiutiRegistrazioni_upd, righe
		-- ~554-572): la somma dei carichi già generati/associati dallo scarico di origine, più
		-- questo nuovo, non può superare la quantità totale dello scarico stesso - altrimenti la
		-- quantità residua diventa negativa (bug reale trovato sui dati: scarico da 30 kg con 5
		-- carichi generati per un totale di 33,60 kg).
		DECLARE @quantitaGiaAssociata DECIMAL(18, 2) = ISNULL((
			SELECT SUM(l.Quantita)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON rp.Id = vp.Id
			WHERE
				l.Id = @IdRegistrazioneOrigine
				AND l.Quantita > 0
				AND rp.Lock < 2
				-- Un carico derivato annullato non occupa piu' la quantità dello scarico (stesso criterio di _upd)
				AND vp.IsAnnullata = 0
		), 0);

		IF @quantitaGiaAssociata + @Quantita > ISNULL(@quantitaOrigine, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità supera quella residua disponibile sulla registrazione di origine';
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
		SELECT @eerDescrizione = Descrizione
		FROM dbo.tblRifiutiEer
		WHERE Id = @idEer;
		SELECT @materialeDescrizione = Nome
		FROM dbo.tblRifiutiMateriali
		WHERE Id = @idMateriale;

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

		-- uspId_get gestisce la propria transazione internamente: chiamate FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		-- @returnId è appena stato generato in questa stessa esecuzione: non può già esistere
		-- nessuna relazione con IdParent = @returnId, la posizione è sempre 0 (stesso schema di
		-- calcolo di uspRifiutiRegistrazioni_ins_Relazione, qui degenera per costruzione).
		DECLARE @pos INT = 0;

		BEGIN TRANSACTION;

			INSERT dbo.tblRifiutiMovimenti
				(Id, IdRegistro, IdOperazione, IdEer, EerDescrizione, IdStatoFisico, IdUnitaMisura, Quantita)
			VALUES
				(@idMovimento, @idRegistro, @idOperazioneDestinazione, @idEer, @eerDescrizione, @idStatoFisico, @idUnitaMisura, @Quantita);

			INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Pos)
			VALUES (@idMovimento, @idAutorizzazioneProduttoreDetentore, 0);

			-- QuantitaVerificata non valorizzata: un carico generato non ha esito da verificare e
			-- uspRifiutiRegistrazioni_upd la riporterebbe comunque a NULL al primo salvataggio (uguale alla
			-- quantita' / causale senza esito); il payload RENTRI usa ISNULL(QuantitaVerificata, Quantita)
			INSERT dbo.tblRifiutiRegistrazioni
				(Id, IdMovimento, Operazione, [Data], Numero, IdMateriale, MaterialeDescrizione, Lock)
			VALUES
				(@returnId, @idMovimento, @operazioneGruppo, @data, @numero, @idMateriale, @materialeDescrizione, 0);

			-- Relazione mancava del tutto, il carico auto restava senza legame con lo scarico che lo ha
			-- generato. Verificato sui dati reali (registrazione Id=65bddb1e1fe94a5a, carico K/M) contro
			-- una relazione creata manualmente: Id = la registrazione di SCARICO (qui l'origine 'I'),
			-- IdParent = la registrazione di CARICO (qui il nuovo @returnId) - il verso opposto a quanto
			-- inserito nel primo tentativo. Operazione = @operazioneGruppo, l'Operazione del CARICO
			-- (sempre 'C' per NP/M, già calcolata sopra) - coerente perché ora è anche l'Operazione
			-- propria di IdParent, stesso schema di uspRifiutiRegistrazioni_ins_Relazione (Operazione =
			-- Operazione del padre).
			-- Il padre (qui il nuovo carico, non l'origine) resta comunque a Lock=0: è la registrazione
			-- appena creata in questa stessa transazione, non passa mai da "da confermare".
			INSERT dbo.tblRifiutiRegistrazioniRelazioni (Id, IdParent, Operazione, Quantita, Pos)
			VALUES (@IdRegistrazioneOrigine, @returnId, @operazioneGruppo, @Quantita, @pos);

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
GO
