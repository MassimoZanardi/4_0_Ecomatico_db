/*
	Deploy produzione - 2026-09-09 - Traccia il caricamento copia FIR in "RENTRI - Carica copia FIR"

	Contenuto di questo script (solo 4_0_ecomatico, nessuna modifica all'hub condiviso 1_0_rentri):

	Motivazione: il pulsante "RENTRI - Carica copia FIR" (Rifiuti/Registrazioni/Edit, destinatario di un
	"carico di rifiuto ricevuti da terzi") non aveva alcun riscontro locale dell'esito - il gate restava
	aperto (RentriFormularioStato in Accettato/RespintoAccettatoParzialmente) anche dopo l'esecuzione
	riuscita, quindi il pulsante non scompariva mai dal menu Azioni. Riusata la colonna
	tblRifiutiMovimenti.RentriFormularioDataCopia, gia' presente ma mai valorizzata lato app (migrata da
	tblRifiutiFormulari il 2026-09-07, propedeutica a questo sviluppo).

	1) CREATE OR ALTER PROCEDURE dbo.uspRentriRegistrazioni_upd_CaricamentoCopia: nuova SP, valorizza
	   RentriFormularioDataCopia = GETDATE() sul Movimento - stesso pattern di
	   uspRentriRegistrazioni_upd_PresaVisione (permesso RRG, verifica o.IsRentriAccettazione = 1 invece di
	   o.IsEsito = 1, blocco se gia' valorizzata). La chiamata all'hub RENTRI e' gia' avvenuta lato chiamante
	   (RentriRegistrazioneAccettazioneService.CaricamentoCopiaInviaAsync) prima di questa SP.

	2) CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistrazioni_get: aggiunta 1 colonna alla SELECT esistente
	   (nessun'altra modifica alla SP) - RentriFormularioDataCopia = m.RentriFormularioDataCopia.

	Verificato su DB dev: nuova SP deployata senza errori di compilazione, smoke test con sessione a basso
	privilegio (diniego pulito), blocco su doppia esecuzione verificato con dati reali (ROLLBACK esplicito).

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-09_caricamento_copia_stato.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- 1) dbo.uspRentriRegistrazioni_upd_CaricamentoCopia (nuova SP)
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Conferma locale del caricamento su RENTRI della copia del FIR digitale ("RENTRI - Carica copia FIR",
-- Rifiuti/Registrazioni/Edit, lato destinatario di un "carico di rifiuto ricevuti da terzi" - IsRentriAccettazione).
-- Riusa la colonna tblRifiutiMovimenti.RentriFormularioDataCopia (esistente ma mai valorizzata lato app,
-- vedi migrazione 2026-09-07 da tblRifiutiFormulari), stesso pattern di uspRentriRegistrazioni_upd_PresaVisione:
-- la chiamata all'hub RENTRI (RentriHubFormularioDigitaleService.CaricamentoCopiaAsync) e' gia' avvenuta lato
-- chiamante prima di questa SP, qui si registra solo l'esito in locale per nascondere l'azione dal menu.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_upd_CaricamentoCopia]
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

		DECLARE @idMovimento CHAR(16), @rentriFormularioDataCopia SMALLDATETIME;
		SELECT
			@idMovimento = m.Id,
			@rentriFormularioDataCopia = m.RentriFormularioDataCopia
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE r.Id = @Id;

		IF @idMovimento IS NULL
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
				AND o.IsRentriAccettazione = 1
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Operazione non consentita: questa registrazione non è di tipo "carico da terzi"';
			GOTO BRANCH_END;
		END

		IF @rentriFormularioDataCopia IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il caricamento della copia del FIR è già stato registrato per questa registrazione';
			GOTO BRANCH_END;
		END

		UPDATE dbo.tblRifiutiMovimenti
		SET RentriFormularioDataCopia = GETDATE()
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
-- 2) dbo.uspRifiutiRegistrazioni_get (estesa)
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
			RentriFormularioDataCopia = m.RentriFormularioDataCopia,
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
GO
