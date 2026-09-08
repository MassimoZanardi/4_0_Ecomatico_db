/*
	Deploy produzione - 2026-09-08 - Verifica esito conferimento da RENTRI (Registrazioni aT/T*aT)

	Contesto: per le Registrazioni con codice operazione RENTRI aT/T*aT (causali STT/STP/CST/CSX/CSM,
	IsEsito=1) l'azienda e' il mittente che conferisce il rifiuto a un destinatario terzo. Nuova azione
	"RENTRI - Verifica esito" in Rifiuti/Registrazioni/Edit: quando il destinatario chiude il FIR digitale
	(stato Accettato/RespintoAccettatoParzialmente) e carica su RENTRI la copia di chiusura, l'utente puo'
	verificare se la copia e' disponibile, leggere l'esito trasmesso e, confermando, salvarlo in locale e
	segnalare a RENTRI la presa visione della copia (obbligo per le parti diverse dal destinatario).

	Nota: l'endpoint hub di sola verifica (GET .../copia-digitale/verifica/...) e' un deploy separato
	sull'app 1_0_RentriApi (Api/ApiFormularioDigitale.cs), non incluso in questo script DB.

	1) ALTER TABLE dbo.tblRifiutiMovimenti ADD (idempotente, guardato con IF NOT EXISTS):
	   - RentriFormularioDataPresaVisione SMALLDATETIME NULL

	2) CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistrazioni_get: aggiunta la proiezione
	   RentriFormularioDataPresaVisione = m.RentriFormularioDataPresaVisione (nessun'altra riga cambiata).

	3) CREATE OR ALTER PROCEDURE dbo.uspRentriRegistrazioni_upd_Esito (nuova): salvataggio dedicato
	   dell'esito letto da RENTRI, stesso schema di uspRifiutiRegistrazioni_upd_Annullamento (rilettura
	   pass-through di tutti i campi non toccati + chiamata a uspRifiutiRegistrazioni_upd, non modificata).
	   La risoluzione Esito/CausaleRespingimento -> Id locale riusa
	   uspRifiutiRegistrazioni_get_MatchCodiciImportazione (stessa lookup gia' usata dall'acquisizione da
	   formulario digitale). QuantitaDestino/DataOraFineTrasporto RENTRI mappano su QuantitaVerificata/
	   DataFineTrasporto (come nell'acquisizione da formulario digitale) - QuantitaRespinta/
	   IdUnitaMisuraQuantitaRespinta restano invariati, RENTRI non li trasmette.
	   RentriFormularioDataPresaVisione viene valorizzata con GETDATE() in un UPDATE diretto separato,
	   unico punto dell'app che scrive questo campo (non e' un parametro di uspRifiutiRegistrazioni_upd).

	4) CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistrazioni_get_EsitoDescrizioni (nuova): descrizioni
	   leggibili di Esito/CausaleRespingimento per la sola modale di anteprima lato UI, prima della
	   conferma - nessun controllo di permesso/titolarita' (tabelle di riferimento statiche).

	Verificato su DB dev: colonna aggiunta, le 3 SP toccate/nuove ridistribuite senza errori di
	compilazione, query di controllo standard (ANSI_NULLS/QUOTED_IDENTIFIER/CRLF/XACT_ABORT) pulita su
	tutte e 3. Build di Ecomatico.Web e di Rentri.Api verde. Test end-to-end con una Registrazione reale
	e un destinatario che ha effettivamente chiuso il FIR su RENTRI non ancora eseguito (richiede il
	deploy applicativo, non solo DB, ed e' pendente lato utente).

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-08_verifica_esito_rentri.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- 1) Colonna su dbo.tblRifiutiMovimenti (idempotente)
--------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblRifiutiMovimenti') AND name = 'RentriFormularioDataPresaVisione')
BEGIN
	ALTER TABLE dbo.tblRifiutiMovimenti ADD RentriFormularioDataPresaVisione SMALLDATETIME NULL;
END
GO

--------------------------------------------------------------------------------
-- 2) dbo.uspRifiutiRegistrazioni_get
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

--------------------------------------------------------------------------------
-- 3) dbo.uspRentriRegistrazioni_upd_Esito (nuova)
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Salvataggio dedicato per l'esito di conferimento letto da RENTRI ("RENTRI - Verifica esito",
-- Rifiuti/Registrazioni/Edit, solo Registrazioni aT/T*aT con IsEsito=1) - stesso schema di
-- uspRifiutiRegistrazioni_upd_Annullamento: rilegge pass-through tutti i campi non toccati e richiama
-- uspRifiutiRegistrazioni_upd. I parametri @Esito/@EsitoCausaleRespingimento/@RespingimentoMotivo/
-- @QuantitaDestino/@DataOraFineTrasporto sono gli stessi nomi/valori di
-- RentriHubFormularioDigitaleDettaglioResponse (GET formulario-digitale/{app}/{id}/{numero}), passati
-- pari pari dal chiamante come per uspRifiutiMovimenti_ins_DaAcquisizioneFormulario. La risoluzione
-- Esito/CausaleRespingimento -> Id locale riusa uspRifiutiRegistrazioni_get_MatchCodiciImportazione
-- (stessa lookup gia' usata dall'acquisizione formulario digitale), mai un CASE hardcoded. Solo
-- QuantitaVerificata/DataFineTrasporto vengono aggiornati dall'esito RENTRI (come nell'acquisizione):
-- QuantitaRespinta/IdUnitaMisuraQuantitaRespinta restano invariati, RENTRI non li trasmette.
-- RentriFormularioDataPresaVisione viene valorizzata qui con GETDATE() dopo l'aggiornamento dei campi
-- Esito: e' l'unico punto dell'app che scrive questo campo, non e' un parametro di
-- uspRifiutiRegistrazioni_upd (che resta cosi' invariata per tutti gli altri chiamanti).
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

		-- Permesso + titolarità su @Id, PRIMA di leggere qualunque dato suo (stesso pattern di
		-- uspRifiutiRegistrazioni_upd_Annullamento)
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

		-- Rilettura pass-through di tutti i campi non toccati dall'esito RENTRI (stessa forma di
		-- uspRifiutiRegistrazioni_upd_Annullamento), cosi' uspRifiutiRegistrazioni_upd non vede alcuna
		-- differenza rispetto ai valori gia' presenti oltre a quelli qui sotto sovrascritti
		DECLARE
			@idMovimento CHAR(16), @idEer CHAR(6), @idProvenienza CHAR(1), @eerDescrizione VARCHAR(200),
			@idStatoFisico CHAR(1), @idAttivitaRs CHAR(2), @idUnitaMisura CHAR(2), @quantita DECIMAL(18, 2),
			@dataInizioTrasporto SMALLDATETIME, @idDocumentoTrasportoTipo CHAR(1), @formularioNumero VARCHAR(20),
			@idAutorizzazioneProduttoreDetentore CHAR(16), @idAutorizzazioneDestinatario CHAR(16),
			@idAutorizzazioneTrasportatore1 CHAR(16), @idAutorizzazioneTrasportatore2 CHAR(16), @idAutorizzazioneTrasportatore3 CHAR(16),
			@idAutorizzazioneIntermediario1 CHAR(16), @idAutorizzazioneIntermediario2 CHAR(16), @idAutorizzazioneIntermediario3 CHAR(16),
			@utenteNote VARCHAR(500), @registrazioneNote VARCHAR(500),
			@isVeicoloFuoriUso BIT, @veicoloFuoriUsoNumero VARCHAR(50), @veicoloFuoriUsoData DATE,
			@idRaee CHAR(1), @quantitaRespinta DECIMAL(18, 2), @idUnitaMisuraQuantitaRespinta CHAR(2),
			@idMateriale CHAR(2), @materialeDescrizione VARCHAR(200),
			@idAttivitaProvenienza CHAR(1), @registrazioneData DATE, @registrazioneNumero INT;

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
			@registrazioneNote = r.Note,
			@isVeicoloFuoriUso = ISNULL(r.VeicoloFuoriUso, 0),
			@veicoloFuoriUsoNumero = r.VeicoloFuoriUsoNumero,
			@veicoloFuoriUsoData = r.VeicoloFuoriUsoData,
			@idRaee = r.IdRaee,
			@quantitaRespinta = r.QuantitaRespinta,
			@idUnitaMisuraQuantitaRespinta = r.IdUnitaMisuraQuantitaRespinta,
			@idMateriale = r.IdMateriale,
			@materialeDescrizione = r.MaterialeDescrizione,
			@idAttivitaProvenienza = r.IdAttivitaProvenienza,
			@registrazioneData = r.[Data],
			@registrazioneNumero = r.Numero
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

		EXEC dbo.uspRifiutiRegistrazioni_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@IdEer = @idEer,
			@IdProvenienza = @idProvenienza,
			@EerDescrizione = @eerDescrizione,
			@IdStatoFisico = @idStatoFisico,
			@ClassiPericolo = @classiPericolo,
			@IdAttivitaRs = @idAttivitaRs,
			@RegistrazioneData = @registrazioneData,
			@RegistrazioneNumero = @registrazioneNumero,
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
			@RegistrazioneNote = @registrazioneNote,
			@UtenteNote = @utenteNote,
			@IdEtichette = @idEtichette,
			@IsVeicoloFuoriUso = @isVeicoloFuoriUso,
			@VeicoloFuoriUsoNumero = @veicoloFuoriUsoNumero,
			@VeicoloFuoriUsoData = @veicoloFuoriUsoData,
			@IdRaee = @idRaee,
			-- Esito RENTRI: unici campi sovrascritti qui
			@IdEsito = @idEsito,
			@QuantitaVerificata = @QuantitaDestino,
			@DataFineTrasporto = @dataOraFineTrasportoFinale,
			@IdCausaleRespingimento = @idCausaleRespingimento,
			@CausaleRespingimentoAltro = @respingimentoMotivoFinale,
			@IdUnitaMisuraQuantitaRespinta = @idUnitaMisuraQuantitaRespinta,
			@QuantitaRespinta = @quantitaRespinta,
			@IdMateriale = @idMateriale,
			@MaterialeDescrizione = @materialeDescrizione,
			@IdAttivitaProvenienza = @idAttivitaProvenienza;

		-- Unico punto dell'app che scrive questo campo: non e' un parametro di
		-- uspRifiutiRegistrazioni_upd, che resta invariata per tutti gli altri chiamanti
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
-- 4) dbo.uspRifiutiRegistrazioni_get_EsitoDescrizioni (nuova)
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Descrizioni leggibili per l'esito/causale di respingimento RENTRI, usate solo per la modale di anteprima
-- di "RENTRI - Verifica esito" (Rifiuti/Registrazioni/Edit) prima della conferma vera e propria - la
-- risoluzione Id effettiva ai fini del salvataggio resta in uspRentriRegistrazioni_upd_Esito
-- (uspRifiutiRegistrazioni_get_MatchCodiciImportazione), qui serve solo il Nome da mostrare all'utente.
-- Nessun controllo di permesso/titolarità: stesse tabelle di riferimento statiche di
-- uspRifiutiRegistrazioni_get_MatchCodiciImportazione, nessun dato di sessione coinvolto.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_EsitoDescrizioni]
	@Esito VARCHAR(5) = NULL,
	@EsitoCausaleRespingimento VARCHAR(5) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Esito = NULLIF(LTRIM(RTRIM(@Esito)), '');
		SET @EsitoCausaleRespingimento = NULLIF(LTRIM(RTRIM(@EsitoCausaleRespingimento)), '');

		SELECT
			DescrizioneEsito = (SELECT TOP 1 Nome
			FROM dbo.tblRifiutiRegistrazioniEsiti
			WHERE Codice = @Esito),
			DescrizioneCausaleRespingimento = (SELECT TOP 1 Nome
			FROM dbo.tblRifiutiRegistrazioniEsitiCausaliRespingimento
			WHERE Codice = @EsitoCausaleRespingimento);

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
