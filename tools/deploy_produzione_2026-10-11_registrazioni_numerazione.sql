/*
Deploy produzione 2026-10-11 - Registrazioni rifiuti: numerazione con blocco sul registro

Da eseguire DOPO deploy_produzione_2026-10-11_indici_fatturazione.sql. Rieseguibile.
Eseguire con sqlcmd -f 65001 -I. Nessuna modifica all'app: si può deployare da solo.
Regole: R11 di docs\regole\registrazioni-rettifiche.md (repo dell'app).

Chi assegna, controlla o sposta i numeri delle registrazioni blocca la riga del registro per tutta la
transazione (UPDLOCK, HOLDLOCK su tblRifiutiRegistri) e legge la numerazione dopo il blocco: due operazioni
contemporanee sullo stesso registro si mettono in fila e non possono prendere lo stesso numero.

1. uspRifiutiRegistrazioni_upd: controlli sul numero (duplicato, ordine rispetto alla data) e calcolo della
   rinumerazione spostati dentro la transazione, dopo il blocco. Query invariate.
2. uspRifiutiRegistrazioni_ins_CaricoAuto: prossimo numero letto dentro la transazione, dopo il blocco.
3. uspRifiutiRegistrazioni_upd_Numerazione: portata allo standard; controlli e aggiornamento in un'unica
   transazione, con il blocco; filtro sull'anno come intervallo di date.
4. uspRifiutiRegistrazioni_upd_Rettifica, uspRifiutiRegistrazioni_upd_Annullamento: il registro si blocca per
   primo, prima delle relazioni (stesso ordine della 1).
5. uspRifiutiRegistrazioni_del_Undo: ripristino rifiutato se il numero è stato assegnato a un'altra
   registrazione dello stesso registro e anno; intestazione standard.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

PRINT 'uspRifiutiRegistrazioni_upd.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdProvenienza CHAR(1) = NULL,
	@EerDescrizione VARCHAR(200) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@ClassiPericolo VARCHAR(50) = NULL,
	@IdAttivitaRs CHAR(2) = NULL,
	@RegistrazioneData DATE = NULL,
	@RegistrazioneNumero INT = 0,
	@IdUnitaMisura CHAR(2) = NULL,
	@Quantita DECIMAL(18,2) = 0,
	@DataInizioTrasporto SMALLDATETIME = NULL,
	@IdDocumentoTrasportoTipo CHAR(1) = NULL,
	@FormularioNumero VARCHAR(20) = NULL,
	@IdAutorizzazioneProduttoreDetentore CHAR(16) = NULL,
	@IdAutorizzazioneDestinatario CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore1 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore2 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore3 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario1 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario2 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario3 CHAR(16) = NULL,
	@RegistrazioneNote VARCHAR(500) = NULL,
	@UtenteNote VARCHAR(500) = NULL,
	@IdEtichette VARCHAR(50) = NULL,

	@IsVeicoloFuoriUso BIT = 0,
	@VeicoloFuoriUsoNumero VARCHAR(50) = NULL,
	@VeicoloFuoriUsoData DATE = NULL,

	@IdRaee CHAR(1) = NULL,

	-- Esito
	@IdEsito CHAR(1) = NULL,
	@QuantitaVerificata DECIMAL(18,2) = NULL,
	@DataFineTrasporto SMALLDATETIME = NULL,
	@IdCausaleRespingimento CHAR(1) = NULL,
	@CausaleRespingimentoAltro VARCHAR(100) = NULL,
	@IdUnitaMisuraQuantitaRespinta CHAR(2) = NULL,
	@QuantitaRespinta DECIMAL(18,2) = NULL,

	-- Materiale
	@IdMateriale CHAR(2) = NULL,
	@MaterialeDescrizione VARCHAR(200) = NULL,

	-- Provenienza
	@IdAttivitaProvenienza CHAR(1) = NULL,

	@RegistrazioneAuto BIT = 0,
	@RinumeraRegistro BIT = 0,
	@NessunaRegistrazioneAssociata BIT = 0
AS

/*
REGOLE ASSOCIAZIONE REGISTRAZIONE <-> FORMULARI
1. Da Registrazioni: se @IdDocumentoTrasportoTipo non è un Formulario lo rimuove da Formulari
2. Da Registrazioni: sarà possibile eliminare una registrazione associata a un formulario. In questo caso, il formulario resterà presente e risulterà non associato ad alcuna registrazione.
3. Da Formulari: sarà possibile creare un nuovo formulario anche senza associarlo a una registrazione.
4. Da Formulari: sarà possibile generare una nuova registrazione a partire dal formulario. La registrazione verrà automaticamente associata al formulario stesso. Non sarà consentita l'associazione del formulario a registrazioni già esistenti.
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);
		DECLARE @minData DATE = '19000101';
		DECLARE @maxData DATE = '20501231';

		-- Pre-calcolo range anno per confronti sargable
		DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@RegistrazioneData), 1, 1);
		DECLARE @annoFine DATE = DATEFROMPARTS(YEAR(@RegistrazioneData) + 1, 1, 1);

		DECLARE @idMovimento CHAR(16);
		DECLARE @idRegistro CHAR(16);
		DECLARE @idFormulario CHAR(16);
		DECLARE @lock TINYINT;
		DECLARE @operazione CHAR(1);
		DECLARE @idOperazione CHAR(1);
		DECLARE @totaleQuantitaAssegnata DECIMAL(18,2);
		DECLARE @idRelazione CHAR(16);
		DECLARE @quantitaRelazione DECIMAL(18,2);
		DECLARE @quantitaResidua DECIMAL(18,2);
		DECLARE @isIntegrazioneFir BIT;
		DECLARE @isFormularioAssociato BIT;
		DECLARE @isEsito BIT;
		DECLARE @isMateriale BIT;
		DECLARE @isProduttore BIT;
		DECLARE @isTrasportatore BIT;
		DECLARE @isDestinatario BIT;
		DECLARE @isIntermediario BIT;
		DECLARE @isAttivitaRs BIT;
		DECLARE @isAttivitaProvenienza BIT;
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		DECLARE @conservazioneSostitutiva BIT;

		-- Recupero dati registrazione
		SELECT
			@idMovimento = r.IdMovimento,
			@idRegistro = m.IdRegistro,
			@idFormulario = f.Id,
			@lock = r.Lock,
			@operazione = r.Operazione,
			@idOperazione = m.IdOperazione,
			@rentriIdentificativo = r.RentriIdentificativo,
			@rentriData = r.RentriData,
			@conservazioneSostitutiva = r.ConservazioneSostitutiva,
			@isIntegrazioneFir = o.IsIntegrazioneFir,
			@isFormularioAssociato = CAST(IIF(f.IdMovimento IS NOT NULL AND f.Lock < 2, 1, 0) AS BIT),
			@isEsito = o.IsEsito,
			@isMateriale = o.IsMateriale,
			@isProduttore = o.IsProduttore,
			@isTrasportatore = o.IsTrasportatore,
			@isDestinatario = o.IsDestinatario,
			@isIntermediario = o.IsIntermediario,
			@isAttivitaRs = o.IsAttivitaRs,
			@isAttivitaProvenienza = o.IsAttivitaProvenienza,
			@totaleQuantitaAssegnata = CASE
				WHEN @NessunaRegistrazioneAssociata = 1 THEN 0
				ELSE
					ISNULL((
						SELECT SUM(lq.Quantita)
						FROM
							dbo.tblRifiutiRegistrazioniRelazioni lq
							INNER JOIN dbo.tblRifiutiRegistrazioni rq ON lq.Id = rq.Id
						WHERE
							lq.IdParent = r.Id
							AND lq.Quantita > 0
							AND rq.Lock < 2
					), 0)
				END
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
		WHERE r.Id = @Id;

		-- Verifica che la registrazione esista
		IF @idMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @idRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Una registrazione già trasmessa a RENTRI non può più essere modificata in alcun modo
		IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può più essere modificata';
			GOTO BRANCH_END;
		END

		-- Una registrazione portata/bloccata per la conservazione sostitutiva non può più essere modificata
		IF ISNULL(@conservazioneSostitutiva, 0) = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è bloccata per la conservazione sostitutiva: non può più essere modificata';
			GOTO BRANCH_END;
		END

		-- Normalizza @isMateriale: NULL (nessuna corrispondenza in tblRifiutiOperazioni) equivale a "non materiale"
		SET @isMateriale = ISNULL(@isMateriale, 0);

		-- Normalizzazione parametri
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdProvenienza = NULLIF(LTRIM(RTRIM(@IdProvenienza)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdAttivitaRs = NULLIF(LTRIM(RTRIM(@IdAttivitaRs)), '');
		SET @IdAttivitaProvenienza = NULLIF(LTRIM(RTRIM(@IdAttivitaProvenienza)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');
		SET @IdUnitaMisura = ISNULL(@IdUnitaMisura, 'KG');
		SET @IdDocumentoTrasportoTipo = NULLIF(LTRIM(RTRIM(@IdDocumentoTrasportoTipo)), '');
		SET @IdAutorizzazioneProduttoreDetentore = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneProduttoreDetentore)), '');
		SET @IdAutorizzazioneDestinatario = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneDestinatario)), '');
		SET @IdAutorizzazioneTrasportatore1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore1)), '');
		SET @IdAutorizzazioneTrasportatore2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore2)), '');
		SET @IdAutorizzazioneTrasportatore3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore3)), '');
		SET @IdAutorizzazioneIntermediario1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario1)), '');
		SET @IdAutorizzazioneIntermediario2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario2)), '');
		SET @IdAutorizzazioneIntermediario3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario3)), '');
		SET @IdEsito = NULLIF(LTRIM(RTRIM(@IdEsito)), '');
		SET @IdCausaleRespingimento = NULLIF(LTRIM(RTRIM(@IdCausaleRespingimento)), '');

		SET @FormularioNumero = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@FormularioNumero, 0, 1));
		SET @ClassiPericolo = dbo.ufnStringhe_get_SenzaSpazi(@ClassiPericolo, 0, 1);
		SET @UtenteNote = dbo.ufnStringhe_get_SenzaSpazi(@UtenteNote, 0, 1);
		SET @RegistrazioneNote = dbo.ufnStringhe_get_SenzaSpazi(@RegistrazioneNote, 0, 1);
		SET @VeicoloFuoriUsoNumero = UPPER(dbo.ufnStringhe_get_SenzaSpazi(@VeicoloFuoriUsoNumero, 0, 1));
		SET @CausaleRespingimentoAltro = dbo.ufnStringhe_get_SenzaSpazi(@CausaleRespingimentoAltro, 0, 1);

		IF @NessunaRegistrazioneAssociata = 1 SET @RegistrazioneAuto = 0;

		IF @RegistrazioneAuto = 1 AND (EXISTS(
			SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @Id
				AND
					(
						(
						[Data] = @RegistrazioneData
						AND Numero = @RegistrazioneNumero
						)
					OR Lock = 2
					)
		))
			SET @RinumeraRegistro = 1;

		IF @QuantitaVerificata = @Quantita
			SET @QuantitaVerificata = NULL;

		-- EER / StatoFisico / ClassiPericolo esclusivi con Materiale; l'unità di misura per il
		-- Materiale è sempre KG, a prescindere da cosa arrivi dal client (campo disabilitato in UI).
		IF @isMateriale = 1
		BEGIN
			SET @IdEer = NULL;
			SET @IdProvenienza = NULL;
			SET @IdStatoFisico = NULL;
			SET @ClassiPericolo = NULL;
			SET @EerDescrizione = NULL;
			SET @IdUnitaMisura = 'KG';
			IF @IdMateriale = 'AL'
				SET @MaterialeDescrizione = dbo.ufnStringhe_get_SenzaSpazi(@MaterialeDescrizione, 0, 1);
			ELSE
				SET @MaterialeDescrizione = NULL;
		END
		ELSE
		BEGIN
			SET @IdMateriale = NULL;
			SET @MaterialeDescrizione = NULL;

			IF @IdEer LIKE '%99'
				SET @EerDescrizione = dbo.ufnStringhe_get_SenzaSpazi(@EerDescrizione, 0, 1);
			ELSE
				SET @EerDescrizione = NULL;
		END

		-- Data inizio trasporto solo se integrazione FIR
		IF @isIntegrazioneFir = 0
			SET @DataInizioTrasporto = NULL;

		-- Attività RS
		IF @isAttivitaRs = 0 OR @IdAttivitaRs = '00'
			SET @IdAttivitaRs = NULL;

		-- Attività Provenienza
		IF @isAttivitaProvenienza = 0 OR @IdAttivitaProvenienza = '0'
			SET @IdAttivitaProvenienza = NULL;

		-- Autorizzazioni: azzera se il ruolo non è previsto per l'operazione, o se è "nessuna" (SediciZeri)
		IF @isProduttore = 0 OR @IdAutorizzazioneProduttoreDetentore = @idSediciZeri
			SET @IdAutorizzazioneProduttoreDetentore = NULL;

		IF @isTrasportatore = 0 OR @IdAutorizzazioneTrasportatore1 = @idSediciZeri
			SET @IdAutorizzazioneTrasportatore1 = NULL;

		IF @isTrasportatore = 0 OR @IdAutorizzazioneTrasportatore2 = @idSediciZeri OR @IdAutorizzazioneTrasportatore1 IS NULL
			SET @IdAutorizzazioneTrasportatore2 = NULL;

		IF @isTrasportatore = 0 OR @IdAutorizzazioneTrasportatore3 = @idSediciZeri OR @IdAutorizzazioneTrasportatore2 IS NULL
			SET @IdAutorizzazioneTrasportatore3 = NULL;

		IF @isDestinatario = 0 OR @IdAutorizzazioneDestinatario = @idSediciZeri
			SET @IdAutorizzazioneDestinatario = NULL;

		-- Autorizzazioni intermediario: gestisce i valori delle 3 possibili autorizzazioni
		IF @isIntermediario = 0 OR @IdAutorizzazioneIntermediario1 = @idSediciZeri
			SET @IdAutorizzazioneIntermediario1 = NULL;

		IF @isIntermediario = 0 OR @IdAutorizzazioneIntermediario2 = @idSediciZeri OR @IdAutorizzazioneIntermediario1 IS NULL
			SET @IdAutorizzazioneIntermediario2 = NULL;

		IF @isIntermediario = 0 OR @IdAutorizzazioneIntermediario3 = @idSediciZeri OR @IdAutorizzazioneIntermediario2 IS NULL
			SET @IdAutorizzazioneIntermediario3 = NULL;

		-- Veicoli fuori uso
		IF
			(
				@idOperazione <> 'Z' -- Carico di rifiuto ricevuti da terzi
				OR
				ISNULL(@IdEer, '') NOT IN('160104', '160106') -- EER per veicoli fuori uso
			)
		BEGIN
			SET @IsVeicoloFuoriUso = 0;
			SET @VeicoloFuoriUsoNumero = NULL;
			SET @VeicoloFuoriUsoData = NULL;
		END

		-- Categoria RAEE
		IF
			(
				@IdRaee = '0'
				OR
				@idOperazione NOT IN('S', 'Z')
				OR
				ISNULL(@IdEer, '') NOT IN('200121', '200123', '200135', '200136', '160210', '160211', '160212', '160213', '160214', '160215', '160216')
			)
		BEGIN
			SET @IdRaee = NULL;
		END

		-- Esito
		IF @isEsito = 0 OR @IdEsito = '0'
		BEGIN
			SET @IdEsito = NULL;
			SET @QuantitaVerificata = NULL;
			SET @DataFineTrasporto = NULL;
			SET @IdCausaleRespingimento = NULL;
			SET @CausaleRespingimentoAltro = NULL;
			SET @QuantitaRespinta = NULL;
			SET @IdUnitaMisuraQuantitaRespinta = NULL;
		END
		ELSE
		BEGIN
			IF @IdEsito = 'A' SET @IdCausaleRespingimento = NULL;
			IF @IdEsito = 'A' SET @CausaleRespingimentoAltro = NULL;
			IF @IdEsito = 'A' SET @IdUnitaMisuraQuantitaRespinta = NULL;
			IF @IdEsito = 'A' SET @QuantitaRespinta = NULL;
			IF @IdEsito = 'R' SET @QuantitaRespinta = @Quantita;
			IF @IdEsito = 'R' SET @IdUnitaMisuraQuantitaRespinta = @IdUnitaMisura;
			IF @IdEsito = 'R' SET @QuantitaVerificata = NULL;
			IF @IdEsito = 'P' SET @IdUnitaMisuraQuantitaRespinta = ISNULL(@IdUnitaMisuraQuantitaRespinta, 'KG');
			IF ISNULL(@IdCausaleRespingimento, '') <> 'A' SET @CausaleRespingimentoAltro = NULL;
		END

		IF @isFormularioAssociato = 1 AND @FormularioNumero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questa registrazione è associata ad un formulario. Il numero deve essere valorizzato';
			GOTO BRANCH_END;
		END

		IF @isIntegrazioneFir = 1
		BEGIN
			-- Verifica l'unicità del numero di formulario solo contro registrazioni attive
			-- (r.Lock < 2), non contro il solo elenco dei formulari: un formulario può
			-- esistere senza alcuna registrazione associata (creato standalone da Formulari),
			-- nel qual caso non deve bloccare il riutilizzo del suo numero.
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					r.Id <> @Id
					AND m.IdRegistro = @idRegistro
					AND r.Lock < 2
					AND m.FormularioNumero = @FormularioNumero
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''altra registrazione con lo stesso numero di formulario è già presente';
				GOTO BRANCH_END;
			END
		END

		IF @RegistrazioneNumero + @RegistrazioneAuto > 999999
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero di registrazione non può essere superiore a 999.999';
			GOTO BRANCH_END;
		END

		-- Controllo EER/stato fisico/unità di misura nelle relazioni
		IF @lock < 2 AND @idOperazione <> 'K'
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
					-- Valori effettivi della registrazione associata (ultima rettifica di correzione
					-- confermata, l'originale non viene mai modificato - viewRifiutiRegistrazioniEffettive)
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
					INNER JOIN dbo.tblRifiutiMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					(
					l.Id = @Id
					OR l.IdParent = @Id
					)
					AND mp.IdOperazione <> 'M'
					AND
						(
						v.IdEer <> @IdEer
						OR v.IdStatoFisico <> @IdStatoFisico
						OR v.IdUnitaMisura <> @IdUnitaMisura
						)
					AND l.Quantita > 0
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è associata ad altre con differente EER e/o stato fisico e/o unità di misura';
				GOTO BRANCH_END;
			END
		END

		-- I controlli sul numero di registrazione (duplicato, ordine rispetto alla data) e il calcolo della
		-- rinumerazione sono dentro la transazione, dopo il blocco sul registro: vedi sotto

		-- Controllo data relazioni padre
		IF @lock < 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
				WHERE
					l.Id = @Id
					AND
						(
						rp.[Data] < @RegistrazioneData
						OR
							(
							rp.[Data] = @RegistrazioneData
							AND rp.Numero < @RegistrazioneNumero
							)
						)
					AND l.Quantita > 0
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è associata ad altre con numero e/o data di registrazione inferiore';
				GOTO BRANCH_END;
			END
		END

		-- Controllo quantità già scaricata (l.Id = @Id: verifica che @Id, come figlio, non scenda sotto quanto già scaricato dal padre)
		IF @lock < 2
		BEGIN
			IF @Quantita < ISNULL((
				SELECT SUM(l.Quantita)
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
					INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON rp.Id = vp.Id
				WHERE
					l.Id = @Id
					AND l.Quantita > 0
					AND rp.Lock < 2
					-- Uno scarico annullato non consuma piu' la registrazione (relazione mantenuta per la stampa)
					AND vp.IsAnnullata = 0
			), 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità non può essere inferiore a quella già associata ad altre registrazioni';
				GOTO BRANCH_END;
			END
		END

		-- Verifica quantità superiore disponibile
		IF @NessunaRegistrazioneAssociata = 0 AND EXISTS (SELECT 1
		FROM dbo.tblRifiutiOperazioniRelazioni
		WHERE Id = @idOperazione) AND @RegistrazioneAuto = 0
		BEGIN
			IF dbo.ufnRifiutiRegistrazioni_get_IsQuantitaSuperiore(
				@Id, @Quantita, @RegistrazioneData, @RegistrazioneNumero,
				@IdEer, @IdStatoFisico, @IdUnitaMisura, 0) > 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità registrata è superiore a quella disponibile nelle registrazioni associate';
				GOTO BRANCH_END;
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
					LEFT JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
					LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
				WHERE
					m.Id = @idMovimento
					AND
						(
						ISNULL(m.IdEer, '000000') <> ISNULL(@IdEer, '000000')
						OR ISNULL(m.IdStatoFisico, '0') <> ISNULL(@IdStatoFisico, '0')
						OR ISNULL(r.IdMateriale, '00') <> ISNULL(@IdMateriale, '00')
						OR ISNULL(m.IdAttivita, '00') <> ISNULL(@IdAttivitaRs, '00')
						OR ISNULL(r.Numero, -1) <> ISNULL(@RegistrazioneNumero, -1)
						OR ISNULL(r.[Data], @minData) <> ISNULL(@RegistrazioneData, @minData)
						OR ISNULL(m.IdUnitaMisura, '0') <> ISNULL(@IdUnitaMisura, '0')
						OR ISNULL(m.Quantita, 0) <> ISNULL(@Quantita, 0)
						OR ISNULL(r.QuantitaVerificata, 0) <> ISNULL(@QuantitaVerificata, 0)
						OR ISNULL(m.FormularioNumero, '') <> ISNULL(@FormularioNumero, '')
						OR ISNULL(m.DataInizioTrasporto, @minData) <> ISNULL(@DataInizioTrasporto, @minData)
						OR ISNULL(r.DataFineTrasporto, @minData) <> ISNULL(@DataFineTrasporto, @minData)
						)
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
					AND
						(
						ISNULL(mp1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneProduttoreDetentore, @idSediciZeri)
						OR ISNULL(md.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneDestinatario, @idSediciZeri)
						OR ISNULL(mt1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneTrasportatore1, @idSediciZeri)
						OR ISNULL(mi1.IdAutorizzazione, @idSediciZeri) <> ISNULL(@IdAutorizzazioneIntermediario1, @idSediciZeri)
						)
			)
				SET @aggiornaLog = 1;
		END

		-- Calcola la soglia per la pulizia del log (fuori dalla transazione, intenzionale)
		-- Se ci sono 10 o meno record @dataLogMin resta NULL: il DELETE successivo non elimina nulla (comportamento corretto)
		DECLARE @dataLogMin DATETIME2(0);

		-- Lettura IdUtente fuori dalla transazione (intenzionale)
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

			SELECT @idUtente = IdUtente
			FROM dbo.tblSessioni
			WHERE Id = @IdSessione;
		END

		BEGIN TRANSACTION;

			-- Numerazione: il registro viene bloccato per tutta la transazione (UPDLOCK/HOLDLOCK sulla sua sola
			-- riga), cosi' due salvataggi contemporanei sullo stesso registro si mettono in fila e non possono
			-- leggere lo stesso ultimo numero. Registri diversi e letture non aspettano. Il registro si blocca
			-- sempre per primo, prima delle relazioni (stesso ordine in _upd_Rettifica e _upd_Annullamento)
			DECLARE @registroBloccato CHAR(16) = (
				SELECT Id
				FROM dbo.tblRifiutiRegistri WITH (UPDLOCK, HOLDLOCK)
				WHERE Id = @idRegistro);

			-- Controllo numero registrazione duplicato (sargable)
			IF @RinumeraRegistro = 0
			BEGIN
				IF EXISTS (
					SELECT 1
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					WHERE
						r.Lock < 2
						AND m.IdRegistro = @idRegistro
						AND r.[Data] >= @annoInizio
						AND r.[Data] < @annoFine
						AND r.Numero = @RegistrazioneNumero
						AND r.Id <> @Id
				)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Un''altra registrazione con lo stesso numero è già presente';
					GOTO BRANCH_END;
				END
			END

			-- Controllo numero > con data < (sargable)
			IF @RinumeraRegistro = 0
			BEGIN
				IF EXISTS (
					SELECT 1
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					WHERE
						r.Lock < 2
						AND m.IdRegistro = @idRegistro
						AND r.[Data] >= @annoInizio
						AND r.[Data] < @annoFine
						AND r.Numero > @RegistrazioneNumero
						AND r.[Data] < @RegistrazioneData
						AND r.Id <> @Id
				)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Almeno una registrazione con numero maggiore e data inferiore a quella indicata è già presente';
					GOTO BRANCH_END;
				END
			END

			-- Controllo numero < con data > (sargable)
			IF @RinumeraRegistro = 0
			BEGIN
				IF EXISTS (
					SELECT 1
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					WHERE
						r.Lock < 2
						AND m.IdRegistro = @idRegistro
						AND r.[Data] >= @annoInizio
						AND r.[Data] < @annoFine
						AND r.Numero < @RegistrazioneNumero
						AND r.[Data] > @RegistrazioneData
						AND r.Id <> @Id
				)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Almeno una registrazione con numero inferiore e data maggiore a quella indicata è già presente';
					GOTO BRANCH_END;
				END
			END

			-- Rinumerazione registro (sargable)
			IF @RinumeraRegistro = 1
			BEGIN
				DECLARE @isLibero1 BIT = 0;
				DECLARE @isLibero2 BIT = 0;

				IF @lock = 2
					SET @RegistrazioneNumero = 1 +
						(SELECT ISNULL(MAX(r.Numero), 0)
						 FROM
							 dbo.tblRifiutiRegistrazioni r
							 INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
						 WHERE
							 r.Lock < 2
							 AND m.IdRegistro = @idRegistro
							 AND r.[Data] <= @RegistrazioneData
							 AND r.[Data] >= @annoInizio
							 AND r.[Data] < @annoFine
						);

				SET @isLibero1 = IIF(EXISTS (
					SELECT 1
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					WHERE
						r.Lock < 2
						AND m.IdRegistro = @idRegistro
						AND r.Numero = @RegistrazioneNumero
						AND r.[Data] >= @annoInizio
						AND r.[Data] < @annoFine
				), 0, 1);

				SET @isLibero2 = IIF(EXISTS (
					SELECT 1
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					WHERE
						r.Lock < 2
						AND m.IdRegistro = @idRegistro
						AND r.Numero = @RegistrazioneNumero + 1
						AND r.[Data] >= @annoInizio
						AND r.[Data] < @annoFine
				), 0, 1);
			END

			IF @RinumeraRegistro = 1
			BEGIN
				UPDATE r
				SET Numero = Numero + 1 + IIF(@lock = 2 AND @RegistrazioneAuto = 1 AND @isLibero1 = 0, 1, 0)
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					r.Lock < 2
					AND m.IdRegistro = @idRegistro
					AND
						(
						r.[Data] > @RegistrazioneData
						OR
							(
							r.[Data] = @RegistrazioneData
							AND r.Numero > @RegistrazioneNumero
							)
						)
					AND r.[Data] >= @annoInizio
					AND r.[Data] < @annoFine
					AND
						(
							(
							@lock < 2
							AND @isLibero2 = 0
							)
						OR
							(
							@lock = 2
							AND @RegistrazioneAuto = 1
							AND
								(
								@isLibero1 = 0
								OR @isLibero2 = 0
								)
							)
						OR
							(
							@lock = 2
							AND @RegistrazioneAuto = 0
							AND @isLibero1 = 0
							)
						);
			END

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
				INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @IdAutorizzazioneTrasportatore1, 0);

				IF @IdAutorizzazioneTrasportatore2 IS NOT NULL
				BEGIN
					INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @IdAutorizzazioneTrasportatore2, 1);

					IF @IdAutorizzazioneTrasportatore3 IS NOT NULL
					BEGIN
						INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @IdAutorizzazioneTrasportatore3, 2);
					END
				END
			END

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

			-- Relazioni quantità
			IF @Quantita = 0 OR @NessunaRegistrazioneAssociata = 1
			BEGIN
				DELETE dbo.tblRifiutiRegistrazioniRelazioni
				WHERE IdParent = @Id;
			END

			IF @NessunaRegistrazioneAssociata = 0 AND @Quantita > 0 AND @Quantita <> @totaleQuantitaAssegnata
			BEGIN
				UPDATE dbo.tblRifiutiRegistrazioniRelazioni
				SET Quantita = 0
				WHERE IdParent = @Id;

				SET @quantitaRelazione = @Quantita;

				-- Distribuzione quantità sulle relazioni ordinate per Pos
				DECLARE c CURSOR FAST_FORWARD FOR
					SELECT
						l.Id,
						-- Valori effettivi (viewRifiutiRegistrazioniEffettive): quantita' dell'ultima correzione
						-- confermata, 0 se annullata; uno scarico annullato non consuma piu' i suoi carichi
						QuantitaResidua = v2.Quantita - ISNULL(a.Quantita, 0)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l
						INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v2 ON r.Id = v2.Id
						LEFT JOIN (
							SELECT lq.Id, Quantita = SUM(lq.Quantita)
							FROM
								dbo.tblRifiutiRegistrazioniRelazioni lq
								INNER JOIN dbo.tblRifiutiRegistrazioni pq ON lq.IdParent = pq.Id
								INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vpq ON pq.Id = vpq.Id
							WHERE
								pq.Lock < 2
								AND vpq.Quantita > 0
							GROUP BY lq.Id
						) a ON l.Id = a.Id
					WHERE l.IdParent = @Id
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
								IdParent = @Id
								AND Id = @idRelazione;
							SET @quantitaRelazione = @quantitaRelazione - @quantitaResidua;
						END
						ELSE
						BEGIN
							UPDATE dbo.tblRifiutiRegistrazioniRelazioni
							SET Quantita = @quantitaRelazione
							WHERE
								IdParent = @Id
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
				IdParent = @Id
				AND Quantita = 0;

			-- Generazione registrazione automatica di compensazione
			IF @quantitaRelazione > 0 AND @RegistrazioneAuto = 1
			BEGIN
				DECLARE @idMovimentoAuto CHAR(16);
				DECLARE @idRegistrazioneAuto CHAR(16);

				EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimentoAuto OUTPUT;
				EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idRegistrazioneAuto OUTPUT;

				INSERT dbo.tblRifiutiMovimenti (Id, IdRegistro, IdOperazione, IdEer, IdProvenienza, IdStatoFisico, IdUnitaMisura, Quantita)
				VALUES (@idMovimentoAuto, @idRegistro, 'C', @IdEer, @IdProvenienza, @IdStatoFisico, @IdUnitaMisura, @quantitaRelazione);

				INSERT dbo.tblRifiutiRegistrazioni
					(Id, IdMovimento, Operazione, [Data], Numero, Lock)
				VALUES
					(@idRegistrazioneAuto, @idMovimentoAuto, 'C',
					 @RegistrazioneData, @RegistrazioneNumero, 0);

				INSERT dbo.tblRifiutiRegistrazioniRelazioni
					(Id, IdParent, Operazione, Quantita, Pos)
				SELECT
					@idRegistrazioneAuto, @Id, 'S', @quantitaRelazione,
					ISNULL(MAX(Pos), -1) + 1
				FROM dbo.tblRifiutiRegistrazioniRelazioni
				WHERE IdParent = @Id;

				INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
				VALUES (@idMovimentoAuto, @IdAutorizzazioneProduttoreDetentore, @quantitaRelazione, 0);

				INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
				SELECT @idMovimentoAuto, c.Id
				FROM
					dbo.tblRifiutiClassiPericolo c
					INNER JOIN STRING_SPLIT(@ClassiPericolo, ';') v ON c.Id = v.value;

				INSERT dbo.tblRifiutiRegistrazioniEtichette (Id, IdEtichetta)
				SELECT TOP 3 @idRegistrazioneAuto, e.Id
				FROM
					dbo.tblEtichette e
					INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

				SET @RegistrazioneNumero = @RegistrazioneNumero + 1;
			END

			-- Classi di pericolo
			DELETE dbo.tblRifiutiMovimentiClassiPericolo
			WHERE Id = @idMovimento;

			INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
			SELECT @idMovimento, c.Id
			FROM
				dbo.tblRifiutiClassiPericolo c
				INNER JOIN STRING_SPLIT(@ClassiPericolo, ';') v ON c.Id = v.value;

			-- Etichette
			DELETE dbo.tblRifiutiRegistrazioniEtichette
			WHERE Id = @Id;

			INSERT dbo.tblRifiutiRegistrazioniEtichette (Id, IdEtichetta)
			SELECT TOP 3 @Id, e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

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
					LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
					LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt ON m.Id = mt.Id AND mt.Pos = 0
					LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi ON m.Id = mi.Id AND mi.Pos = 0
				WHERE m.Id = @idMovimento;
			END

			-- Azzera FormularioNumero se il documento non è un formulario
			IF ISNULL(@IdDocumentoTrasportoTipo, 'F') <> 'F'
				SET @FormularioNumero = NULL;

			-- Se il documento non è un formulario (tipo <> 'F') elimina il formulario associato
			IF ISNULL(@IdDocumentoTrasportoTipo, 'F') <> 'F' AND @idFormulario IS NOT NULL
			BEGIN
				DELETE dbo.tblRifiutiFormulari
				WHERE Id = @idFormulario;
				DELETE dbo.tblIdLog
				WHERE Id = @idMovimento;
				DELETE dbo.tblId
				WHERE Id = @idMovimento;
			END

			-- Aggiornamento registrazione
			UPDATE dbo.tblRifiutiRegistrazioni
			SET
				[Data] = @RegistrazioneData,
				Numero = @RegistrazioneNumero,
				IdTrasportoTransfrontalieroTipo = IIF(@IdDocumentoTrasportoTipo <> 'F', @IdDocumentoTrasportoTipo, NULL),
				Note = @RegistrazioneNote,
				Etichette = dbo.ufnRifiutiRegistrazioni_get_Etichette(Id),
				VeicoloFuoriUso = @IsVeicoloFuoriUso,
				VeicoloFuoriUsoData = @VeicoloFuoriUsoData,
				VeicoloFuoriUsoNumero = @VeicoloFuoriUsoNumero,
				IdRaee = @IdRaee,
				IdEsito = @IdEsito,
				IdCausaleRespingimento = @IdCausaleRespingimento,
				CausaleRespingimentoAltro = @CausaleRespingimentoAltro,
				QuantitaVerificata = @QuantitaVerificata,
				IdUnitaMisuraQuantitaRespinta = @IdUnitaMisuraQuantitaRespinta,
				QuantitaRespinta = @QuantitaRespinta,
				DataFineTrasporto = @DataFineTrasporto,
				IdMateriale = @IdMateriale,
				MaterialeDescrizione = @MaterialeDescrizione,
				IdAttivitaProvenienza = @IdAttivitaProvenienza,
				Lock = 0
			WHERE Id = @Id;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Registrazione non trovata o già modificata da un altro utente';
				GOTO BRANCH_END;
			END

			-- Aggiornamento movimento
			UPDATE m
			SET
				IdEer = @IdEer,
				IdProvenienza = @IdProvenienza,
				EerDescrizione = @EerDescrizione,
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

			-- Magazzino EoW allineato al registro operativo: una M con quantita' ridotta o materiale cambiato
			-- riduce/rimuove le proprie allocazioni sui lotti (nessun effetto senza allocazioni o su una
			-- rettifica, che non ne ha mai)
			EXEC dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea @IdRegistrazione = @Id;

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
GO

PRINT 'uspRifiutiRegistrazioni_ins_CaricoAuto.sql';
GO
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

		-- Il prossimo numero disponibile per Registro/anno si legge dentro la transazione, dopo il blocco
		-- sul registro (vedi sotto)
		DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@data), 1, 1);
		DECLARE @annoFine DATE = DATEFROMPARTS(YEAR(@data) + 1, 1, 1);
		DECLARE @numero INT;

		DECLARE @idMovimento CHAR(16);

		-- uspId_get gestisce la propria transazione internamente: chiamate FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		-- @returnId è appena stato generato in questa stessa esecuzione: non può già esistere
		-- nessuna relazione con IdParent = @returnId, la posizione è sempre 0 (stesso schema di
		-- calcolo di uspRifiutiRegistrazioni_ins_Relazione, qui degenera per costruzione).
		DECLARE @pos INT = 0;

		BEGIN TRANSACTION;

			-- Numerazione: il registro viene bloccato per tutta la transazione (UPDLOCK/HOLDLOCK sulla sua sola
			-- riga), come in uspRifiutiRegistrazioni_upd: due operazioni contemporanee sullo stesso registro si
			-- mettono in fila e non possono leggere lo stesso ultimo numero
			DECLARE @registroBloccato CHAR(16) = (
				SELECT Id
				FROM dbo.tblRifiutiRegistri WITH (UPDLOCK, HOLDLOCK)
				WHERE Id = @idRegistro);

			-- Prossimo numero disponibile per Registro/anno (stesso schema di uspRifiutiRegistrazioni_upd,
			-- ramo di rinumerazione: 1 + MAX(Numero) tra le registrazioni confermate/bozza dell'anno)
			SET @numero = 1 + ISNULL((
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

PRINT 'uspRifiutiRegistrazioni_upd_Numerazione.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rinumera le registrazioni del registro del contesto (tblSessioni.IdRegistro) con data nell'anno @Anno e
-- numero tra @DalNumero e @AlNumero: ricevono numeri consecutivi a partire da @PrimoNumero, nell'ordine di
-- data e numero attuali. Un intervallo che contiene registrazioni già inviate al RENTRI non si rinumera.
-- Restituisce il numero di registrazioni rinumerate.
CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistrazioni_upd_Numerazione
	@IdSessione CHAR(16) = NULL,
	@DalNumero INT = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL,
	@PrimoNumero INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DalNumero IS NULL OR @AlNumero IS NULL OR @Anno IS NULL OR @PrimoNumero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare l''intervallo dei numeri, l''anno e il primo numero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: registro corrente della sessione. Un anno fuori dall'intervallo delle date non ha registrazioni
		DECLARE @idRegistro CHAR(16) = (SELECT IdRegistro FROM dbo.tblSessioni WHERE Id = @IdSessione);

		IF @idRegistro IS NULL OR @Anno < 1900 OR @Anno > 2100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non ci sono registrazioni nell''intervallo indicato';
			GOTO BRANCH_END;
		END

		DECLARE @annoInizio DATE = DATEFROMPARTS(@Anno, 1, 1);
		DECLARE @annoFine DATE = DATEFROMPARTS(@Anno + 1, 1, 1);
		DECLARE @totaleDaRinumerare INT;

		BEGIN TRANSACTION;

			-- Numerazione: il registro viene bloccato per tutta la transazione (UPDLOCK/HOLDLOCK sulla sua sola
			-- riga), come in uspRifiutiRegistrazioni_upd: un salvataggio contemporaneo sullo stesso registro
			-- attende la fine della rinumerazione e non può prendere un numero dell'intervallo in corso di modifica
			DECLARE @registroBloccato CHAR(16) = (
				SELECT Id
				FROM dbo.tblRifiutiRegistri WITH (UPDLOCK, HOLDLOCK)
				WHERE Id = @idRegistro);

			SELECT @totaleDaRinumerare = COUNT(*)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			WHERE
				m.IdRegistro = @idRegistro
				AND r.Lock < 2
				AND r.[Data] >= @annoInizio
				AND r.[Data] < @annoFine
				AND r.Numero BETWEEN @DalNumero AND @AlNumero;

			-- Se non c'è nulla da rinumerare
			IF @totaleDaRinumerare = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Non ci sono registrazioni nell''intervallo indicato';
				GOTO BRANCH_END;
			END

			-- Se l'intervallo contiene registrazioni già inviate a RENTRI: il Numero/Anno trasmesso
			-- non può più essere modificato, pena il disallineamento con quanto RENTRI ha registrato
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					m.IdRegistro = @idRegistro
					AND r.Lock < 2
					AND r.[Data] >= @annoInizio
					AND r.[Data] < @annoFine
					AND r.Numero BETWEEN @DalNumero AND @AlNumero
					AND (r.RentriIdentificativo IS NOT NULL OR r.RentriData IS NOT NULL)
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'L''intervallo contiene registrazioni già inviate al RENTRI: non possono essere rinumerate';
				GOTO BRANCH_END;
			END

			-- Se la numerazione finale supera 999.999
			IF @PrimoNumero + @totaleDaRinumerare > 999999
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La rinumerazione non può assegnare numeri maggiori di 999.999';
				GOTO BRANCH_END;
			END

			-- Se la nuova rinumerazione entra in conflitto con altre registrazioni al di fuori del gruppo che sarà rinumerato
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					m.IdRegistro = @idRegistro
					AND r.Lock < 2
					AND r.[Data] >= @annoInizio
					AND r.[Data] < @annoFine
					AND r.Numero NOT BETWEEN @DalNumero AND @AlNumero
					AND r.Numero BETWEEN @PrimoNumero AND @PrimoNumero + @totaleDaRinumerare
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La nuova numerazione è in conflitto con quella di altre registrazioni';
				GOTO BRANCH_END;
			END

			UPDATE r
			SET Numero = t.NumeroBase + @PrimoNumero - 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN
					(
						SELECT
							r.Id,
							NumeroBase = ROW_NUMBER() OVER (ORDER BY r.[Data], r.Numero)
						FROM
							dbo.tblRifiutiRegistrazioni r
							INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
						WHERE
							m.IdRegistro = @idRegistro
							AND r.Lock < 2
							AND r.[Data] >= @annoInizio
							AND r.[Data] < @annoFine
							AND r.Numero BETWEEN @DalNumero AND @AlNumero
					) t ON r.Id = t.Id;

			SET @returnValue = @@ROWCOUNT;

		COMMIT TRANSACTION;

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
GO
GO

PRINT 'uspRifiutiRegistrazioni_upd_Rettifica.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Salvataggio dedicato per una registrazione di rettifica (@Id, collegata a un originale via
-- tblRentriRegistrazioniRettifiche.IdRettifica). Riusa integralmente uspRifiutiRegistrazioni_upd per
-- salvare la rettifica stessa (stessa validazione Data/Numero/rinumerazione/autorizzazioni/esito/ecc. di
-- una registrazione normale - la rettifica non è ancora inviata al RENTRI, quindi il blocco "già inviata"
-- di quella SP non la riguarda). Stato amministrativo e stato operativo sono separati: la rettifica viene
-- sempre salvata con i valori indicati (sono quelli trasmessi al RENTRI) e le relazioni carico/scarico non la
-- bloccano mai; l'originale non viene mai modificato. Alla conferma i valori OPERATIVI (giacenze, residui,
-- relazioni - viewRifiutiRegistrazioniEffettive) vengono scritti nella riga di tblRentriRegistrazioniRettifiche:
-- i nuovi valori se non rendono incoerenti le relazioni dell'originale, altrimenti tutti quelli operativi
-- precedenti ("tutto o niente", ufnRifiutiRegistrazioni_get_RettificaOperativa). Ogni salvataggio prima
-- dell'invio ricalcola la decisione; dopo l'invio la rettifica non e' piu' modificabile e la decisione resta.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_upd_Rettifica]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdProvenienza CHAR(1) = NULL,
	@EerDescrizione VARCHAR(200) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@ClassiPericolo VARCHAR(50) = NULL,
	@IdAttivitaRs CHAR(2) = NULL,
	@RegistrazioneData DATE = NULL,
	@RegistrazioneNumero INT = 0,
	@IdUnitaMisura CHAR(2) = NULL,
	@Quantita DECIMAL(18,2) = 0,
	@DataInizioTrasporto SMALLDATETIME = NULL,
	@IdDocumentoTrasportoTipo CHAR(1) = NULL,
	@FormularioNumero VARCHAR(20) = NULL,
	@IdAutorizzazioneProduttoreDetentore CHAR(16) = NULL,
	@IdAutorizzazioneDestinatario CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore1 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore2 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore3 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario1 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario2 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario3 CHAR(16) = NULL,
	@RegistrazioneNote VARCHAR(500) = NULL,
	@UtenteNote VARCHAR(500) = NULL,
	@IdEtichette VARCHAR(50) = NULL,

	@IsVeicoloFuoriUso BIT = 0,
	@VeicoloFuoriUsoNumero VARCHAR(50) = NULL,
	@VeicoloFuoriUsoData DATE = NULL,

	@IdRaee CHAR(1) = NULL,

	-- Esito
	@IdEsito CHAR(1) = NULL,
	@QuantitaVerificata DECIMAL(18,2) = NULL,
	@DataFineTrasporto SMALLDATETIME = NULL,
	@IdCausaleRespingimento CHAR(1) = NULL,
	@CausaleRespingimentoAltro VARCHAR(100) = NULL,
	@IdUnitaMisuraQuantitaRespinta CHAR(2) = NULL,
	@QuantitaRespinta DECIMAL(18,2) = NULL,

	-- Materiale
	@IdMateriale CHAR(2) = NULL,
	@MaterialeDescrizione VARCHAR(200) = NULL,

	-- Provenienza
	@IdAttivitaProvenienza CHAR(1) = NULL,

	@RegistrazioneAuto BIT = 0,
	@RinumeraRegistro BIT = 0
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

		-- Permesso + titolarità su @Id, PRIMA di leggere qualunque dato suo o dell'originale collegato
		-- (stesso pattern di uspRifiutiRegistrazioni_ins/_del - evita di esporre valori/relazioni
		-- dell'originale a una sessione senza diritti su questa specifica registrazione)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idOriginale CHAR(16) = (SELECT Id
		FROM dbo.tblRentriRegistrazioniRettifiche
		WHERE IdRettifica = @Id);

		IF @idOriginale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non è una rettifica';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Il registro si blocca per primo, prima delle relazioni: è lo stesso ordine di
			-- uspRifiutiRegistrazioni_upd (che blocca il registro per la numerazione), cosi' una rettifica e un
			-- salvataggio contemporanei sullo stesso registro si mettono in fila invece di bloccarsi a vicenda
			DECLARE @registroBloccato CHAR(16) = (
				SELECT g.Id
				FROM dbo.tblRifiutiRegistri g WITH (UPDLOCK, HOLDLOCK)
				WHERE g.Id = (
					SELECT m.IdRegistro
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					WHERE r.Id = @Id));

			-- Relazioni carico/scarico dell'originale bloccate fino alla fine della transazione
			-- (UPDLOCK/HOLDLOCK): una nuova associazione sull'originale attende la conferma di questa
			-- rettifica, cosi' la decisione sui valori operativi presa sotto resta valida.
			DECLARE @relazioniOriginale INT = (SELECT COUNT(*)
			FROM dbo.tblRifiutiRegistrazioniRelazioni WITH (UPDLOCK, HOLDLOCK)
			WHERE
				Id = @idOriginale
				OR IdParent = @idOriginale
			);

			EXEC dbo.uspRifiutiRegistrazioni_upd
				@Id = @Id,
				@IdSessione = @IdSessione,
				@IdEer = @IdEer,
				@IdProvenienza = @IdProvenienza,
				@EerDescrizione = @EerDescrizione,
				@IdStatoFisico = @IdStatoFisico,
				@ClassiPericolo = @ClassiPericolo,
				@IdAttivitaRs = @IdAttivitaRs,
				@RegistrazioneData = @RegistrazioneData,
				@RegistrazioneNumero = @RegistrazioneNumero,
				@IdUnitaMisura = @IdUnitaMisura,
				@Quantita = @Quantita,
				@DataInizioTrasporto = @DataInizioTrasporto,
				@IdDocumentoTrasportoTipo = @IdDocumentoTrasportoTipo,
				@FormularioNumero = @FormularioNumero,
				@IdAutorizzazioneProduttoreDetentore = @IdAutorizzazioneProduttoreDetentore,
				@IdAutorizzazioneDestinatario = @IdAutorizzazioneDestinatario,
				@IdAutorizzazioneTrasportatore1 = @IdAutorizzazioneTrasportatore1,
				@IdAutorizzazioneTrasportatore2 = @IdAutorizzazioneTrasportatore2,
				@IdAutorizzazioneTrasportatore3 = @IdAutorizzazioneTrasportatore3,
				@IdAutorizzazioneIntermediario1 = @IdAutorizzazioneIntermediario1,
				@IdAutorizzazioneIntermediario2 = @IdAutorizzazioneIntermediario2,
				@IdAutorizzazioneIntermediario3 = @IdAutorizzazioneIntermediario3,
				@RegistrazioneNote = @RegistrazioneNote,
				@UtenteNote = @UtenteNote,
				@IdEtichette = @IdEtichette,
				@IsVeicoloFuoriUso = @IsVeicoloFuoriUso,
				@VeicoloFuoriUsoNumero = @VeicoloFuoriUsoNumero,
				@VeicoloFuoriUsoData = @VeicoloFuoriUsoData,
				@IdRaee = @IdRaee,
				@IdEsito = @IdEsito,
				@QuantitaVerificata = @QuantitaVerificata,
				@DataFineTrasporto = @DataFineTrasporto,
				@IdCausaleRespingimento = @IdCausaleRespingimento,
				@CausaleRespingimentoAltro = @CausaleRespingimentoAltro,
				@IdUnitaMisuraQuantitaRespinta = @IdUnitaMisuraQuantitaRespinta,
				@QuantitaRespinta = @QuantitaRespinta,
				@IdMateriale = @IdMateriale,
				@MaterialeDescrizione = @MaterialeDescrizione,
				@IdAttivitaProvenienza = @IdAttivitaProvenienza,
				@RegistrazioneAuto = @RegistrazioneAuto,
				@RinumeraRegistro = @RinumeraRegistro,
				-- Sempre 1: una rettifica non partecipa mai al grafo carichi/scarichi (punto 3 della
				-- specifica) - non è un parametro esposto al chiamante, bypassa anche il controllo
				-- "quantità disponibile nelle registrazioni associate" che non ha senso qui
				@NessunaRegistrazioneAssociata = 1;

			-- Valori operativi (vedi header), calcolati sui valori appena salvati nel movimento della
			-- rettifica (gia' normalizzati da uspRifiutiRegistrazioni_upd, es. KG per il Materiale)
			UPDATE t
			SET
				t.IdEer = IIF(o.IsOperativa = 1, m.IdEer, o.IdEer),
				t.EerDescrizione = IIF(o.IsOperativa = 1, m.EerDescrizione, o.EerDescrizione),
				t.IdStatoFisico = IIF(o.IsOperativa = 1, m.IdStatoFisico, o.IdStatoFisico),
				t.IdUnitaMisura = IIF(o.IsOperativa = 1, m.IdUnitaMisura, o.IdUnitaMisura),
				t.Quantita = IIF(o.IsOperativa = 1, m.Quantita, o.Quantita)
			FROM
				dbo.tblRentriRegistrazioniRettifiche t
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON t.IdRettifica = r.Id
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				CROSS APPLY dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(t.IdRettifica, m.IdEer, m.IdStatoFisico, m.IdUnitaMisura, m.Quantita) o
			WHERE t.IdRettifica = @Id;

			-- Magazzino EoW allineato al registro operativo: se la correzione riduce la quantita' operativa di
			-- una M, le sue allocazioni sui lotti si riducono (correzione non operativa: nessun effetto)
			EXEC dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea @IdRegistrazione = @idOriginale;

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
GO

PRINT 'uspRifiutiRegistrazioni_upd_Annullamento.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Salvataggio dedicato per una registrazione di rettifica di ANNULLAMENTO (@Id, collegata a un
-- originale via tblRentriRegistrazioniRettifiche.IdRettifica/Annullata=1 - vedi
-- uspRifiutiRegistrazioni_upd_Rettifica per la sotto-tipologia di correzione, stessa tabella di
-- tracking). A differenza della correzione, un annullamento non ha ALCUN campo modificabile
-- dall'utente eccetto le note (RegistrazioneNote, obbligatorie: riportano il motivo dell'annullamento
-- e diventano "annotazioni" nel payload RENTRI - vedi viewRentriRegistrazioni.RettificaIsAnnullata,
-- l'hub 1_0_RentriApi traduce la riga in un "AnnullamentoMovimento" che trasmette solo il riferimento
-- alla registrazione annullata + data + annotazioni, nessun altro campo rifiuto). Numero/Data di
-- registrazione restano quelli calcolati automaticamente (nessuna UI li espone in modifica) ma vengono
-- comunque passati a uspRifiutiRegistrazioni_upd per la sua validazione standard. Tutti gli altri campi
-- vengono riletti invariati dalla riga stessa (snapshot copiato dall'originale al momento dell'INSERT,
-- mai più toccato) e passati pari pari a uspRifiutiRegistrazioni_upd. Come la correzione, un annullamento
-- non modifica mai l'originale e non e' mai bloccato dalle relazioni carico/scarico (l'annullamento va sempre
-- trasmesso al RENTRI). Alla conferma i valori OPERATIVI vengono scritti nella riga di
-- tblRentriRegistrazioniRettifiche (ufnRifiutiRegistrazioni_get_RettificaOperativa): Quantita = 0 (registrazione
-- esclusa da giacenze e relazioni, viewRifiutiRegistrazioniEffettive.IsAnnullata) se l'esclusione non rende
-- incoerenti le relazioni (es. scarico senza carichi derivati, i cui carichi tornano disponibili); per un
-- carico gia' consumato da scarichi o uno scarico da cui derivano carichi (es. I -> M/NP) restano invece i
-- valori operativi precedenti: annullato per il RENTRI, continua ad avere effetto in Ecomatico.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_upd_Annullamento]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@RegistrazioneData DATE = NULL,
	@RegistrazioneNumero INT = 0,
	@RegistrazioneNote VARCHAR(500) = NULL,
	@RegistrazioneAuto BIT = 0,
	@RinumeraRegistro BIT = 0
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

		-- Permesso + titolarità su @Id, PRIMA di leggere qualunque dato suo (stesso pattern di
		-- uspRifiutiRegistrazioni_upd_Rettifica)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idOriginale CHAR(16) = (SELECT Id
		FROM dbo.tblRentriRegistrazioniRettifiche
		WHERE
			IdRettifica = @Id
			AND Annullata = 1
		);

		IF @idOriginale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non è un annullamento';
			GOTO BRANCH_END;
		END

		SET @RegistrazioneNote = NULLIF(LTRIM(RTRIM(@RegistrazioneNote)), '');

		-- Punto 5 della specifica: unico dato editabile dall'utente, obbligatorio (riporta il motivo
		-- dell'annullamento, diventa "annotazioni" nel payload RENTRI)
		IF @RegistrazioneNote IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il motivo dell''annullamento';
			GOTO BRANCH_END;
		END

		-- Rilettura pass-through di tutti i campi non modificabili qui (snapshot copiato dall'originale
		-- all'INSERT): stessa forma di uspRifiutiRegistrazioni_get, così uspRifiutiRegistrazioni_upd non
		-- vede alcuna differenza rispetto ai valori già presenti e non rifiuta/altera nulla oltre a
		-- Numero/Data/Note.
		DECLARE
			@idMovimento CHAR(16), @idEer CHAR(6), @idProvenienza CHAR(1), @eerDescrizione VARCHAR(200),
			@idStatoFisico CHAR(1), @idAttivitaRs CHAR(2), @idUnitaMisura CHAR(2), @quantita DECIMAL(18, 2),
			@dataInizioTrasporto SMALLDATETIME, @idDocumentoTrasportoTipo CHAR(1), @formularioNumero VARCHAR(20),
			@idAutorizzazioneProduttoreDetentore CHAR(16), @idAutorizzazioneDestinatario CHAR(16),
			@idAutorizzazioneTrasportatore1 CHAR(16), @idAutorizzazioneTrasportatore2 CHAR(16), @idAutorizzazioneTrasportatore3 CHAR(16),
			@idAutorizzazioneIntermediario1 CHAR(16), @idAutorizzazioneIntermediario2 CHAR(16), @idAutorizzazioneIntermediario3 CHAR(16),
			@utenteNote VARCHAR(500),
			@isVeicoloFuoriUso BIT, @veicoloFuoriUsoNumero VARCHAR(50), @veicoloFuoriUsoData DATE,
			@idRaee CHAR(1),
			@idEsito CHAR(1), @quantitaVerificata DECIMAL(18, 2), @isQuantitaVerificata BIT, @dataFineTrasporto SMALLDATETIME,
			@idCausaleRespingimento CHAR(1), @causaleRespingimentoAltro VARCHAR(100), @idUnitaMisuraQuantitaRespinta CHAR(2), @quantitaRespinta DECIMAL(18, 2),
			@idMateriale CHAR(2), @materialeDescrizione VARCHAR(200),
			@idAttivitaProvenienza CHAR(1);

		SELECT
			@idMovimento = m.Id,
			@idEer = m.IdEer,
			@idProvenienza = m.IdProvenienza,
			@eerDescrizione = m.EerDescrizione,
			@idStatoFisico = m.IdStatoFisico,
			@idAttivitaRs = m.IdAttivita,
			@idUnitaMisura = m.IdUnitaMisura,
			@quantita = m.Quantita,
			@dataInizioTrasporto = m.DataInizioTrasporto,
			@idDocumentoTrasportoTipo = r.IdTrasportoTransfrontalieroTipo,
			@formularioNumero = m.FormularioNumero,
			@utenteNote = m.Note,
			@isVeicoloFuoriUso = ISNULL(r.VeicoloFuoriUso, 0),
			@veicoloFuoriUsoNumero = r.VeicoloFuoriUsoNumero,
			@veicoloFuoriUsoData = r.VeicoloFuoriUsoData,
			@idRaee = r.IdRaee,
			@idEsito = r.IdEsito,
			@quantitaVerificata = r.QuantitaVerificata,
			@dataFineTrasporto = r.DataFineTrasporto,
			@idCausaleRespingimento = r.IdCausaleRespingimento,
			@causaleRespingimentoAltro = r.CausaleRespingimentoAltro,
			@idUnitaMisuraQuantitaRespinta = r.IdUnitaMisuraQuantitaRespinta,
			@quantitaRespinta = r.QuantitaRespinta,
			@idMateriale = r.IdMateriale,
			@materialeDescrizione = r.MaterialeDescrizione,
			@idAttivitaProvenienza = r.IdAttivitaProvenienza
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE r.Id = @Id;

		SELECT @idAutorizzazioneProduttoreDetentore = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiProduttori
		WHERE
			Id = @idMovimento
			AND Pos = 0;
		SELECT @idAutorizzazioneDestinatario = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiDestinatari
		WHERE
			Id = @idMovimento
			AND Pos = 0;
		SELECT @idAutorizzazioneTrasportatore1 = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiTrasportatori
		WHERE
			Id = @idMovimento
			AND Pos = 0;
		SELECT @idAutorizzazioneTrasportatore2 = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiTrasportatori
		WHERE
			Id = @idMovimento
			AND Pos = 1;
		SELECT @idAutorizzazioneTrasportatore3 = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiTrasportatori
		WHERE
			Id = @idMovimento
			AND Pos = 2;
		SELECT @idAutorizzazioneIntermediario1 = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiIntermediari
		WHERE
			Id = @idMovimento
			AND Pos = 0;
		SELECT @idAutorizzazioneIntermediario2 = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiIntermediari
		WHERE
			Id = @idMovimento
			AND Pos = 1;
		SELECT @idAutorizzazioneIntermediario3 = IdAutorizzazione
		FROM dbo.tblRifiutiMovimentiIntermediari
		WHERE
			Id = @idMovimento
			AND Pos = 2;

		DECLARE @classiPericolo VARCHAR(50) = (
			SELECT STRING_AGG(c.Codice, ';')
			FROM
				dbo.tblRifiutiMovimentiClassiPericolo mc
				INNER JOIN dbo.tblRifiutiClassiPericolo c ON mc.IdClasse = c.Id
			WHERE mc.Id = @idMovimento);

		DECLARE @idEtichette VARCHAR(50) = (
			SELECT STRING_AGG(IdEtichetta, ';')
			FROM dbo.tblRifiutiRegistrazioniEtichette
			WHERE Id = @Id);

		BEGIN TRANSACTION;

			-- Il registro si blocca per primo, prima delle relazioni: è lo stesso ordine di
			-- uspRifiutiRegistrazioni_upd (che blocca il registro per la numerazione), cosi' un annullamento e un
			-- salvataggio contemporanei sullo stesso registro si mettono in fila invece di bloccarsi a vicenda
			DECLARE @registroBloccato CHAR(16) = (
				SELECT g.Id
				FROM dbo.tblRifiutiRegistri g WITH (UPDLOCK, HOLDLOCK)
				WHERE g.Id = (
					SELECT m.IdRegistro
					FROM
						dbo.tblRifiutiRegistrazioni r
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					WHERE r.Id = @Id));

			-- Relazioni carico/scarico dell'originale bloccate fino alla fine della transazione
			-- (UPDLOCK/HOLDLOCK): una nuova associazione sull'originale attende la conferma di questo
			-- annullamento, cosi' la decisione sui valori operativi presa sotto resta valida.
			DECLARE @relazioniOriginale INT = (SELECT COUNT(*)
			FROM dbo.tblRifiutiRegistrazioniRelazioni WITH (UPDLOCK, HOLDLOCK)
			WHERE
				Id = @idOriginale
				OR IdParent = @idOriginale
			);

			EXEC dbo.uspRifiutiRegistrazioni_upd
				@Id = @Id,
				@IdSessione = @IdSessione,
				@IdEer = @idEer,
				@IdProvenienza = @idProvenienza,
				@EerDescrizione = @eerDescrizione,
				@IdStatoFisico = @idStatoFisico,
				@ClassiPericolo = @classiPericolo,
				@IdAttivitaRs = @idAttivitaRs,
				@RegistrazioneData = @RegistrazioneData,
				@RegistrazioneNumero = @RegistrazioneNumero,
				@IdUnitaMisura = @idUnitaMisura,
				@Quantita = @quantita,
				@DataInizioTrasporto = @dataInizioTrasporto,
				@IdDocumentoTrasportoTipo = @idDocumentoTrasportoTipo,
				@FormularioNumero = @formularioNumero,
				@IdAutorizzazioneProduttoreDetentore = @idAutorizzazioneProduttoreDetentore,
				@IdAutorizzazioneDestinatario = @idAutorizzazioneDestinatario,
				@IdAutorizzazioneTrasportatore1 = @idAutorizzazioneTrasportatore1,
				@IdAutorizzazioneTrasportatore2 = @idAutorizzazioneTrasportatore2,
				@IdAutorizzazioneTrasportatore3 = @idAutorizzazioneTrasportatore3,
				@IdAutorizzazioneIntermediario1 = @idAutorizzazioneIntermediario1,
				@IdAutorizzazioneIntermediario2 = @idAutorizzazioneIntermediario2,
				@IdAutorizzazioneIntermediario3 = @idAutorizzazioneIntermediario3,
				@RegistrazioneNote = @RegistrazioneNote,
				@UtenteNote = @utenteNote,
				@IdEtichette = @idEtichette,
				@IsVeicoloFuoriUso = @isVeicoloFuoriUso,
				@VeicoloFuoriUsoNumero = @veicoloFuoriUsoNumero,
				@VeicoloFuoriUsoData = @veicoloFuoriUsoData,
				@IdRaee = @idRaee,
				@IdEsito = @idEsito,
				@QuantitaVerificata = @quantitaVerificata,
				@DataFineTrasporto = @dataFineTrasporto,
				@IdCausaleRespingimento = @idCausaleRespingimento,
				@CausaleRespingimentoAltro = @causaleRespingimentoAltro,
				@IdUnitaMisuraQuantitaRespinta = @idUnitaMisuraQuantitaRespinta,
				@QuantitaRespinta = @quantitaRespinta,
				@IdMateriale = @idMateriale,
				@MaterialeDescrizione = @materialeDescrizione,
				@IdAttivitaProvenienza = @idAttivitaProvenienza,
				@RegistrazioneAuto = @RegistrazioneAuto,
				@RinumeraRegistro = @RinumeraRegistro,
				-- Sempre 1, come per la rettifica di correzione: un annullamento non partecipa mai al grafo
				-- carichi/scarichi, non è un parametro esposto al chiamante
				@NessunaRegistrazioneAssociata = 1;

			-- Valori operativi (vedi header): Quantita = 0 se l'annullamento vale anche per Ecomatico,
			-- altrimenti tutti i valori operativi precedenti
			UPDATE t
			SET
				t.IdEer = o.IdEer,
				t.EerDescrizione = o.EerDescrizione,
				t.IdStatoFisico = o.IdStatoFisico,
				t.IdUnitaMisura = o.IdUnitaMisura,
				t.Quantita = IIF(o.IsOperativa = 1, 0, o.Quantita)
			FROM
				dbo.tblRentriRegistrazioniRettifiche t
				CROSS APPLY dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(t.IdRettifica, NULL, NULL, NULL, NULL) o
			WHERE t.IdRettifica = @Id;

			-- Magazzino EoW allineato al registro operativo: una M annullata (quantita' operativa 0) perde
			-- tutte le allocazioni sui lotti
			EXEC dbo.uspEoWLottiRifiutiRegistrazioni_upd_Allinea @IdRegistrazione = @idOriginale;

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
GO

PRINT 'uspRifiutiRegistrazioni_del_Undo.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Ripristina le registrazioni cancellate dalla sessione (tblIdCancellati). Il ripristino è rifiutato se nel
-- frattempo il numero di una di esse è stato assegnato a un'altra registrazione dello stesso registro e anno.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_del_Undo]
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Numerazione: i registri delle registrazioni da ripristinare vengono bloccati per tutta la
			-- transazione (UPDLOCK/HOLDLOCK sulle loro sole righe), come in uspRifiutiRegistrazioni_upd
			DECLARE @registriBloccati INT = (
				SELECT COUNT(*)
				FROM dbo.tblRifiutiRegistri g WITH (UPDLOCK, HOLDLOCK)
				WHERE g.Id IN (
					SELECT m.IdRegistro
					FROM
						dbo.tblIdCancellati c
						INNER JOIN dbo.tblRifiutiRegistrazioni i ON c.Id = i.Id
						INNER JOIN dbo.tblRifiutiMovimenti m ON i.IdMovimento = m.Id
					WHERE c.IdSessione = @IdSessione));

			-- Dopo la cancellazione il numero può essere stato riassegnato a un'altra registrazione dello
			-- stesso registro e anno: il ripristino creerebbe due registrazioni con lo stesso numero
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblIdCancellati c
					INNER JOIN dbo.tblRifiutiRegistrazioni i ON c.Id = i.Id
					INNER JOIN dbo.tblRifiutiMovimenti mi ON i.IdMovimento = mi.Id
					INNER JOIN dbo.tblRifiutiMovimenti ma ON mi.IdRegistro = ma.IdRegistro
					INNER JOIN dbo.tblRifiutiRegistrazioni a ON ma.Id = a.IdMovimento
				WHERE
					c.IdSessione = @IdSessione
					AND i.Lock = 4
					AND a.Lock < 2
					AND a.Id <> i.Id
					AND a.Numero = i.Numero
					AND a.[Data] >= DATEFROMPARTS(YEAR(i.[Data]), 1, 1)
					AND a.[Data] < DATEFROMPARTS(YEAR(i.[Data]) + 1, 1, 1)
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Ripristino non possibile: il numero della registrazione è già stato assegnato a un''altra registrazione';
				GOTO BRANCH_END;
			END

			UPDATE i
			SET Lock = 0
			FROM dbo.tblRifiutiRegistrazioni i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE c.IdSessione = @IdSessione;

			DELETE i
			FROM dbo.tblIdLog i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;

			DECLARE @ripristinate INT = @@ROWCOUNT;
		COMMIT TRANSACTION;

		SET @returnMessage = CASE @ripristinate
			WHEN 0 THEN 'Nessuna entità da ripristinare'
			WHEN 1 THEN 'Entità ripristinata'
			ELSE FORMAT(@ripristinate, 'N0', 'it-IT') + ' entità ripristinate'
		END;

		SELECT @returnMessage AS ReturnMessage;

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
GO

