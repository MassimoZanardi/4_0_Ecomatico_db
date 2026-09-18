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

