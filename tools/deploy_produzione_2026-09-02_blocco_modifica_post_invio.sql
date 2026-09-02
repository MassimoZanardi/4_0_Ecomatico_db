/*
	Deploy produzione - 2026-09-02 - Blocco modifiche su registrazioni/formulari già inviati a RENTRI

	Nuova regola di business, estesa a tutte le SP che possono modificare una registrazione già
	trasmessa a RENTRI (RentriIdentificativo o RentriData valorizzati):
	- uspRifiutiRegistrazioni_upd/_del: bloccano qualunque modifica/cancellazione.
	- uspRifiutiFormulari_upd/_del: bloccano se il Formulario ha una registrazione associata
	  attiva già inviata (un formulario senza registrazione associata resta modificabile).
	- uspRifiutiRegistrazioni_ins_Relazione/_ins_RelazioniTutte/_del_Relazione: bloccano se la
	  registrazione "padre" (quella le cui associazioni cambierebbero, e il cui Lock verrebbe
	  riportato a 1 "da confermare") è già stata inviata.
	- uspRifiutiRegistrazioni_upd_Numerazione: blocca la rinumerazione se l'intervallo contiene
	  anche una sola registrazione già inviata (il Numero/Anno trasmesso a RENTRI non può
	  disallinearsi da quello locale).

	Aggiunto anche l'header SET ANSI_NULLS/QUOTED_IDENTIFIER mancante su 7 delle 8 SP (nessun
	impatto funzionale, solo allineamento allo standard - erano già ANSI_NULLS/
	QUOTED_IDENTIFIER=1 lato server).

	Testato con dati reali su dev (transazione con rollback, nessun dato alterato) per tutte e
	8 le SP: confermato blocco con messaggio corretto su una registrazione simulata come già
	inviata, confermato nessuna regressione sulle registrazioni non inviate.

	Nessuna modifica a tabelle/funzioni, solo CREATE OR ALTER PROCEDURE.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-02_blocco_modifica_post_invio.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- dbo.uspRifiutiRegistrazioni_upd
--------------------------------------------------------------------------------
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

		-- EER / StatoFisico / ClassiPericolo esclusivi con Materiale
		IF @isMateriale = 1
		BEGIN
			SET @IdEer = NULL;
			SET @IdProvenienza = NULL;
			SET @IdStatoFisico = NULL;
			SET @ClassiPericolo = NULL;
			SET @EerDescrizione = NULL;
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
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
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
						m.IdEer <> @IdEer
						OR m.IdStatoFisico <> @IdStatoFisico
						OR m.IdUnitaMisura <> @IdUnitaMisura
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
				SET @returnValue = -1;
				SET @returnMessage = 'Almeno una registrazione con numero inferiore e data maggiore a quella indicata è già presente';
				GOTO BRANCH_END;
			END
		END

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
				WHERE
					l.Id = @Id
					AND l.Quantita > 0
					AND rp.Lock < 2
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

		BEGIN TRANSACTION;

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


--------------------------------------------------------------------------------
-- dbo.uspRifiutiFormulari_upd
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_upd]
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
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);

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
			@rentriIdentificativo = r.RentriIdentificativo,
			@rentriData = r.RentriData,
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

		-- Se la registrazione associata è già stata trasmessa a RENTRI, il formulario non può più
		-- essere modificato (un formulario senza registrazione associata resta invece modificabile)
		IF @isRegistrazioneAssociata = 1 AND (@rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione associata è già stata inviata al RENTRI: il formulario non può più essere modificato';
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
					(
					l.Id = @idRegistrazione
					OR l.IdParent = @idRegistrazione
					)
					AND mp.IdOperazione <> 'M'
					AND
						(
						m.IdEer <> @IdEer
						OR m.IdStatoFisico <> @IdStatoFisico
						OR m.IdUnitaMisura <> @IdUnitaMisura
						)
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
					AND
						(
						ISNULL(m.IdEer, '000000') <> ISNULL(@IdEer, '000000')
						OR ISNULL(m.IdStatoFisico, '0') <> ISNULL(@IdStatoFisico, '0')
						OR ISNULL(m.IdAttivita, '00') <> ISNULL(@IdAttivitaRs, '00')
						OR ISNULL(m.FormularioNumero, '') <> ISNULL(@FormularioNumero, '')
						OR ISNULL(m.IdUnitaMisura, '0') <> ISNULL(@IdUnitaMisura, '0')
						OR ISNULL(m.Quantita, 0) <> ISNULL(@Quantita, 0)
						OR ISNULL(m.DataInizioTrasporto, @minData) <> ISNULL(@DataInizioTrasporto, @minData)
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

--------------------------------------------------------------------------------
-- dbo.uspRifiutiRegistrazioni_del
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
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

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblRifiutiRegistrazioni
		WHERE Id = @Id);

		IF @lock IS NULL
		BEGIN
			-- Idempotenza: registrazione mai esistita o già cancellata (es. doppio invio della
			-- richiesta di annullamento lato UI) — trattata come cancellazione già avvenuta con
			-- successo, non come errore. Salta anche il controllo di titolarità sottostante e
			-- l'intera catena Lock, che non hanno senso su un record inesistente.
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

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

		DECLARE @idMovimento CHAR(16);
		DECLARE @idFormulario CHAR(16);
		DECLARE @operazione CHAR(1);
		DECLARE @idOperazione CHAR(1);
		DECLARE @isFormulario BIT;
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);

		-- ── CASO 1: registrazione attiva (Lock = 0) → soft delete ────────────
		IF @lock = 0
		BEGIN
			SELECT @rentriIdentificativo = RentriIdentificativo, @rentriData = RentriData
			FROM dbo.tblRifiutiRegistrazioni
			WHERE Id = @Id;

			-- Una registrazione già trasmessa a RENTRI non può più essere cancellata
			IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può più essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiRegistrazioniRelazioni a
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON a.IdParent = r.Id
				WHERE
					a.Id = @Id
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una registrazione associata ad altre non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Recupero dati registrazione
			SELECT
				@idMovimento = r.IdMovimento,
				@idFormulario = f.Id,
				@operazione = r.Operazione,
				@idOperazione = m.IdOperazione
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
			WHERE r.Id = @Id;

			BEGIN TRANSACTION;
				UPDATE dbo.tblRifiutiRegistrazioni
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Registrazione non trovata o già eliminata';
					GOTO BRANCH_END;
				END

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());

			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END

		-- ── CASO 2: registrazione non confermata (Lock = 1) ──────────────────
		ELSE IF @lock = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione non confermata non può essere cancellata';
			GOTO BRANCH_END;
		END

		-- ── CASO 3: registrazione in bozza (Lock = 2) → hard delete ──────────
		ELSE IF @lock = 2
		BEGIN
			SELECT
				@idMovimento = r.IdMovimento,
				@idFormulario = f.Id
			FROM
				dbo.tblRifiutiRegistrazioni r
				LEFT JOIN dbo.tblRifiutiFormulari f ON r.IdMovimento = f.IdMovimento
			WHERE r.Id = @Id;

			BEGIN TRANSACTION;
				DELETE dbo.tblRifiutiRegistrazioniRelazioni
				WHERE
					Id = @Id
					OR IdParent = @Id;
				DELETE dbo.tblRifiutiMovimentiClassiPericolo
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiProduttori
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiDestinatari
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiTrasportatori
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiIntermediari
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				-- Mancante in precedenza: dettaglio 1:1 a chiave condivisa (Id NOT NULL) di
				-- tblRifiutiMovimenti, blocca la DELETE su tblRifiutiMovimenti se esistono righe
				-- (stesso gap trovato e corretto in uspRifiutiFormulari_del il 2026-08-21)
				DELETE dbo.tblRifiutiMovimentiLog
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiRegistrazioniEtichette
				WHERE Id = @Id;
				-- Gestione EoW: tblEoWMovimenti.IdRegistrazione (nullable) può referenziare questa
				-- registrazione se l'automatismo sulla causale K l'ha già collegata a un movimento
				-- di magazzino EoW - si azzera il collegamento anziché bloccare la cancellazione,
				-- il movimento resta un record di magazzino valido anche senza la registrazione di
				-- origine (stesso pattern di uspSYS_del_RegistroCascade).
				UPDATE dbo.tblEoWMovimenti SET IdRegistrazione = NULL WHERE IdRegistrazione = @Id;
				DELETE dbo.tblRifiutiRegistrazioni
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulari
				WHERE
					IdMovimento = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimenti
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblIdLog
				WHERE
					Id = @Id
					OR
						(
						Id = @idMovimento
						AND @idFormulario IS NULL
						);
				DELETE dbo.tblId
				WHERE
					Id = @Id
					OR
						(
						Id = @idMovimento
						AND @idFormulario IS NULL
						);
			COMMIT TRANSACTION;
		END

		-- ── CASO 4: Lock in stato non gestito ────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

		END

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



--------------------------------------------------------------------------------
-- dbo.uspRifiutiFormulari_del
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
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
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RFR', @Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: verifica prima di tutto se il formulario esiste, indipendentemente dalla
		-- titolarità sottostante — mai esistito o già cancellato (es. doppio invio della
		-- richiesta di annullamento lato UI) viene trattato come cancellazione già avvenuta con
		-- successo, non come errore.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRifiutiFormulari
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Titolarità: prima non esisteva alcun controllo che @Id appartenesse
		-- all'azienda della sessione (via registro/sede) — stesso pattern di
		-- uspRifiutiFormulari_get.
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

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblRifiutiFormulari
		WHERE Id = @Id);

		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		SELECT @rentriIdentificativo = r.RentriIdentificativo, @rentriData = r.RentriData
		FROM
			dbo.tblRifiutiFormulari f
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento AND r.Lock < 2
		WHERE f.Id = @Id;

		-- Se la registrazione associata è già stata trasmessa a RENTRI, il formulario non può
		-- più essere cancellato (un formulario senza registrazione associata resta cancellabile)
		IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione associata è già stata inviata al RENTRI: il formulario non può più essere cancellato';
			GOTO BRANCH_END;
		END

		-- Se il record è già stato aggiunto
		IF @lock = 0
		BEGIN
			BEGIN TRANSACTION;

				UPDATE dbo.tblRifiutiFormulari
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT dbo.tblIdCancellati (Id, IdSessione, [Data]) VALUES (@Id, @IdSessione, GETDATE());

			COMMIT TRANSACTION;

			-- Aggiorna il log (fuori dalla transazione)
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END
		ELSE IF @lock = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione non confermata non può essere cancellata';
			GOTO BRANCH_END;
		END
		ELSE IF @lock = 2
		BEGIN
			DECLARE @idMovimento CHAR(16);
			SELECT @idMovimento = IdMovimento
			FROM dbo.tblRifiutiFormulari
			WHERE Id = @Id;

			BEGIN TRANSACTION;

				DELETE dbo.tblRifiutiMovimentiClassiPericolo
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiMovimentiProduttori
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiMovimentiDestinatari
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiMovimentiTrasportatori
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiMovimentiIntermediari
				WHERE Id = @idMovimento;
				-- Mancante in precedenza: dettaglio 1:1 a chiave condivisa (Id NOT NULL) di
				-- tblRifiutiMovimenti, blocca la DELETE su tblRifiutiMovimenti se esistono righe
				DELETE dbo.tblRifiutiMovimentiLog
				WHERE Id = @idMovimento;
				DELETE dbo.tblRifiutiFormulariEtichette
				WHERE Id = @Id;
				-- Aggiunte per il recente cambio di schema: dettagli 1:1 a chiave condivisa
				-- (Id NOT NULL) di tblRifiutiFormulari, bloccano la DELETE su tblRifiutiFormulari
				-- se esistono righe
				DELETE dbo.tblRifiutiFormulariTrasportiFerroviari
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulariTrasportiMarittimi
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulariTrasportiTerresti
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulari
				WHERE IdMovimento = @idMovimento;
				DELETE dbo.tblRifiutiMovimenti
				WHERE Id = @idMovimento;
				DELETE dbo.tblIdLog
				WHERE
					Id = @Id
					OR Id = @idMovimento;
				DELETE dbo.tblId
				WHERE
					Id = @Id
					OR Id = @idMovimento;

			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il formulario è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

		END

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
		THROW 50001, @returnMessage, 1
	END

END;


--------------------------------------------------------------------------------
-- dbo.uspRifiutiRegistrazioni_ins_Relazione
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_ins_Relazione]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdParent CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
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

		-- Recupera l'operazione del padre e verifica che esista
		DECLARE @operazioneParent CHAR(1);
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		SELECT
			@operazioneParent = Operazione,
			@rentriIdentificativo = RentriIdentificativo,
			@rentriData = RentriData
		FROM dbo.tblRifiutiRegistrazioni
		WHERE Id = @IdParent;

		IF @operazioneParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione padre non trovata';
			GOTO BRANCH_END;
		END

		-- La registrazione padre, già trasmessa a RENTRI, non può cambiare le proprie associazioni
		IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può essere associata ad altre registrazioni';
			GOTO BRANCH_END;
		END

		IF (
			SELECT COUNT(DISTINCT r.Id)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id IN (@Id, @IdParent)) < 2
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @pos INT;
		SELECT @pos = ISNULL(MAX(s.Pos), -1) + 1
		FROM dbo.tblRifiutiRegistrazioniRelazioni s
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON s.Id = r.Id
		WHERE
			s.IdParent = @IdParent
			AND r.Lock < 2;
		IF @pos >= 499
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Superato il numero massimo di registrazioni associabili';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			INSERT INTO dbo.tblRifiutiRegistrazioniRelazioni
				(Id, IdParent, Operazione, Quantita, Pos)
			VALUES
				(@Id, @IdParent, @operazioneParent, 0, @pos);

			-- Imposta la registrazione padre nello stato "Da confermare"
			UPDATE dbo.tblRifiutiRegistrazioni
			SET Lock = 1
			WHERE
				Id = @IdParent
				AND Lock = 0;
		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;
	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;

--------------------------------------------------------------------------------
-- dbo.uspRifiutiRegistrazioni_ins_RelazioniTutte
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_ins_RelazioniTutte]
	@IdSessione CHAR(16) = NULL,
	@IdParent CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@IdEer CHAR(6),
	@IdStatoFisico CHAR(1),
	@IdUnitaMisura CHAR(2),
	@Numero INT,
	@Data DATE
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
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

		-- Calcolata una sola volta e riusata nei due controlli titolarità sottostanti,
		-- invece di richiamare la function separatamente per ciascuno
		DECLARE @sedi TABLE (Id CHAR(16) PRIMARY KEY);
		INSERT @sedi (Id)
		SELECT Id
		FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione);

		IF (
			SELECT COUNT(DISTINCT g.Id)
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN @sedi i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro) = 0
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
				INNER JOIN @sedi i ON g.IdSede = i.Id
			WHERE r.Id = @IdParent)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La registrazione padre, già trasmessa a RENTRI, non può cambiare le proprie associazioni
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @IdParent
				AND (RentriIdentificativo IS NOT NULL OR RentriData IS NOT NULL)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può essere associata ad altre registrazioni';
			GOTO BRANCH_END;
		END

		DECLARE @pos INT;
		SELECT @pos = ISNULL(MAX(s.Pos), -1)
		FROM
			dbo.tblRifiutiRegistrazioniRelazioni s
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON s.Id = r.Id
		WHERE
			s.IdParent = @IdParent
			AND r.Lock < 2;

		IF @pos >= 499
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Superato il numero massimo di registrazioni associabili';
			GOTO BRANCH_END;
		END

		DECLARE @idOperazione CHAR(1);
		SELECT @idOperazione = m.IdOperazione
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE r.Id = @IdParent;

		BEGIN TRANSACTION;

			--      QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0)
			INSERT dbo.tblRifiutiRegistrazioniRelazioni
				(Id, IdParent, Operazione, Quantita, Pos)
			SELECT TOP(499 - @pos)
				r.Id,
				@IdParent,
				IIF(r.Operazione = 'C', 'S', 'C'),
				0,
				@pos + ROW_NUMBER() OVER (ORDER BY YEAR(r.[Data]), r.Numero)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN (
					SELECT
						l.Id,
						Quantita = SUM(l.Quantita)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l
						INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
						INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
					WHERE
						p.Lock < 2
						AND mp.Quantita > 0
					GROUP BY l.Id
				) a ON r.Id = a.Id
			WHERE
				r.Lock = 0
				AND m.IdRegistro = @IdRegistro
				AND
					(
					@idOperazione IN ('K', 'M')
					OR m.IdEer = @IdEer
					)
				AND
					(
					@idOperazione IN ('K', 'M')
					OR m.IdStatoFisico = @IdStatoFisico
					)
				AND
					(
					@idOperazione IN ('K', 'M')
					OR m.IdUnitaMisura = @IdUnitaMisura
					)
				AND
					(
					r.[Data] < @Data
					OR
						(
						r.[Data] = @Data
						AND r.Numero < @Numero
						)
					)
				AND m.IdOperazione IN ( SELECT IdParent FROM dbo.tblRifiutiOperazioniRelazioni WHERE Id = @idOperazione )
				AND m.Quantita - ISNULL(a.Quantita, 0) > 0 -- QuantitaResidua > 0
				AND NOT EXISTS ( SELECT 1 FROM dbo.tblRifiutiRegistrazioniRelazioni x WHERE x.Id = r.Id AND x.IdParent = @IdParent )
			ORDER BY YEAR(r.[Data]), r.Numero;

			SET @returnValue = @@ROWCOUNT;

			-- Imposta la registrazione nello stato "Da confermare"
			UPDATE dbo.tblRifiutiRegistrazioni
			SET Lock = 1
			WHERE
				Id = @IdParent
				AND Lock = 0;

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

--------------------------------------------------------------------------------
-- dbo.uspRifiutiRegistrazioni_del_Relazione
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_del_Relazione]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdParent CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
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

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id = @IdParent)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La registrazione padre, già trasmessa a RENTRI, non può cambiare le proprie associazioni
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @IdParent
				AND (RentriIdentificativo IS NOT NULL OR RentriData IS NOT NULL)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può essere modificata la sua associazione';
			GOTO BRANCH_END;
		END

		-- Caso 1: relazione con Quantita = 0 → eliminazione diretta senza transazione
		-- (nessun effetto collaterale sullo stato della registrazione padre)
		DELETE dbo.tblRifiutiRegistrazioniRelazioni
		WHERE
			Id = @Id
			AND IdParent = @IdParent
			AND Quantita = 0;

		-- Caso 2: relazione con Quantita <> 0 → rimozione + ripristino stato Lock = 1 sul padre
		IF @@ROWCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblRifiutiRegistrazioniRelazioni
				WHERE
					Id = @Id
					AND IdParent = @IdParent;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Relazione non trovata o già rimossa';
					GOTO BRANCH_END;
				END

				-- Imposta la registrazione padre nello stato "Da confermare"
				UPDATE dbo.tblRifiutiRegistrazioni
				SET Lock = 1
				WHERE
					Id = @IdParent
					AND Lock = 0;
			COMMIT TRANSACTION;
		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;

--------------------------------------------------------------------------------
-- dbo.uspRifiutiRegistrazioni_upd_Numerazione
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_upd_Numerazione]
	@IdSessione CHAR(16),
	@DalNumero INT,
	@AlNumero INT,
	@Anno INT,
	@PrimoNumero INT
AS
BEGIN

SET NOCOUNT, XACT_ABORT ON

BEGIN TRY

DECLARE @returnValue INT = 0
DECLARE @returnMessage NVARCHAR(200) = NULL

-- Controlla il permesso sulla funzione
DECLARE @permesso TINYINT
EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RRG', @Permesso = @permesso OUTPUT
IF 2 > @permesso
BEGIN
	SET @returnValue = -1;
	SET @returnMessage = 'Non si dispone dei diritti necessari'
	GOTO BRANCH_END
END

DECLARE @totaleDaRinumerare INT
SELECT
	@totaleDaRinumerare = COUNT(*)
FROM
	dbo.tblRifiutiRegistrazioni r
	INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
	INNER JOIN dbo.tblSessioni e ON m.IdRegistro = e.IdRegistro
WHERE
	e.Id = @IdSessione
	AND r.Lock < 2
	AND YEAR(r.[Data]) = @Anno
	AND r.Numero BETWEEN @DalNumero AND @AlNumero

-- Se non c'è nulla da rinumerare
IF @totaleDaRinumerare = 0
BEGIN
	SET @returnValue = -1;
	SET @returnMessage = 'Non ci sono registrazioni nell''intervallo indicato'
	GOTO BRANCH_END
END

-- Se l'intervallo contiene registrazioni già inviate a RENTRI: il Numero/Anno trasmesso
-- non può più essere modificato, pena il disallineamento con quanto RENTRI ha registrato
IF EXISTS (SELECT 1
	FROM
		dbo.tblRifiutiRegistrazioni r
		INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		INNER JOIN dbo.tblSessioni e ON m.IdRegistro = e.IdRegistro
	WHERE
		e.Id = @IdSessione
		AND r.Lock < 2
		AND YEAR(r.[Data]) = @Anno
		AND r.Numero BETWEEN @DalNumero AND @AlNumero
		AND (r.RentriIdentificativo IS NOT NULL OR r.RentriData IS NOT NULL)
)
BEGIN
	SET @returnValue = -1;
	SET @returnMessage = 'L''intervallo contiene registrazioni già inviate al RENTRI: non possono essere rinumerate'
	GOTO BRANCH_END
END

-- Se la numerazione finale supera 999.999
IF @PrimoNumero + @totaleDaRinumerare > 999999
BEGIN
	SET @returnValue = -1;
	SET @returnMessage = 'La rinumerazione non può assegnare numeri maggiori di 999.999'
	GOTO BRANCH_END
END

-- Se la nuova rinumerazione entra in conflitto con altre registrazioni al di fuori del gruppo che sarà rinumerato
IF EXISTS (SELECT 1
	FROM
		dbo.tblRifiutiRegistrazioni r
		INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		INNER JOIN dbo.tblSessioni e ON m.IdRegistro = e.IdRegistro
	WHERE
		e.Id = @IdSessione
		AND r.Lock < 2
		AND YEAR(r.[Data]) = @Anno
		AND r.Numero NOT BETWEEN @DalNumero AND @AlNumero
		AND r.Numero BETWEEN @PrimoNumero AND @PrimoNumero + @totaleDaRinumerare
)
BEGIN
	SET @returnValue = -1;
	SET @returnMessage = 'La nuova numerazione è in conflitto con quella di altre registrazioni'
	GOTO BRANCH_END
END

UPDATE r
SET Numero = t.NumeroBase + @PrimoNumero - 1
FROM
	dbo.tblRifiutiRegistrazioni r INNER JOIN
	(SELECT
		r.Id,
		NumeroBase = ROW_NUMBER() OVER (ORDER BY r.[Data], r.Numero)
	FROM
		dbo.tblRifiutiRegistrazioni r
		INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		INNER JOIN dbo.tblSessioni e ON m.IdRegistro = e.IdRegistro
	WHERE
		e.Id = @IdSessione
		AND r.Lock < 2
		AND YEAR(r.[Data]) = @Anno
		AND r.Numero BETWEEN @DalNumero AND @AlNumero
	) t ON r.Id = t.Id

	SET @returnValue = @@ROWCOUNT

END TRY
BEGIN CATCH
	THROW;
END CATCH

BRANCH_END:

SET NOCOUNT, XACT_ABORT OFF

IF @returnValue < 0
BEGIN
	SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
	THROW 50001, @returnMessage, 1;
END

SELECT ReturnValue = @returnValue

END
