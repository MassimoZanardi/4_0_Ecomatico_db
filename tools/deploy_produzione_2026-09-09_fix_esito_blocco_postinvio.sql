/*
	Deploy produzione - 2026-09-09 - Fix uspRentriRegistrazioni_upd_Esito: messaggio corretto sul blocco
	post-invio RENTRI + UPDATE mirato

	Contesto: durante il primo test end-to-end reale in produzione di "RENTRI - Verifica esito" (Rifiuti/
	Registrazioni/Edit), la conferma dell'esito ha fallito con l'errore "La registrazione e' gia' stata
	inviata al RENTRI: non puo' piu' essere modificata". Un primo tentativo di fix (poi corretto, vedi
	sotto) aveva RIMOSSO questo blocco, ipotizzando fosse un falso positivo. Verificato invece contro lo
	spec RENTRI ufficiale (dati-registri v1.0, POST /operatore/{identificativo_registro}/movimenti): un
	movimento gia' trasmesso al registro cronologico NON e' MAI modificabile, l'esito incluso - le
	correzioni ad un movimento gia' inviato richiedono una registrazione di Rettifica separata (funzione
	gia' esistente in Rifiuti/Registrazioni), MAI una modifica diretta dell'originale. Il blocco era quindi
	corretto: il problema era solo che l'utente non aveva un modo chiaro di capire cosa fare.

	Fix definitivo: uspRentriRegistrazioni_upd_Esito non chiama piu' la SP generica
	uspRifiutiRegistrazioni_upd (che avrebbe comunque bloccato con un messaggio generico). Esegue un UPDATE
	diretto e mirato solo sulle colonne Esito (IdEsito, IdCausaleRespingimento, CausaleRespingimentoAltro,
	QuantitaVerificata, IdUnitaMisuraQuantitaRespinta, QuantitaRespinta, DataFineTrasporto) +
	RentriFormularioDataPresaVisione - la clausola SET dell'UPDATE e' la garanzia strutturale che nessun
	altro campo venga toccato. I controlli RentriIdentificativo/RentriData e ConservazioneSostitutiva
	restano ENTRAMBI attivi (replicati esplicitamente, non piu' ereditati dalla SP generica): se la
	registrazione e' gia' stata inviata al RENTRI, l'aggiornamento viene bloccato con un messaggio esplicito
	che guida l'utente verso la Rettifica ("La registrazione risulta già trasmessa al RENTRI, è pertanto
	necessario inserire una nuova registrazione di rettifica") invece del generico "non può più essere
	modificata". Se la registrazione NON e' ancora stata inviata, l'aggiornamento diretto resta pienamente
	legittimo (nessun movimento immutabile in gioco). Audit di tutti i GOTO BRANCH_END di
	uspRifiutiRegistrazioni_upd: nessun altro controllo li' presente e' applicabile (riguardano tutti campi
	mai toccati da questo UPDATE - FormularioNumero, RegistrazioneNumero/Data, EER/StatoFisico/UnitaMisura,
	Quantita).

	Nessuna modifica a uspRifiutiRegistrazioni_upd ne' ad altre SP: fix isolato a
	uspRentriRegistrazioni_upd_Esito su richiesta esplicita dell'utente. Nessuna creazione automatica di
	Rettifica in questa versione: l'utente la crea manualmente tramite la funzione "RENTRI - Rettifica" già
	esistente in Rifiuti/Registrazioni/Index, dopo aver letto il messaggio guida.

	Verificato su DB dev con dati reali e transazione con ROLLBACK esplicito (nessun dato alterato), 3
	scenari: (1) RentriIdentificativo/RentriData valorizzati (già inviata) -> blocco con il messaggio
	corretto, nessuna modifica applicata; (2) RentriIdentificativo/RentriData NULL (non ancora inviata) ->
	l'esito viene salvato correttamente (IdEsito, DataFineTrasporto, RentriFormularioDataPresaVisione
	valorizzati, QuantitaVerificata/QuantitaRespinta/IdUnitaMisuraQuantitaRespinta normalizzati secondo
	l'esito); (3) ConservazioneSostitutiva=1 -> blocco con messaggio corretto, nessuna modifica applicata.
	Query di controllo standard (ANSI_NULLS/QUOTED_IDENTIFIER/CRLF) pulita.

	Aggiunta successiva (stessa sessione, efficienza): il controllo sopra veniva scoperto solo alla
	conferma finale, dopo aver gia' contattato l'hub RENTRI per "Verifica esito" (fino a un minuto di
	attesa). uspRifiutiRegistrazioni_get e' stata estesa con 3 colonne mai esposte prima
	(RentriIdentificativo, RentriData, ConservazioneSostitutiva) cosi' che RentriRegistrazioneEsitoService
	possa fare lo stesso controllo SUBITO al click su "Verifica esito", PRIMA di qualunque chiamata hub,
	mostrando una modale dedicata (motivo "GiaInviata" o "ConservazioneSostitutiva") invece del generico
	"copia non disponibile". Nessuna modifica al comportamento esistente della SP per gli altri
	consumatori (sola aggiunta di colonne alla proiezione).

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-09_fix_esito_blocco_postinvio.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- uspRentriRegistrazioni_upd_Esito (CREATE OR ALTER, sostituisce integralmente la versione 2026-09-08)
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Salvataggio dedicato per l'esito di conferimento letto da RENTRI ("RENTRI - Verifica esito",
-- Rifiuti/Registrazioni/Edit, solo Registrazioni aT/T*aT con IsEsito=1). I parametri
-- @Esito/@EsitoCausaleRespingimento/@RespingimentoMotivo/@QuantitaDestino/@DataOraFineTrasporto sono gli
-- stessi nomi/valori di RentriHubFormularioDigitaleDettaglioResponse (GET formulario-digitale/{app}/{id}/
-- {numero}), passati pari pari dal chiamante come per uspRifiutiMovimenti_ins_DaAcquisizioneFormulario. La
-- risoluzione Esito/CausaleRespingimento -> Id locale riusa uspRifiutiRegistrazioni_get_MatchCodiciImportazione
-- (stessa lookup gia' usata dall'acquisizione formulario digitale), mai un CASE hardcoded.
--
-- UPDATE mirato SOLO sulle colonne Esito, MAI tramite uspRifiutiRegistrazioni_upd: la clausola SET
-- dell'UPDATE sotto e' la garanzia strutturale che nessun'altra colonna venga toccata. Il blocco
-- RentriIdentificativo/RentriData e quello per ConservazioneSostitutiva restano ENTRAMBI validi e sono
-- replicati esplicitamente sotto (audit di tutti i GOTO BRANCH_END di uspRifiutiRegistrazioni_upd: gli
-- altri controlli lì presenti riguardano solo campi mai toccati da questo UPDATE - FormularioNumero,
-- RegistrazioneNumero/Data, EER/StatoFisico/UnitaMisura, Quantita - quindi non applicabili qui). Verificato
-- contro lo spec RENTRI (dati-registri v1.0, POST /operatore/{identificativo_registro}/movimenti): un
-- movimento gia' trasmesso al registro cronologico non e' mai modificabile, l'esito incluso - le
-- correzioni vanno fatte con una registrazione di Rettifica separata (funzione gia' esistente in
-- Rifiuti/Registrazioni), MAI con una modifica diretta dell'originale. Se invece la registrazione non e'
-- ancora stata inviata, l'aggiornamento diretto e' pienamente legittimo.
--
-- Normalizzazione Esito replicata identica a quella di uspRifiutiRegistrazioni_upd (righe 265-266, 357-377
-- alla data di questa modifica), limitata al solo ramo "esito presente" dato che qui @IdEsito non e' mai
-- '0' (garantito dal controllo su @idEsito IS NULL sotto): Accettato ('A') pulisce causale/quantita
-- respinta, Respinto ('R') forza quantita respinta = quantita registrata e azzera la verificata, Parziale
-- ('P') valorizza l'unita' di misura respinta di default se assente, il motivo testuale sopravvive solo se
-- la causale e' "Altro". QuantitaRespinta/IdUnitaMisuraQuantitaRespinta partono dal valore attuale (RENTRI
-- non li trasmette) e vengono normalizzati secondo le stesse regole di un salvataggio manuale via UI.
--
-- RentriFormularioDataPresaVisione viene valorizzata qui con GETDATE() dopo l'aggiornamento dei campi
-- Esito: e' l'unico punto dell'app che scrive questo campo.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_upd_Esito]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Esito VARCHAR(5) = NULL,
	@EsitoCausaleRespingimento VARCHAR(5) = NULL,
	@RespingimentoMotivo VARCHAR(500) = NULL,
	@QuantitaDestino DECIMAL(18, 3) = NULL,
	@DataOraFineTrasporto DATETIME2(0) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Esito = NULLIF(LTRIM(RTRIM(@Esito)), '');
		SET @EsitoCausaleRespingimento = NULLIF(LTRIM(RTRIM(@EsitoCausaleRespingimento)), '');
		SET @RespingimentoMotivo = NULLIF(LTRIM(RTRIM(@RespingimentoMotivo)), '');

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

		-- Permesso + titolarità su @Id, PRIMA di leggere qualunque dato suo
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

		-- Una registrazione portata/bloccata per la conservazione sostitutiva non può più essere
		-- modificata (stesso controllo di uspRifiutiRegistrazioni_upd)
		DECLARE @conservazioneSostitutiva BIT, @rentriIdentificativo VARCHAR(20), @rentriData DATETIME2(0);
		SELECT
			@conservazioneSostitutiva = ConservazioneSostitutiva,
			@rentriIdentificativo = RentriIdentificativo,
			@rentriData = RentriData
		FROM dbo.tblRifiutiRegistrazioni
		WHERE Id = @Id;

		IF ISNULL(@conservazioneSostitutiva, 0) = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è bloccata per la conservazione sostitutiva: non può più essere modificata';
			GOTO BRANCH_END;
		END

		-- Il registro cronologico RENTRI non ammette modifiche a un movimento gia' trasmesso (spec
		-- dati-registri v1.0, POST /operatore/{identificativo_registro}/movimenti - le correzioni ad un
		-- movimento gia' inviato, incluso l'esito, richiedono una registrazione di Rettifica separata, non
		-- una modifica diretta). Se la registrazione non e' ancora stata inviata, l'aggiornamento diretto
		-- e' invece pienamente legittimo (nessun movimento immutabile in gioco).
		IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione risulta già trasmessa al RENTRI, è pertanto necessario inserire una nuova registrazione di rettifica';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			WHERE
				r.Id = @Id
				AND o.IsEsito = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non prevede un esito di conferimento';
			GOTO BRANCH_END;
		END

		-- Lookup Esito/CausaleRespingimento -> Id locale, stessa SP gia' usata dall'acquisizione da
		-- formulario digitale (nessun CASE hardcoded qui)
		CREATE TABLE #codici (
			IdStatoFisico CHAR(1) NULL,
			IdAttivitaRs CHAR(2) NULL,
			IdAnalisiTipo CHAR(1) NULL,
			IdAdr CHAR(2) NULL,
			IdUnitaMisura CHAR(2) NULL,
			IdEsito CHAR(1) NULL,
			IdCausaleRespingimento CHAR(1) NULL
		);
		INSERT #codici
		EXEC dbo.uspRifiutiRegistrazioni_get_MatchCodiciImportazione
			@EsitoCodice = @Esito,
			@CausaleRespingimentoCodice = @EsitoCausaleRespingimento;

		DECLARE @idEsito CHAR(1), @idCausaleRespingimento CHAR(1);
		SELECT TOP 1 @idEsito = IdEsito, @idCausaleRespingimento = IdCausaleRespingimento
		FROM #codici;

		IF @idEsito IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Esito RENTRI non riconosciuto: ' + ISNULL(@Esito, '(vuoto)');
			GOTO BRANCH_END;
		END

		DECLARE @dataOraFineTrasportoFinale DATETIME2(0) = @DataOraFineTrasporto;
		IF @dataOraFineTrasportoFinale >= '20500101' SET @dataOraFineTrasportoFinale = NULL;

		DECLARE @respingimentoMotivoFinale VARCHAR(100) = LEFT(@RespingimentoMotivo, 100);

		DECLARE @idMovimento CHAR(16), @quantita DECIMAL(18, 2), @idUnitaMisura CHAR(2),
			@quantitaRespinta DECIMAL(18, 2), @idUnitaMisuraQuantitaRespinta CHAR(2);

		SELECT
			@idMovimento = m.Id,
			@quantita = m.Quantita,
			@idUnitaMisura = m.IdUnitaMisura,
			@quantitaRespinta = r.QuantitaRespinta,
			@idUnitaMisuraQuantitaRespinta = r.IdUnitaMisuraQuantitaRespinta
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE r.Id = @Id;

		-- Stessa regola di uspRifiutiRegistrazioni_upd: una quantita' verificata identica a quella
		-- registrata equivale a "non specificata"
		DECLARE @quantitaVerificataFinale DECIMAL(18, 2) = @QuantitaDestino;
		IF @quantitaVerificataFinale = @quantita SET @quantitaVerificataFinale = NULL;

		IF @idEsito = 'A'
		BEGIN
			SET @idCausaleRespingimento = NULL;
			SET @respingimentoMotivoFinale = NULL;
			SET @idUnitaMisuraQuantitaRespinta = NULL;
			SET @quantitaRespinta = NULL;
		END
		IF @idEsito = 'R'
		BEGIN
			SET @quantitaRespinta = @quantita;
			SET @idUnitaMisuraQuantitaRespinta = @idUnitaMisura;
			SET @quantitaVerificataFinale = NULL;
		END
		IF @idEsito = 'P'
			SET @idUnitaMisuraQuantitaRespinta = ISNULL(@idUnitaMisuraQuantitaRespinta, 'KG');
		IF ISNULL(@idCausaleRespingimento, '') <> 'A'
			SET @respingimentoMotivoFinale = NULL;

		UPDATE dbo.tblRifiutiRegistrazioni
		SET
			IdEsito = @idEsito,
			IdCausaleRespingimento = @idCausaleRespingimento,
			CausaleRespingimentoAltro = @respingimentoMotivoFinale,
			QuantitaVerificata = @quantitaVerificataFinale,
			IdUnitaMisuraQuantitaRespinta = @idUnitaMisuraQuantitaRespinta,
			QuantitaRespinta = @quantitaRespinta,
			DataFineTrasporto = @dataOraFineTrasportoFinale
		WHERE Id = @Id;

		IF @@ROWCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata';
			GOTO BRANCH_END;
		END

		-- Unico punto dell'app che scrive questo campo
		UPDATE dbo.tblRifiutiMovimenti
		SET RentriFormularioDataPresaVisione = GETDATE()
		WHERE Id = @idMovimento;

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

--------------------------------------------------------------------------------
-- uspRifiutiRegistrazioni_get (CREATE OR ALTER, aggiunge RentriIdentificativo/RentriData/ConservazioneSostitutiva)
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
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

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRifiutiRegistrazioni
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione non trovata';
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

		SELECT
			Id = r.Id,
			IdMovimento = m.Id,
			m.IdRegistro,
			IdOperazione = ISNULL(m.IdOperazione, '0'),
			OperazioneNome = ISNULL(o.Nome, ''),
			IdEer = ISNULL(m.IdEer, '000000'),
			EerDescrizione = ISNULL(m.EerDescrizione, ''),
			IdStatoFisico = ISNULL(m.IdStatoFisico, '0'),
			IdProvenienza = ISNULL(m.IdProvenienza, 'S'),
			IdAttivitaRs = ISNULL(m.IdAttivita, '00'),

			RegistrazioneData = ISNULL(r.[Data], GETDATE()),
			RegistrazioneNumero = IIF(
				r.Lock = 2 OR r.Numero IS NULL,
				dbo.ufnRifiutiRegistrazioni_get_UltimoNumero(m.IdRegistro, GETDATE()) + 1,
				r.Numero
			),

			Quantita = ISNULL(m.Quantita, 0),
			IdUnitaMisura = ISNULL(m.IdUnitaMisura, 'KG'),

			NessunaRegistrazioneAssociata = CASE
														WHEN r.Lock = 2 THEN 0
														WHEN EXISTS(
															SELECT 1
															FROM dbo.tblRifiutiRegistrazioniRelazioni rel
															INNER JOIN dbo.tblRifiutiRegistrazioni rr ON rel.Id = rr.Id
															WHERE
																rel.IdParent = r.Id
																AND rr.Lock < 2
														) THEN 0
														ELSE 1
													END,

			DataInizioTrasporto = m.DataInizioTrasporto,

			RegistrazioneNote = ISNULL(r.Note, ''),
			UtenteNote = ISNULL(m.Note, ''),

			IdDocumentoTrasportoTipo = ISNULL(r.IdTrasportoTransfrontalieroTipo, 'F'),
			IsFormularioNumero = CAST(CASE
				WHEN o.IsIntegrazioneFir = 1 AND r.Lock = 2 THEN 1
				ELSE IIF(m.FormularioNumero IS NULL, 0, 1)
			END AS BIT),
			FormularioNumero = ISNULL(m.FormularioNumero, ''),
			FormularioDataEmissione = ISNULL(f.DataEmissione, GETDATE()),
			RentriFormularioStato = m.RentriFormularioStato,
			RentriFormularioDataPresaVisione = m.RentriFormularioDataPresaVisione,
			r.RentriIdentificativo,
			r.RentriData,
			ConservazioneSostitutiva = ISNULL(r.ConservazioneSostitutiva, 0),

			IsTrasportoTransfrontaliero = CAST(IIF(r.IdTrasportoTransfrontalieroTipo IS NOT NULL, 1, 0) AS BIT),
			IdTrasportoTransfrontalieroTipo = ISNULL(r.IdTrasportoTransfrontalieroTipo, 'D'),

			IdAutorizzazioneProduttoreDetentore = ISNULL(mp.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneDestinatario = ISNULL(md.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore1 = ISNULL(mt1.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore2 = ISNULL(mt2.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneTrasportatore3 = ISNULL(mt3.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario1 = ISNULL(mi1.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario2 = ISNULL(mi2.IdAutorizzazione, REPLICATE('0', 16)),
			IdAutorizzazioneIntermediario3 = ISNULL(mi3.IdAutorizzazione, REPLICATE('0', 16)),

			IsRelazionabile = CAST(IIF(EXISTS(SELECT 1
			FROM dbo.tblRifiutiOperazioniRelazioni
			WHERE Id = m.IdOperazione), 1, 0) AS BIT),
			IsRegistrazioneAuto = CAST(IIF(o.OperazioneAuto IS NULL, 0, 1) AS BIT),
			IsVeicoloFuoriUso = ISNULL(r.VeicoloFuoriUso, 0),

			IdRaee = ISNULL(r.IdRaee, '0'),

			VeicoloFuoriUsoNumero = ISNULL(r.VeicoloFuoriUsoNumero, ''),
			VeicoloFuoriUsoData = r.VeicoloFuoriUsoData,

			-- Esito
			IdEsito = ISNULL(r.IdEsito, '0'),
			IdCausaleRespingimento = ISNULL(r.IdCausaleRespingimento, 'N'),
			IdUnitaMisuraQuantitaRespinta = ISNULL(r.IdUnitaMisuraQuantitaRespinta, 'KG'),
			CausaleRespingimentoAltro = ISNULL(r.CausaleRespingimentoAltro, ''),
			QuantitaVerificata = ISNULL(r.QuantitaVerificata, 0),
			IsQuantitaVerificata = CAST(IIF(r.QuantitaVerificata IS NOT NULL, 1, 0) AS BIT),
			QuantitaRespinta = ISNULL(r.QuantitaRespinta, 0),
			DataFineTrasporto = r.DataFineTrasporto,

			-- Materiale
			IdMateriale = ISNULL(r.IdMateriale, '00'),
			MaterialeDescrizione = ISNULL(r.MaterialeDescrizione, ''),

			-- Provenienza
			IdAttivitaProvenienza = ISNULL(r.IdAttivitaProvenienza, '0'),

			IsIntegrazioneFir = ISNULL(o.IsIntegrazioneFir, 0),
			IsProduttore = ISNULL(o.IsProduttore, 0),
			IsTrasportatore = ISNULL(o.IsTrasportatore, 0),
			IsDestinatario = ISNULL(o.IsDestinatario, 0),
			IsIntermediario = ISNULL(o.IsIntermediario, 0),
			IsAttivitaRs = ISNULL(o.IsAttivitaRs, 0),
			IsEsito = ISNULL(o.IsEsito, 0),
			IsRentriAccettazione = ISNULL(o.IsRentriAccettazione, 0),
			IsAttivitaProvenienza = ISNULL(o.IsAttivitaProvenienza, 0),
			IsMateriale = ISNULL(o.IsMateriale, 0),
			IsStoccaggioIstantaneo = ISNULL(o.IsStoccaggioIstantaneo, 0),

			-- Rettifica: rett.Id valorizzato solo se questa registrazione è essa stessa una rettifica di
			-- un'altra (tblRentriRegistrazioniRettifiche.IdRettifica = r.Id). IsRettificaCampiBloccati
			-- riflette lato UI lo stesso gate applicato in uspRifiutiRegistrazioni_upd_Rettifica (punto 4
			-- della specifica): Eer/StatoFisico/UnitaMisura/Quantita non modificabili se l'originale ha
			-- relazioni carico/scarico attive su entrambi i lati.
			IdRegistrazioneOriginaleRettifica = rett.Id,
			RettificaRegistrazioneNumero = ro.Numero,
			RettificaRegistrazioneData = ro.Data,
			IsRettifica = CAST(IIF(rett.Id IS NOT NULL, 1, 0) AS BIT),
			IsAnnullamento = CAST(ISNULL(rett.Annullata, 0) AS BIT),
			IsRettificaCampiBloccati = CAST(IIF(rett.Id IS NOT NULL AND EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni r2 ON l.Id = r2.Id
					INNER JOIN dbo.tblRifiutiRegistrazioni rp2 ON l.IdParent = rp2.Id
				WHERE
					(
					l.Id = rett.Id
					OR l.IdParent = rett.Id
					)
					AND l.Quantita > 0
					AND r2.Lock < 2
					AND rp2.Lock < 2
			), 1, 0) AS BIT),

			Lock = r.Lock
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			LEFT JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento AND f.Lock < 2
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN dbo.tblRentriRegistrazioniRettifiche rett ON rett.IdRettifica = r.Id
			LEFT JOIN dbo.tblRifiutiRegistrazioni ro ON rett.Id = ro.Id
			-- Produttori
			LEFT JOIN dbo.tblRifiutiMovimentiProduttori mp ON m.Id = mp.Id AND mp.Pos = 0
			-- Destinatari
			LEFT JOIN dbo.tblRifiutiMovimentiDestinatari md ON m.Id = md.Id AND md.Pos = 0
			-- Trasportatori
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt1 ON m.Id = mt1.Id AND mt1.Pos = 0
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt2 ON m.Id = mt2.Id AND mt2.Pos = 1
			LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori mt3 ON m.Id = mt3.Id AND mt3.Pos = 2
			-- Intermediari
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi1 ON m.Id = mi1.Id AND mi1.Pos = 0
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi2 ON m.Id = mi2.Id AND mi2.Pos = 1
			LEFT JOIN dbo.tblRifiutiMovimentiIntermediari mi3 ON m.Id = mi3.Id AND mi3.Pos = 2
		WHERE
			r.Id = @Id
			AND r.Lock <= 2;

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
