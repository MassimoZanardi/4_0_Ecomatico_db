CREATE PROCEDURE [dbo].[uspRifiutiFormulari_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdProvenienza CHAR(1) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@ClassiPericolo VARCHAR(50) = NULL,
	@VerificatoInPartenza BIT = 0,
	@IdAttivitaRs CHAR(2) = NULL,
	@FormularioNumero VARCHAR(20) = NULL,
	@FormularioDataEmissione DATE = NULL,
	@IdAutorizzazioneProduttoreDetentore CHAR(16) = NULL,
	@IdAutorizzazioneDestinatario CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore1 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore2 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore3 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario1 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario2 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario3 CHAR(16) = NULL,
	@IdTipoTrasporto1 CHAR(1) = NULL,
	@IdTipoTrasporto2 CHAR(1) = NULL,
	@IdTipoTrasporto3 CHAR(1) = NULL,
	@TargaMotrice VARCHAR(20) = NULL,
	@TargaRimorchio VARCHAR(20) = NULL,
	@ConducenteNome VARCHAR(50) = NULL,
	@ConducenteCognome VARCHAR(50) = NULL,
	@RimorchioPrecedente BIT = 0,
	@Nave VARCHAR(50) = NULL,
	@Imdg BIT = 0,
	@Treno VARCHAR(50) = NULL,
	@Tratta VARCHAR(50) = NULL,
	@Rid BIT = 0,
	@DataInizioTrasporto SMALLDATETIME = NULL,
	@IdAdr CHAR(2) = NULL,
	@NumeroOnu VARCHAR(20) = NULL,
	@TrasportoAdr BIT = 0,
	@AdrNote VARCHAR(200) = NULL,
	@IdImballo CHAR(2) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@Quantita DECIMAL(18,2) = NULL,
	@ColliNumero VARCHAR(50) = NULL,
	@AllaRinfusa BIT = 0,
	@IdAnalisiTipo CHAR(1) = NULL,
	@AnalisiNumero VARCHAR(50) = NULL,
	@AnalisiData DATE = NULL,
	@LuogoDiProduzione BIT = 0,
	@Detentore BIT = 0,
	@Percorso VARCHAR(100) = NULL,
	@FormularioNote VARCHAR(500) = NULL,
	@UtenteNote VARCHAR(500) = NULL,
	@IdEtichette VARCHAR(50) = NULL
AS

/*
REGOLE ASSOCIAZIONE REGISTRAZIONE <-> FORMULARI
1. Da Registrazioni: se @IdDocumentoTrasportoTipo non è un Formulario lo rimuove da Formulari
2. Da Registrazioni: sarà possibile eliminare una registrazione associata a un formulario. In questo caso, il formulario resterà presente e risulterà non associato ad alcuna registrazione.
3. Da Formulari: sarà possibile creare un nuovo formulario anche senza associarlo a una registrazione.
4. Da Formulari: sarà possibile generare una nuova registrazione a partire dal formulario. La registrazione verrà automaticamente associata al formulario stesso. Non sarà consentita l'associazione del
 formulario a registrazioni già esistenti.
5. Da formulari: sarà possibile creare il formulario e contestualmente la registrazione. Non sarà possibile il contrario.
*/

BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Normalizzazione parametri obbligatori
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
		IF @Quantita IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Quantita non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RFR',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: prima non esisteva alcun controllo che @Id appartenesse
		-- all'azienda della sessione (via registro/sede) - stesso pattern di
		-- uspRifiutiFormulari_get. Senza questo controllo, chiunque avesse permesso
		-- RFR >= 2 poteva riscrivere il formulario (autorizzazioni, EER, quantità,
		-- trasportatori, ecc.) di un'altra azienda conoscendone l'Id.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE f.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);
		DECLARE @minData DATE = '19000101';
		DECLARE @maxData DATE = '20501231';

		IF @FormularioDataEmissione >= @maxData SET @FormularioDataEmissione = NULL;
		IF @DataInizioTrasporto >= @maxData SET @DataInizioTrasporto = NULL;

		DECLARE @idMovimento CHAR(16);
		DECLARE @idRegistro CHAR(16);
		DECLARE @idRegistrazione CHAR(16);
		DECLARE @lock TINYINT;
		DECLARE @isRegistrazioneAssociata BIT;
		DECLARE @registrazioneData DATE;
		DECLARE @registrazioneNumero INT;
		DECLARE @idOperazione CHAR(1);
		DECLARE @totaleQuantitaAssegnata DECIMAL(18,2);
		DECLARE @idRelazione CHAR(16);
		DECLARE @quantitaRelazione DECIMAL(18,2);
		DECLARE @quantitaResidua DECIMAL(18,2);
		DECLARE @nessunaRegistrazioneAssociata BIT = 1;

		-- Recupero dati formulario dalle tabelle base
		SELECT
			@idMovimento = f.IdMovimento,
			@idRegistro = m.IdRegistro,
			@idRegistrazione = r.Id,
			@lock = f.Lock,
			@idOperazione = m.IdOperazione,
			@isRegistrazioneAssociata = IIF(r.Id IS NOT NULL AND ISNULL(r.Lock, 8) < 2, 1, 0),
			@registrazioneData = r.[Data],
			@registrazioneNumero = r.Numero,
			@nessunaRegistrazioneAssociata = CASE
				WHEN EXISTS(
					SELECT 1
					FROM dbo.tblRifiutiRegistrazioniRelazioni rel
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON rel.Id = rr.Id
					WHERE
						rel.IdParent = r.Id
						AND rr.Lock < 2
				) THEN 0
				ELSE 1
			END
		FROM
			dbo.tblRifiutiFormulari f
		INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
		LEFT JOIN dbo.tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento AND r.Lock < 2
		WHERE f.Id = @Id;

		-- Verifica che il formulario esista
		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Formulario non trovato';
			GOTO BRANCH_END;
		END

		-- Normalizzazione parametri CHAR opzionali
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdProvenienza = NULLIF(LTRIM(RTRIM(@IdProvenienza)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdAttivitaRs = NULLIF(LTRIM(RTRIM(@IdAttivitaRs)), '');
		SET @IdTipoTrasporto1 = NULLIF(LTRIM(RTRIM(@IdTipoTrasporto1)), '');
		SET @IdTipoTrasporto2 = NULLIF(LTRIM(RTRIM(@IdTipoTrasporto2)), '');
		SET @IdTipoTrasporto3 = NULLIF(LTRIM(RTRIM(@IdTipoTrasporto3)), '');
		SET @IdAdr = NULLIF(LTRIM(RTRIM(@IdAdr)), '');
		SET @IdImballo = NULLIF(LTRIM(RTRIM(@IdImballo)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');
		SET @IdAutorizzazioneProduttoreDetentore = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneProduttoreDetentore)), '');
		SET @IdAutorizzazioneDestinatario = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneDestinatario)), '');
		SET @IdAutorizzazioneTrasportatore1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore1)), '');
		SET @IdAutorizzazioneTrasportatore2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore2)), '');
		SET @IdAutorizzazioneTrasportatore3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore3)), '');
		SET @IdAutorizzazioneIntermediario1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario1)), '');
		SET @IdAutorizzazioneIntermediario2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario2)), '');
		SET @IdAutorizzazioneIntermediario3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario3)), '');

		-- Autorizzazioni: azzera se è "nessuna" (SediciZeri)
		IF @IdAutorizzazioneProduttoreDetentore = @idSediciZeri SET @IdAutorizzazioneProduttoreDetentore = NULL;
		IF @IdAutorizzazioneDestinatario = @idSediciZeri SET @IdAutorizzazioneDestinatario = NULL;

		-- Autorizzazioni trasportatore: gestisce i valori delle 3 possibili autorizzazioni
		IF @IdAutorizzazioneTrasportatore1 = @idSediciZeri
			SET @IdAutorizzazioneTrasportatore1 = NULL;

		IF @IdAutorizzazioneTrasportatore2 = @idSediciZeri OR @IdAutorizzazioneTrasportatore1 IS NULL
			SET @IdAutorizzazioneTrasportatore2 = NULL;

		IF @IdAutorizzazioneTrasportatore3 = @idSediciZeri OR @IdAutorizzazioneTrasportatore2 IS NULL
			SET @IdAutorizzazioneTrasportatore3 = NULL;

		-- Autorizzazioni intermediario: gestisce i valori delle 3 possibili autorizzazioni
		IF @IdAutorizzazioneIntermediario1 = @idSediciZeri
			SET @IdAutorizzazioneIntermediario1 = NULL;

		IF @IdAutorizzazioneIntermediario2 = @idSediciZeri OR @IdAutorizzazioneIntermediario1 IS NULL
			SET @IdAutorizzazioneIntermediario2 = NULL;

		IF @IdAutorizzazioneIntermediario3 = @idSediciZeri OR @IdAutorizzazioneIntermediario2 IS NULL
			SET @IdAutorizzazioneIntermediario3 = NULL;

		IF @AllaRinfusa = 1 SET @IdImballo = NULL;
		IF @IdImballo = '00' SET @IdImballo = NULL;

		-- Normalizzazione parametri VARCHAR opzionali
		SET @ClassiPericolo = dbo.ufnStringhe_get_SenzaSpazi(@ClassiPericolo, 0, 1);
		SET @FormularioNumero = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@FormularioNumero, 0, 1));
		SET @ColliNumero = dbo.ufnStringhe_get_SenzaSpazi(@ColliNumero, 0, 1);
		SET @FormularioNote = dbo.ufnStringhe_get_SenzaSpazi(@FormularioNote, 0, 1);
		SET @UtenteNote = dbo.ufnStringhe_get_SenzaSpazi(@UtenteNote, 0, 1);
		SET @IdEtichette = dbo.ufnStringhe_get_SenzaSpazi(@IdEtichette, 0, 1);

		-- Trasporto terrestre (G): tblRifiutiFormulariTrasportiTerresti
		IF @IdTipoTrasporto1 <> 'G'
		BEGIN
			SET @TargaMotrice = NULL;
			SET @TargaRimorchio = NULL;
			SET @ConducenteNome = NULL;
			SET @ConducenteCognome = NULL;
			SET @Percorso = NULL;
			SET @RimorchioPrecedente = 0;
		END
		ELSE
		BEGIN
			SET @TargaMotrice = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@TargaMotrice, 0, 1));
			SET @TargaRimorchio = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@TargaRimorchio, 0, 1));
			SET @ConducenteNome = dbo.ufnStringhe_get_SenzaSpazi(@ConducenteNome, 0, 1);
			SET @ConducenteCognome = dbo.ufnStringhe_get_SenzaSpazi(@ConducenteCognome, 0, 1);
			SET @Percorso = dbo.ufnStringhe_get_SenzaSpazi(@Percorso, 0, 1);
		END

		-- Trasporto marittimo (N): tblRifiutiFormulariTrasportiMarittimi
		IF @IdTipoTrasporto1 <> 'N'
		BEGIN
			SET @Nave = NULL;
			SET @Imdg = 0;
		END
		ELSE
			SET @Nave = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Nave, 0, 1));

		-- Trasporto ferroviario (T): tblRifiutiFormulariTrasportiFerroviari
		IF @IdTipoTrasporto1 <> 'T'
		BEGIN
			SET @Treno = NULL;
			SET @Tratta = NULL;
			SET @Rid = 0;
		END
		ELSE
		BEGIN
			SET @Treno = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Treno, 0, 1));
			SET @Tratta = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@Tratta, 0, 1));
		END

		-- ADR
		IF @TrasportoAdr = 0
		BEGIN
			SET @IdAdr = NULL;
			SET @NumeroOnu = NULL;
			SET @AdrNote = NULL;
		END
		ELSE
		BEGIN
			IF @IdAdr = '00' SET @IdAdr = NULL;
			SET @NumeroOnu = dbo.ufnStringhe_get_SenzaSpazi(@NumeroOnu, 0, 1);
			SET @AdrNote = dbo.ufnStringhe_get_SenzaSpazi(@AdrNote, 0, 1);
		END

		-- Analisi
		IF @IdAnalisiTipo = '0'
		BEGIN
			SET @IdAnalisiTipo = NULL;
			SET @AnalisiNumero = NULL;
			SET @AnalisiData = NULL;
		END
		ELSE
		BEGIN
			SET @AnalisiNumero = dbo.ufnStringhe_get_SenzaSpazi(@AnalisiNumero, 0, 1);
		END

		-- Calcolo totale quantità assegnata (separato dal SELECT per leggere @nessunaRegistrazioneAssociata già valorizzata)
		IF @nessunaRegistrazioneAssociata = 0
			SELECT @totaleQuantitaAssegnata = ISNULL(SUM(lq.Quantita), 0)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni lq
			INNER JOIN dbo.tblRifiutiRegistrazioni rq ON lq.Id = rq.Id
			WHERE
				lq.IdParent = @idRegistrazione
				AND lq.Quantita > 0
				AND rq.Lock < 2;
		ELSE
			SET @totaleQuantitaAssegnata = 0;

		-- Controllo numero formulario duplicato
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
			WHERE
				f.IdMovimento <> @idMovimento
				AND m.IdRegistro = @idRegistro
				AND f.Lock < 2
				AND m.FormularioNumero = @FormularioNumero
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro formulario con lo stesso numero è già presente';
			GOTO BRANCH_END;
		END

		-- Controllo EER/stato fisico/unità di misura nelle relazioni della registrazione associata
		IF @isRegistrazioneAssociata = 1 AND @nessunaRegistrazioneAssociata = 0 AND @idOperazione <> 'K'
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
				INNER JOIN dbo.tblRifiutiMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					(l.Id = @idRegistrazione OR l.IdParent = @idRegistrazione)
					AND mp.IdOperazione <> 'M'
					AND ( m.IdEer <> @IdEer OR m.IdStatoFisico <> @IdStatoFisico OR m.IdUnitaMisura <> @IdUnitaMisura )
					AND l.Quantita > 0
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione di questo formulario è associata ad altre con differente EER e/o stato fisico e/o unità di misura';
				GOTO BRANCH_END;
			END
		END


		-- Controllo quantità già scaricata (l.Id = @idRegistrazione: verifica che @idRegistrazione, come figlio, non scenda sotto quanto già scaricato dal padre)
		IF @isRegistrazioneAssociata = 1
		BEGIN
			IF @Quantita < ISNULL((
				SELECT SUM(l.Quantita)
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
				WHERE
					l.Id = @idRegistrazione
					AND l.Quantita > 0
					AND rp.Lock < 2
			), 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità non può essere inferiore a quella già associata ad altre registrazioni';
				GOTO BRANCH_END;
			END
		END

		 -- Verifica quantità superiore disponibile nella registrazione associata
		IF @isRegistrazioneAssociata = 1 AND @nessunaRegistrazioneAssociata = 0
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiOperazioniRelazioni
			WHERE Id = @idOperazione)
			BEGIN
				IF dbo.ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore(
					@idRegistrazione, @Quantita, @registrazioneData, @registrazioneNumero,
					@IdEer, @IdStatoFisico, @IdUnitaMisura, 0) > 0
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'La quantità registrata è superiore a quella disponibile nelle registrazioni associate';
					GOTO BRANCH_END;
				END
			END
		END

		-- Verifica se necessario aggiornare il log
		DECLARE @aggiornaLog BIT = 0;
		IF @lock < 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiMovimenti m
				WHERE
					m.Id = @idMovimento
					AND ( ISNULL(m.IdEer, '000000') <> ISNULL(@IdEer, '000000') OR ISNULL(m.IdStatoFisico, '0') <> ISNULL(@IdStatoFisico, '0') OR ISNULL(m.IdAttivita, '00') <> ISNULL(@IdAttivitaRs, '00') OR ISNULL(m.FormularioNumero, '') <> ISNULL(@FormularioNumero, '') OR ISNULL(m.IdUnitaMisura, '0') <> ISNULL(@IdUnitaMisura, '0') OR ISNULL(m.Quantita, 0) <> ISNULL(@Quantita, 0) OR ISNULL(m.DataInizioTrasporto, @minData) <> ISNULL(@DataInizioTrasporto, @minData) )
			)
				SET @aggiornaLog = 1;
			ELSE IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiMovimenti m
				LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp1 ON m.Id = mp1.Id AND mp1.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi1 ON m.Id = mi1.Id AND mi1.Pos = 0
				WHERE
					m.Id = @idMovimento
					AND ( ISNULL(mp1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneProduttoreDetentore, @idSediciZeri) OR ISNULL(md.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneDestinatario, @idSediciZeri) OR ISNULL(mt1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneTrasportatore1, @idSediciZeri) OR ISNULL(mi1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneIntermediario1, @idSediciZeri) )
			)
				SET @aggiornaLog = 1;
		END

		-- Calcola la soglia per la pulizia del log (fuori dalla transazione, intenzionale)
		-- Se ci sono 10 o meno record @dataLogMin resta NULL: il DELETE successivo non elimina nulla (comportamento corretto)
		DECLARE @dataLogMin DATETIME2(0);
		DECLARE @idUtente CHAR(16);

		IF @aggiornaLog = 1
		BEGIN
			SELECT TOP 1
				@dataLogMin = [Data]
			FROM (
				SELECT
					[Data],
					Pos = ROW_NUMBER() OVER (ORDER BY [Data] DESC)
				FROM dbo.tblRifiutiMovimentiLog
				WHERE Id = @idMovimento) t
			WHERE t.Pos > 9
			ORDER BY Pos;

			-- Lettura IdUtente fuori dalla transazione (intenzionale)
			SELECT @idUtente = IdUtente
			FROM dbo.tblSessioni
			WHERE Id = @IdSessione;
		END

		BEGIN TRANSACTION;

			-- Produttori
			DELETE dbo.tblRifiutiMovimentiProduttori
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneProduttoreDetentore IS NOT NULL
			BEGIN
				IF EXISTS (SELECT 1
				FROM dbo.tblSedi
				WHERE Id = @IdAutorizzazioneProduttoreDetentore)
				BEGIN
					DECLARE @idSede CHAR(16) = @IdAutorizzazioneProduttoreDetentore;
					SET @IdAutorizzazioneProduttoreDetentore = NULL;

					SELECT @IdAutorizzazioneProduttoreDetentore = Id
					FROM dbo.tblRifiutiAutorizzazioni
					WHERE
						IdSede = @idSede
						AND Nessuna = 1
						AND Lock = 0;

					IF @IdAutorizzazioneProduttoreDetentore IS NULL
					BEGIN
						EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @IdAutorizzazioneProduttoreDetentore OUTPUT;

						INSERT dbo.tblRifiutiAutorizzazioni
							(Id, IdSede, IdRuolo, DataInizio, DataFine, Nessuna, Disabilitata, Lock)
						VALUES
							(@IdAutorizzazioneProduttoreDetentore, @idSede, 'P', @minData, @maxData, 1, 0, 0);
					END
				END

				INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneProduttoreDetentore, @Quantita, 0);
			END

			-- Destinatari
			DELETE dbo.tblRifiutiMovimentiDestinatari
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneDestinatario IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneDestinatario, 0);
			END

			-- Trasportatori
			DELETE dbo.tblRifiutiMovimentiTrasportatori
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneTrasportatore1 IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneTrasportatore1, @IdTipoTrasporto1, 0);

				IF @IdAutorizzazioneTrasportatore2 IS NOT NULL
				BEGIN
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
					VALUES (@idMovimento, @IdAutorizzazioneTrasportatore2, @IdTipoTrasporto2, 1);

					IF @IdAutorizzazioneTrasportatore3 IS NOT NULL
					BEGIN
						INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
						VALUES (@idMovimento, @IdAutorizzazioneTrasportatore3, @IdTipoTrasporto3, 2);
					END
				END
			END

			-- Trasporto (dettaglio per tipo, tabelle satellite del formulario)
			DELETE dbo.tblRifiutiFormulariTrasportiTerresti
			WHERE Id = @Id;
			DELETE dbo.tblRifiutiFormulariTrasportiMarittimi
			WHERE Id = @Id;
			DELETE dbo.tblRifiutiFormulariTrasportiFerroviari
			WHERE Id = @Id;

			IF @IdTipoTrasporto1 = 'G'
				INSERT dbo.tblRifiutiFormulariTrasportiTerresti
					(Id, TargaMotrice, TargaRimorchio, ConducenteNome, ConducenteCognome, Percorso, RimorchioPrecedente)
				VALUES
					(@Id, @TargaMotrice, @TargaRimorchio, @ConducenteNome, @ConducenteCognome, @Percorso, @RimorchioPrecedente);
			ELSE IF @IdTipoTrasporto1 = 'N'
				INSERT dbo.tblRifiutiFormulariTrasportiMarittimi (Id, Nave, Imdg)
				VALUES (@Id, @Nave, @Imdg);
			ELSE IF @IdTipoTrasporto1 = 'T'
				INSERT dbo.tblRifiutiFormulariTrasportiFerroviari (Id, Treno, Tratta, Rid)
				VALUES (@Id, @Treno, @Tratta, @Rid);

			-- Intermediari
			DELETE dbo.tblRifiutiMovimentiIntermediari
			WHERE Id = @idMovimento;

			IF @IdAutorizzazioneIntermediario1 IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneIntermediario1, 0);

				IF @IdAutorizzazioneIntermediario2 IS NOT NULL
				BEGIN
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @IdAutorizzazioneIntermediario2, 1);

					IF @IdAutorizzazioneIntermediario3 IS NOT NULL
					BEGIN
						INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @IdAutorizzazioneIntermediario3, 2);
					END
				END
			END

			-- Classi di pericolo
			DELETE dbo.tblRifiutiMovimentiClassiPericolo
			WHERE Id = @idMovimento;

			INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
			SELECT @idMovimento, c.Id
			FROM
				dbo.tblRifiutiClassiPericolo c
			INNER JOIN STRING_SPLIT(@ClassiPericolo, ';') v ON c.Id = v.value;

			-- Etichette formulario
			DELETE dbo.tblRifiutiFormulariEtichette
			WHERE Id = @Id;

			INSERT dbo.tblRifiutiFormulariEtichette (Id, IdEtichetta)
			SELECT TOP 3 @Id, e.Id
			FROM
				dbo.tblEtichette e
			INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

			-- Aggiorna le quantità delle registrazioni in relazione carico/scarico
			IF @Quantita = 0 OR @nessunaRegistrazioneAssociata = 1
			BEGIN
				DELETE dbo.tblRifiutiRegistrazioniRelazioni
				WHERE IdParent = @idRegistrazione;
			END

			IF @nessunaRegistrazioneAssociata = 0 AND @Quantita > 0 AND @Quantita <> @totaleQuantitaAssegnata
			BEGIN
				UPDATE dbo.tblRifiutiRegistrazioniRelazioni
				SET Quantita = 0
				WHERE IdParent = @idRegistrazione;

				SET @quantitaRelazione = @Quantita;

				-- Distribuzione quantità sulle relazioni ordinate per Pos
				DECLARE c CURSOR FAST_FORWARD FOR
					SELECT
						l.Id,
						QuantitaResidua = m2.Quantita - ISNULL(a.Quantita, 0)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
					INNER JOIN dbo.tblRifiutiMovimenti m2 ON r.IdMovimento = m2.Id
					LEFT JOIN (
							SELECT lq.Id, Quantita = SUM(lq.Quantita)
							FROM
								dbo.tblRifiutiRegistrazioniRelazioni lq
							INNER JOIN dbo.tblRifiutiRegistrazioni pq ON lq.IdParent = pq.Id
							INNER JOIN dbo.tblRifiutiMovimenti mpq ON pq.IdMovimento = mpq.Id
							WHERE
								pq.Lock < 2
								AND mpq.Quantita > 0
							GROUP BY lq.Id
						) a ON l.Id = a.Id
					WHERE l.IdParent = @idRegistrazione
					ORDER BY l.Pos;

				OPEN c;
				FETCH c INTO @idRelazione, @quantitaResidua;

				WHILE @@FETCH_STATUS = 0
				BEGIN
					IF @quantitaRelazione > 0
					BEGIN
						IF @quantitaRelazione >= @quantitaResidua
						BEGIN
							UPDATE dbo.tblRifiutiRegistrazioniRelazioni
							SET Quantita = @quantitaResidua
							WHERE
								IdParent = @idRegistrazione
								AND Id = @idRelazione;
							SET @quantitaRelazione = @quantitaRelazione - @quantitaResidua;
						END
						ELSE
						BEGIN
							UPDATE dbo.tblRifiutiRegistrazioniRelazioni
							SET Quantita = @quantitaRelazione
							WHERE
								IdParent = @idRegistrazione
								AND Id = @idRelazione;
							SET @quantitaRelazione = 0;
						END
					END
					FETCH c INTO @idRelazione, @quantitaResidua;
				END

				CLOSE c;
				DEALLOCATE c;
			END

			DELETE dbo.tblRifiutiRegistrazioniRelazioni
			WHERE
				IdParent = @idRegistrazione
				AND Quantita = 0;

			-- Aggiornamento log storico movimento (snapshot stato corrente prima degli UPDATE)
			-- @dataLogMin = NULL se <= 10 record: il DELETE non elimina nulla (comportamento corretto)
			IF @aggiornaLog = 1
			BEGIN
				DELETE dbo.tblRifiutiMovimentiLog
				WHERE
					Id = @idMovimento
					AND [Data] <= @dataLogMin;

				INSERT dbo.tblRifiutiMovimentiLog
					(Id, [Data], IdUtente,
					 IdEer, IdStatoFisico, IdMateriale, IdAttivita, IdUnitaMisura,
					 Quantita, QuantitaVerificata, IdAutorizzazioneProduttoreDetentore, IdAutorizzazioneDestinatario,
					 IdAutorizzazioneTrasportatore1, IdAutorizzazioneIntermediario1,
					 RegistrazioneNumero, RegistrazioneData, FormularioNumero, DataInizioTrasporto, DataFineTrasporto)
				SELECT
					m.Id, GETDATE(), @idUtente,
					m.IdEer, m.IdStatoFisico, r.IdMateriale, m.IdAttivita, m.IdUnitaMisura,
					m.Quantita, r.QuantitaVerificata, mp.IdAutorizzazione, md.IdAutorizzazione,
					mt.IdAutorizzazione, mi.IdAutorizzazione,
					r.Numero, r.[Data], m.FormularioNumero, m.DataInizioTrasporto, r.DataFineTrasporto
				FROM
					dbo.tblRifiutiMovimenti m
				LEFT JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
				LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt ON m.Id = mt.Id AND mt.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi ON m.Id = mi.Id AND mi.Pos = 0
				WHERE m.Id = @idMovimento;
			END

			-- Aggiornamento formulario
			UPDATE dbo.tblRifiutiFormulari
			SET
				DataEmissione = @FormularioDataEmissione,
				Note = @FormularioNote,
				IdAdr = @IdAdr,
				NumeroOnu = @NumeroOnu,
				TrasportoAdr = @TrasportoAdr,
				AdrNote = @AdrNote,
				IdImballo = @IdImballo,
				ColliNumero = @ColliNumero,
				AllaRinfusa = @AllaRinfusa,
				VerificatoInPartenza = @VerificatoInPartenza,
				Etichette = dbo.ufnRifiutiFormulari_get_Etichette(Id),
				IdAnalisiTipo = @IdAnalisiTipo,
				AnalisiNumero = @AnalisiNumero,
				AnalisiData = @AnalisiData,
				LuogoDiProduzione = @LuogoDiProduzione,
				Detentore = @Detentore,
				Lock = 0
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Formulario non trovato o già modificato da un altro utente';
				GOTO BRANCH_END;
			END

			-- Aggiornamento movimento
			UPDATE m
			SET
				IdEer = @IdEer,
				IdProvenienza = @IdProvenienza,
				IdStatoFisico = @IdStatoFisico,
				IdAttivita = @IdAttivitaRs,
				IdUnitaMisura = @IdUnitaMisura,
				Quantita = @Quantita,
				IdSedeProduttoreDetentore = ap.IdSede,
				IdSedeDestinatario = ad.IdSede,
				IdSedeTrasportatore1 = ar.IdSede,
				IdSedeIntermediario1 = ai.IdSede,
				FormularioNumero = @FormularioNumero,
				DataInizioTrasporto = @DataInizioTrasporto,
				Note = @UtenteNote
			FROM
				dbo.tblRifiutiMovimenti m
			LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ap ON mp.IdAutorizzazione = ap.Id
			LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ad ON md.IdAutorizzazione = ad.Id
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt ON m.Id = mt.Id AND mt.Pos = 0
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ar ON mt.IdAutorizzazione = ar.Id
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi ON m.Id = mi.Id AND mi.Pos = 0
			LEFT JOIN dbo.tblRifiutiAutorizzazioni ai ON mi.IdAutorizzazione = ai.Id
			WHERE m.Id = @idMovimento;

		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione (intenzionale)
		IF @lock > 0 OR @aggiornaLog = 1
		BEGIN
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';
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

	SELECT ReturnValue = @returnValue;
END;
