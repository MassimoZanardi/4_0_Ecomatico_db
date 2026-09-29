-- Deploy produzione 2026-09-29, rettifiche RENTRI passi 4-5 (1 funzione + 6 stored procedure):
-- repo DB da deployed-prod b378629 a ac0d0ed.
-- - Limiti rifiuti: verifica sui valori effettivi (viewRifiutiRegistrazioniEffettive), registrazioni di rettifica escluse
-- - Carichi automatici da scarico: quantita' origine effettiva, blocco su origine di rettifica o annullata,
--   carichi derivati annullati esclusi
-- - EoW: tetto delle quote sulla quantita' effettiva, niente quote su registrazioni di rettifica,
--   elenchi Carichi/Registrazioni con quantita' complessiva effettiva
-- Richiede viewRifiutiRegistrazioniEffettive e ufnRifiutiRegistrazioni_get_RettificaOperativa (gia' in produzione).
-- Eseguire con: sqlcmd -S <server> -d 4_0_ecomatico -E -f 65001 -i <questo file>
-- ============================================================ ufnRifiutiLimiti_get_Verifica_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnRifiutiLimiti_get_Verifica_List] (
	@IdSede CHAR(16) = NULL)
RETURNS TABLE
AS
RETURN
(
	-- Righe di verifica effettive per ciascun limite: un limite con IdRegistro esplicito
	-- produce sempre una sola riga (verifica ristretta a quel registro); un limite senza
	-- registro produce una riga aggregata di sede (VerificaPerRegistro=0) oppure una riga
	-- per ciascun registro della sede, indipendente (VerificaPerRegistro=1, default).
	WITH LimitiEspansi AS (
		SELECT
			IdLimite = c.Id,
			IdRegistroVerifica = c.IdRegistro
		FROM dbo.tblRifiutiLimiti c
		WHERE c.IdRegistro IS NOT NULL

		UNION ALL

		SELECT
			IdLimite = c.Id,
			IdRegistroVerifica = NULL
		FROM dbo.tblRifiutiLimiti c
		WHERE
			c.IdRegistro IS NULL
			AND ISNULL(c.VerificaPerRegistro, 1) = 0

		UNION ALL

		SELECT
			IdLimite = c.Id,
			IdRegistroVerifica = r.Id
		FROM
			dbo.tblRifiutiLimiti c
			INNER JOIN dbo.tblRifiutiRegistri r ON r.IdSede = c.IdSede AND r.Lock = 0
		WHERE
			c.IdRegistro IS NULL
			AND ISNULL(c.VerificaPerRegistro, 1) = 1
	),
	-- Stessa logica di quantità residua di uspRifiutiGiacenze_get_Quantita, non ristretta
	-- a un singolo registro/EER/stato fisico: il filtro per limite avviene nelle APPLY sotto.
	-- Quantità, EER e unità di misura sono i valori effettivi (viewRifiutiRegistrazioniEffettive),
	-- mai quelli dell'originale: una rettifica non modifica la registrazione originale.
	QuantitaAssegnata AS (
		SELECT
			l.Id,
			Quantita = SUM(l.Quantita)
		FROM
			dbo.tblRifiutiRegistrazioniRelazioni l
			INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON p.Id = vp.Id
		WHERE
			p.Lock = 0
			-- Uno scarico annullato ha Quantita = 0: le sue relazioni restano ma non consumano piu' il carico
			AND vp.Quantita > 0
			AND p.[Data] <= CAST(GETDATE() AS DATE)
		GROUP BY l.Id
	)
	SELECT
		c.Id,
		c.Nome,
		c.IdSede,
		c.IdRegistro,
		le.IdRegistroVerifica,
		RegistroVerificaNome = rv.Nome,
		c.IdUnitaMisura,
		c.Riferimento,
		c.Intervallo,
		c.Valore,
		ValoreAttuale = ISNULL(CASE
			WHEN c.Riferimento = 'G' AND c.IdUnitaMisura = 'GG' THEN giac.GiacenzaGiorni
			WHEN c.Riferimento = 'G' THEN giac.GiacenzaQuantita
			WHEN c.Riferimento = 'O' THEN op.OperazioniQuantita
		END, 0),
		Superato = CAST(IIF(ISNULL(CASE
			WHEN c.Riferimento = 'G' AND c.IdUnitaMisura = 'GG' THEN giac.GiacenzaGiorni
			WHEN c.Riferimento = 'G' THEN giac.GiacenzaQuantita
			WHEN c.Riferimento = 'O' THEN op.OperazioniQuantita
		END, 0) >= c.Valore, 1, 0) AS BIT)
	FROM
		dbo.tblRifiutiLimiti c
		INNER JOIN LimitiEspansi le ON le.IdLimite = c.Id
		LEFT JOIN dbo.tblRifiutiRegistri rv ON rv.Id = le.IdRegistroVerifica
		CROSS APPLY (
			SELECT
				GiacenzaQuantita = SUM(x.ResiduoUnitaMisura),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(x.DataSeResiduo), CAST(GETDATE() AS DATE))
			FROM (
				SELECT
					-- Le due espressioni portano un riferimento esterno (c.IdUnitaMisura):
					-- va isolato in una derived table prima dell'aggregazione, altrimenti
					-- SQL Server rifiuta l'aggregato per riferimento esterno misto a colonne locali.
					ResiduoUnitaMisura = CASE WHEN v.IdUnitaMisura = c.IdUnitaMisura THEN (v.Quantita - ISNULL(a.Quantita, 0)) END,
					DataSeResiduo = CASE WHEN (v.Quantita - ISNULL(a.Quantita, 0)) > 0 THEN r.[Data] END
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
					INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
					LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				WHERE
					r.Lock = 0
					AND r.[Data] <= CAST(GETDATE() AS DATE)
					AND (
						(le.IdRegistroVerifica IS NOT NULL AND m.IdRegistro = le.IdRegistroVerifica)
						OR (le.IdRegistroVerifica IS NULL AND m.IdRegistro IN (SELECT Id FROM dbo.tblRifiutiRegistri WHERE IdSede = c.IdSede AND Lock = 0))
					)
					AND v.Quantita > 0
					-- Una registrazione di rettifica o annullamento non è un movimento reale: mai in giacenza
					AND v.IsRettifica = 0
					AND (
						(ISNULL(m.IdOperazione, '') <> 'R' AND o.Operazione = 'C')
						OR (m.IdOperazione = 'R' AND o.Operazione = 'S')
					)
					AND (
						NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiLimitiEer WHERE IdLimite = c.Id)
						OR v.IdEer IN (SELECT IdEer FROM dbo.tblRifiutiLimitiEer WHERE IdLimite = c.Id)
					)
					AND (
						NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiLimitiEtichette WHERE IdLimite = c.Id)
						OR EXISTS (
							SELECT 1
							FROM dbo.tblRifiutiRegistrazioniEtichette re
							WHERE
								re.Id = r.Id
								AND re.IdEtichetta IN (SELECT IdEtichetta FROM dbo.tblRifiutiLimitiEtichette WHERE IdLimite = c.Id)
						)
					)
			) x
		) giac
		CROSS APPLY (
			SELECT
				OperazioniQuantita = SUM(x.QuantitaUnitaMisura)
			FROM (
				SELECT
					-- Riferimento esterno c.IdUnitaMisura isolato in derived table, stesso motivo di giac.
					QuantitaUnitaMisura = CASE WHEN v.IdUnitaMisura = c.IdUnitaMisura THEN v.Quantita END
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
				WHERE
					r.Lock = 0
					AND r.[Data] <= CAST(GETDATE() AS DATE)
					AND r.[Data] >= CASE c.Intervallo
						WHEN 'GG' THEN CAST(GETDATE() AS DATE)
						WHEN 'WK' THEN CAST(DATEADD(WEEK, DATEDIFF(WEEK, 0, CAST(GETDATE() AS DATE)), 0) AS DATE)
						WHEN 'MM' THEN DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
						WHEN 'YY' THEN DATEFROMPARTS(YEAR(GETDATE()), 1, 1)
					END
					AND (
						(le.IdRegistroVerifica IS NOT NULL AND m.IdRegistro = le.IdRegistroVerifica)
						OR (le.IdRegistroVerifica IS NULL AND m.IdRegistro IN (SELECT Id FROM dbo.tblRifiutiRegistri WHERE IdSede = c.IdSede AND Lock = 0))
					)
					-- Un annullamento operativo porta la quantità effettiva a 0: esclusa
					AND v.Quantita > 0
					-- Bug pre-esistente: le registrazioni di rettifica/annullamento venivano contate come operazioni
					AND v.IsRettifica = 0
					AND (
						NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiLimitiEer WHERE IdLimite = c.Id)
						OR v.IdEer IN (SELECT IdEer FROM dbo.tblRifiutiLimitiEer WHERE IdLimite = c.Id)
					)
					AND (
						NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiLimitiEtichette WHERE IdLimite = c.Id)
						OR EXISTS (
							SELECT 1
							FROM dbo.tblRifiutiRegistrazioniEtichette re
							WHERE
								re.Id = r.Id
								AND re.IdEtichetta IN (SELECT IdEtichetta FROM dbo.tblRifiutiLimitiEtichette WHERE IdLimite = c.Id)
						)
					)
					AND (
						NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiLimitiOperazioni WHERE IdLimite = c.Id)
						OR m.IdOperazione IN (SELECT IdOperazione FROM dbo.tblRifiutiLimitiOperazioni WHERE IdLimite = c.Id)
					)
			) x
		) op
	WHERE
		c.Lock = 0
		AND (@IdSede IS NULL OR c.IdSede = @IdSede)
);
GO

-- ============================================================ uspRifiutiRegistrazioni_ins_CaricoAuto
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

			INSERT dbo.tblRifiutiRegistrazioni
				(Id, IdMovimento, Operazione, [Data], Numero, QuantitaVerificata, IdMateriale, MaterialeDescrizione, Lock)
			VALUES
				(@returnId, @idMovimento, @operazioneGruppo, @data, @numero, @Quantita, @idMateriale, @materialeDescrizione, 0);

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

-- ============================================================ uspEoWLottiRifiutiRegistrazioni_ins
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
		IF EXISTS (SELECT 1 FROM dbo.viewRifiutiRegistrazioniEffettive WHERE Id = @IdRegistrazione AND IsRettifica = 1)
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
			SELECT @lockRow = Id FROM dbo.tblEoWLotti WITH (UPDLOCK, HOLDLOCK) WHERE Id = @IdLotto;

			DECLARE @quantitaAttribuitaLotto DECIMAL(18, 2) = (
				-- Capienza occupata solo dalle quote di registrazioni attive (Lock < 2)
				SELECT SUM(q.Quantita) FROM dbo.tblEoWLottiRifiutiRegistrazioni q INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id WHERE q.IdLotto = @IdLotto AND rr.Lock < 2
			);
			IF @quantitaMaxLotto IS NOT NULL AND ISNULL(@quantitaAttribuitaLotto, 0) + @Quantita > @quantitaMaxLotto
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la capacità residua del lotto';
				GOTO BRANCH_END;
			END

			SELECT @lockRow = Id FROM dbo.tblRifiutiMovimenti WITH (UPDLOCK, HOLDLOCK) WHERE Id = @idMovimento;

			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			DECLARE @quantitaMovimento DECIMAL(18, 2) = (SELECT Quantita FROM dbo.viewRifiutiRegistrazioniEffettive WHERE Id = @IdRegistrazione);
			DECLARE @quantitaAttribuitaRegistrazione DECIMAL(18, 2) = (
				SELECT SUM(Quantita) FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione = @IdRegistrazione
			);
			IF ISNULL(@quantitaAttribuitaRegistrazione, 0) + @Quantita > ISNULL(@quantitaMovimento, 0)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la quantità residua della registrazione';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione = @IdRegistrazione AND IdLotto = @IdLotto)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Questo lotto è già associato alla registrazione: modificare la quantità esistente';
				GOTO BRANCH_END;
			END

			INSERT dbo.tblEoWLottiRifiutiRegistrazioni (IdRegistrazione, IdLotto, Quantita)
			VALUES (@IdRegistrazione, @IdLotto, @Quantita);

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

-- ============================================================ uspEoWLottiRifiutiRegistrazioni_upd
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

		IF NOT EXISTS (SELECT 1 FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione = @IdRegistrazione AND IdLotto = @IdLotto)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Associazione non trovata';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Lock in ordine stabile (sempre Lotto, poi Movimento), stesso ordine di _ins
			DECLARE @lockRow CHAR(16);
			SELECT @lockRow = Id FROM dbo.tblEoWLotti WITH (UPDLOCK, HOLDLOCK) WHERE Id = @IdLotto;

			DECLARE @quantitaAttribuitaLotto DECIMAL(18, 2) = (
				-- Capienza occupata solo dalle quote di registrazioni attive (Lock < 2)
				SELECT SUM(q.Quantita) FROM dbo.tblEoWLottiRifiutiRegistrazioni q INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id WHERE q.IdLotto = @IdLotto AND rr.Lock < 2 AND q.IdRegistrazione <> @IdRegistrazione
			);
			IF @quantitaMaxLotto IS NOT NULL AND ISNULL(@quantitaAttribuitaLotto, 0) + @Quantita > @quantitaMaxLotto
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la capacità residua del lotto';
				GOTO BRANCH_END;
			END

			SELECT @lockRow = Id FROM dbo.tblRifiutiMovimenti WITH (UPDLOCK, HOLDLOCK) WHERE Id = @idMovimento;

			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			DECLARE @quantitaMovimento DECIMAL(18, 2) = (SELECT Quantita FROM dbo.viewRifiutiRegistrazioniEffettive WHERE Id = @IdRegistrazione);
			DECLARE @quantitaAttribuitaRegistrazione DECIMAL(18, 2) = (
				SELECT SUM(Quantita) FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione = @IdRegistrazione AND IdLotto <> @IdLotto
			);
			IF ISNULL(@quantitaAttribuitaRegistrazione, 0) + @Quantita > ISNULL(@quantitaMovimento, 0)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità supera la quantità residua della registrazione';
				GOTO BRANCH_END;
			END

			UPDATE dbo.tblEoWLottiRifiutiRegistrazioni
			SET Quantita = @Quantita
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

-- ============================================================ uspEoWAllocazioni_esegui
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
		IF EXISTS (SELECT 1 FROM dbo.viewRifiutiRegistrazioniEffettive WHERE Id = @IdRegistrazione AND IsRettifica = 1)
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

			SELECT @lockRow = Id FROM dbo.tblRifiutiMovimenti WITH (UPDLOCK, HOLDLOCK) WHERE Id = @idMovimento;

			-- Righe di configurazione + quantità già attribuita ad ognuno dei lotti coinvolti, lette
			-- sotto lock (fonte unica di verità, nessun ricalcolo su dati stimati prima del lock)
			DECLARE @righe TABLE (IdLotto CHAR(16) PRIMARY KEY, Valore DECIMAL(18, 2) NULL, QuantitaMax DECIMAL(18, 2) NULL, QuantitaAttribuita DECIMAL(18, 2) NOT NULL);
			INSERT INTO @righe (IdLotto, Valore, QuantitaMax, QuantitaAttribuita)
			SELECT
				la.IdLotto,
				la.Valore,
				l.QuantitaMax,
				QuantitaAttribuita = ISNULL((SELECT SUM(r.Quantita) FROM dbo.tblEoWLottiRifiutiRegistrazioni r INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id WHERE r.IdLotto = la.IdLotto AND rr.Lock < 2), 0)
			FROM
				dbo.tblEoWLottiAllocazioni la
				INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
			WHERE la.IdAllocazione = @Id;

			IF NOT EXISTS (SELECT 1 FROM @righe)
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

				IF NOT EXISTS (SELECT 1 FROM @righe)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Tutti i lotti dell''allocazione sono chiusi o disabilitati';
					GOTO BRANCH_END;
				END
			END

			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			DECLARE @quantitaMovimento DECIMAL(18, 2) = (SELECT Quantita FROM dbo.viewRifiutiRegistrazioniEffettive WHERE Id = @IdRegistrazione);
			DECLARE @quantitaAttribuitaRegistrazione DECIMAL(18, 2) = ISNULL((
				SELECT SUM(Quantita) FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione = @IdRegistrazione
			), 0);
			DECLARE @quantitaDaAllocare DECIMAL(18, 2) = ISNULL(@quantitaMovimento, 0) - @quantitaAttribuitaRegistrazione;

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
				IF (SELECT COUNT(*) FROM @righe) <> 1
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Un''allocazione di tipo Lotto unico deve avere esattamente un lotto configurato';
					GOTO BRANCH_END;
				END

				INSERT INTO @piano (IdLotto, Quantita)
				SELECT IdLotto, @quantitaDaAllocare FROM @righe;
			END
			ELSE IF @idAllocazioneTipo = 'P'
			BEGIN
				DECLARE @sommaPercentuali DECIMAL(18, 2) = (SELECT SUM(ISNULL(Valore, 0)) FROM @righe);
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
					DECLARE @idUltimoLotto CHAR(16) = (SELECT TOP 1 IdLotto FROM @righe ORDER BY IdLotto DESC);
					DECLARE @resto DECIMAL(18, 2) = @quantitaDaAllocare - (SELECT SUM(Quantita) FROM @piano);
					UPDATE @piano SET Quantita = Quantita + @resto WHERE IdLotto = @idUltimoLotto;
				END
			END
			ELSE IF @idAllocazioneTipo = 'C'
			BEGIN
				-- Ripartizione greedy per priorità (Valore crescente = priorità più alta): iterazione
				-- riga per riga, nessun pattern set-based equivalente per un bin-packing sequenziale.
				DECLARE @rimanente DECIMAL(18, 2) = @quantitaDaAllocare;
				DECLARE @curIdLotto CHAR(16), @curQuantitaMax DECIMAL(18, 2), @curQuantitaAttribuita DECIMAL(18, 2);

				DECLARE curRighe CURSOR LOCAL FAST_FORWARD FOR
					SELECT IdLotto, QuantitaMax, QuantitaAttribuita
					FROM @righe
					ORDER BY ISNULL(Valore, 999999999), IdLotto;

				OPEN curRighe;
				FETCH NEXT FROM curRighe INTO @curIdLotto, @curQuantitaMax, @curQuantitaAttribuita;
				WHILE @@FETCH_STATUS = 0 AND @rimanente > 0
				BEGIN
					DECLARE @capacitaResidua DECIMAL(18, 2) = CASE
						WHEN @curQuantitaMax IS NULL THEN @rimanente
						ELSE @curQuantitaMax - @curQuantitaAttribuita
					END;
					IF @capacitaResidua > 0
					BEGIN
						DECLARE @presoQui DECIMAL(18, 2) = IIF(@capacitaResidua < @rimanente, @capacitaResidua, @rimanente);
						INSERT INTO @piano (IdLotto, Quantita) VALUES (@curIdLotto, @presoQui);
						SET @rimanente -= @presoQui;
					END
					FETCH NEXT FROM curRighe INTO @curIdLotto, @curQuantitaMax, @curQuantitaAttribuita;
				END
				CLOSE curRighe;
				DEALLOCATE curRighe;

				IF @rimanente > 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'La capacità configurata nei lotti è insufficiente per la quantità da allocare';
					GOTO BRANCH_END;
				END
			END

			-- Verifica finale capacità per riga (ridondante per U/P dove già implicito, ma protegge
			-- comunque da una configurazione QuantitaMax incoerente) e upsert nella tabella risultato
			IF EXISTS (
				SELECT 1
				FROM @piano p INNER JOIN @righe r ON p.IdLotto = r.IdLotto
				WHERE r.QuantitaMax IS NOT NULL AND r.QuantitaAttribuita + p.Quantita > r.QuantitaMax
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità calcolata supera la capacità residua di uno o più lotti';
				GOTO BRANCH_END;
			END

			MERGE dbo.tblEoWLottiRifiutiRegistrazioni AS target
			USING @piano AS source
				ON target.IdRegistrazione = @IdRegistrazione AND target.IdLotto = source.IdLotto
			WHEN MATCHED THEN
				UPDATE SET Quantita = target.Quantita + source.Quantita
			WHEN NOT MATCHED THEN
				INSERT (IdRegistrazione, IdLotto, Quantita)
				VALUES (@IdRegistrazione, source.IdLotto, source.Quantita);

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

-- ============================================================ uspEoWGiacenze_get_Carichi_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWGiacenze_get_Carichi_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Id CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSede CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- Senza @Id: tutti i carichi EoW delle sedi interne della sessione (filtrati per
		-- @IdSede, la sede del contesto, se indicata); con @Id: i carichi del lotto (@Vista = L)
		-- o del magazzino EoW (@Vista = M) indicato
		IF @Id IS NOT NULL AND ISNULL(@Vista, '') NOT IN ('L', 'M')
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

		-- Titolarità sul Lotto/Magazzino indicato
		IF @Id IS NOT NULL AND @Vista = 'L' AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti l INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			WHERE l.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF @Id IS NOT NULL AND @Vista = 'M' AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWMagazzini g INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			lr.IdRegistrazione AS Id,
			r.Numero,
			r.Data,
			MaterialeNome = ISNULL(r.MaterialeDescrizione, mat.Nome),
			LottoNome = l.Nome,
			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			QuantitaComplessiva = vo.Quantita,
			QuantitaAttribuita = lr.Quantita,
			-- Residuo attuale del lotto EoW della quota (gli scarichi di magazzino prelevano dal
			-- lotto, non dalla singola registrazione): quote di registrazioni attive meno gli
			-- scarichi dei movimenti di magazzino confermati
			ResiduoLotto = ISNULL(pl.Prodotta, 0) - ISNULL(sl.Scaricata, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblEoWLottiRifiutiRegistrazioni lr
			INNER JOIN dbo.tblEoWLotti l ON lr.IdLotto = l.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON lr.IdRegistrazione = r.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vo ON r.Id = vo.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON r.IdMateriale = mat.Id
			OUTER APPLY (
				SELECT Prodotta = SUM(qp.Quantita)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni qp
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON qp.IdRegistrazione = rp.Id
				WHERE
					qp.IdLotto = l.Id
					AND rp.Lock < 2
			) pl
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
			) sl
		-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
		-- mantiene le sue quote per un eventuale ripristino, ma non conta più
		WHERE
			r.Lock < 2
			AND (
				(@Id IS NULL AND (@IdSede IS NULL OR l.IdSede = @IdSede))
				OR (@Vista = 'L' AND l.Id = @Id)
				OR (@Vista = 'M' AND l.IdMagazzino = @Id)
			)
			AND (@Search IS NULL OR r.Numero = TRY_CAST(@Search AS INT) OR l.Nome LIKE '%' + @Search + '%')
		ORDER BY r.Data DESC, r.Numero DESC
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

-- ============================================================ uspEoWLotti_get_RegistrazioniList
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get_RegistrazioniList
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

		-- Controlla il permesso sul record (titolarità)
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

		SELECT
			lr.IdRegistrazione,
			r.Numero,
			r.Data,
			MaterialeNome = ISNULL(r.MaterialeDescrizione, mat.Nome),
			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			QuantitaComplessiva = vo.Quantita,
			QuantitaAttribuita = lr.Quantita
		FROM
			dbo.tblEoWLottiRifiutiRegistrazioni lr
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON lr.IdRegistrazione = r.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vo ON r.Id = vo.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON r.IdMateriale = mat.Id
		-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
		-- mantiene le sue quote per un eventuale ripristino, ma non conta più
		WHERE
			lr.IdLotto = @Id
			AND r.Lock < 2
		ORDER BY r.Data DESC, r.Numero DESC;

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

