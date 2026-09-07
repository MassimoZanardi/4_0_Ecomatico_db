SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Crea, in un'unica transazione, la bozza (Lock=2) di una Registrazione o di un Formulario a partire dai
-- dati di un formulario digitale RENTRI ("RENTRI - Acquisisci da formulario digitale", Rifiuti/Registrazioni
-- e Rifiuti/Formulari) - stesso ruolo della SP legacy 3.1 uspRifiutiSchede_ins_ImportazioneFormularioDigitale,
-- riscritta sullo schema 4.0. @ModalitaRitorno ('R'/'F') decide quale sola entità creare (mai entrambe:
-- in 4.0 Registrazioni e Formulari sono percorsi di creazione separati, a differenza della legacy).
--
-- Risoluzione FK/lookup interamente qui dentro, riusando le SP già esistenti invece di duplicarne la
-- logica: uspRifiutiAutorizzazioni_get_MatchImportazione (Produttore/Destinatario/Trasportatore/
-- Intermediario per Codice Fiscale) e uspRifiutiRegistrazioni_get_MatchCodiciImportazione (stato
-- fisico/attività R-D/esito/causale respingimento/analisi/ADR/unità di misura). Nessun match trovato -> il
-- relativo campo resta NULL, l'utente completa a mano da Edit.
--
-- La bozza risultante (Lock=2) segue esattamente lo stesso ciclo di vita di "Nuova registrazione"/"Nuovo
-- formulario": se l'utente preme Annulla in Edit, uspRifiutiRegistrazioni_del/uspRifiutiFormulari_del la
-- cancellano (hard delete, verificato che coprano tutte le tabelle popolate qui); se preme Salva, il
-- normale uspRifiutiRegistrazioni_upd/uspRifiutiFormulari_upd la finalizza con tutte le sue validazioni.
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMovimenti_ins_DaAcquisizioneFormulario]
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@ModalitaRitorno CHAR(1) = NULL, -- 'R' Registrazione, 'F' Formulario

	@Numero VARCHAR(20) = NULL,
	@DataEmissione DATE = NULL,
	@Esito VARCHAR(5) = NULL,
	@EsitoCausaleRespingimento VARCHAR(5) = NULL,
	@RespingimentoMotivo VARCHAR(500) = NULL,
	@DataOraFineTrasporto DATETIME2(0) = NULL,
	@Eer CHAR(6) = NULL,
	@EerDescrizione VARCHAR(200) = NULL,
	@StatoFisico VARCHAR(5) = NULL,
	@ClassiPericolo VARCHAR(200) = NULL,
	@Provenienza CHAR(1) = NULL,
	@Quantita DECIMAL(18, 3) = NULL,
	@QuantitaDestino DECIMAL(18, 3) = NULL,
	@UnitaMisura VARCHAR(5) = NULL,
	@Note VARCHAR(500) = NULL,

	@ProduttoreAutorizzazione VARCHAR(20) = NULL,
	@ProduttoreCodiceFiscale VARCHAR(20) = NULL,
	@DestinatarioAutorizzazione VARCHAR(20) = NULL,
	@DestinatarioCodiceFiscale VARCHAR(20) = NULL,
	@TrasportatoreAutorizzazioneAlbo VARCHAR(20) = NULL,
	@TrasportatoreCodiceFiscale VARCHAR(20) = NULL,
	@IntermediarioAutorizzazioneAlbo VARCHAR(20) = NULL,
	@IntermediarioCodiceFiscale VARCHAR(20) = NULL,
	@Intermediario2AutorizzazioneAlbo VARCHAR(20) = NULL,
	@Intermediario2CodiceFiscale VARCHAR(20) = NULL,

	@Destinazione VARCHAR(5) = NULL,
	@DataOraInizioTrasporto VARCHAR(20) = NULL, -- "yyyy-MM-dd HH:mm", come restituito dall'hub
	@ConducenteNome VARCHAR(50) = NULL,
	@ConducenteCognome VARCHAR(50) = NULL,
	@TargaMotrice VARCHAR(10) = NULL,
	@TargaRimorchio VARCHAR(10) = NULL,
	@Percorso VARCHAR(200) = NULL,
	@Colli VARCHAR(50) = NULL,
	@NumeroONU VARCHAR(20) = NULL,
	@ClasseADR VARCHAR(5) = NULL,
	@AdrNote VARCHAR(200) = NULL,
	@Analisi VARCHAR(20) = NULL,
	@AnalisiNumero VARCHAR(50) = NULL,
	@AnalisiData VARCHAR(20) = NULL,
	@QuantitaVerificataPartenza BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @returnId CHAR(16) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');
		SET @ModalitaRitorno = NULLIF(LTRIM(RTRIM(@ModalitaRitorno)), '');
		SET @Numero = NULLIF(UPPER(LTRIM(RTRIM(@Numero))), '');
		SET @EerDescrizione = NULLIF(LTRIM(RTRIM(@EerDescrizione)), '');
		SET @ClassiPericolo = NULLIF(LTRIM(RTRIM(@ClassiPericolo)), '');
		SET @Note = NULLIF(LTRIM(RTRIM(@Note)), '');
		SET @RespingimentoMotivo = NULLIF(LTRIM(RTRIM(@RespingimentoMotivo)), '');
		SET @ConducenteNome = NULLIF(LTRIM(RTRIM(@ConducenteNome)), '');
		SET @ConducenteCognome = NULLIF(LTRIM(RTRIM(@ConducenteCognome)), '');
		SET @TargaMotrice = NULLIF(LTRIM(RTRIM(@TargaMotrice)), '');
		SET @TargaRimorchio = NULLIF(LTRIM(RTRIM(@TargaRimorchio)), '');
		SET @Percorso = NULLIF(LTRIM(RTRIM(@Percorso)), '');
		SET @NumeroONU = NULLIF(LTRIM(RTRIM(@NumeroONU)), '');
		SET @AdrNote = NULLIF(LTRIM(RTRIM(@AdrNote)), '');
		SET @AnalisiNumero = NULLIF(LTRIM(RTRIM(@AnalisiNumero)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @ModalitaRitorno NOT IN ('R', 'F')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @ModalitaRitorno deve essere ''R'' o ''F''';
			GOTO BRANCH_END;
		END
		IF @Numero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Numero formulario non valorizzato';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		DECLARE @idFunzionePermesso CHAR(3) = IIF(@ModalitaRitorno = 'F', 'RFR', 'RRG');
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzionePermesso,
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
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE
			@operazione CHAR(1), @isProduttore BIT, @isTrasportatore BIT, @isDestinatario BIT,
			@isIntermediario BIT, @isEsito BIT, @isAttivitaRs BIT, @isIntegrazioneFir BIT, @isFormulario BIT;
		SELECT
			@operazione = Operazione, @isProduttore = IsProduttore, @isTrasportatore = IsTrasportatore,
			@isDestinatario = IsDestinatario, @isIntermediario = IsIntermediario, @isEsito = IsEsito,
			@isAttivitaRs = IsAttivitaRs, @isIntegrazioneFir = IsIntegrazioneFir, @isFormulario = IsFormulario
		FROM dbo.tblRifiutiOperazioni
		WHERE Id = @IdOperazione;

		IF @operazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Causale non valida';
			GOTO BRANCH_END;
		END
		IF (@ModalitaRitorno = 'R' AND ISNULL(@isIntegrazioneFir, 0) = 0) OR (@ModalitaRitorno = 'F' AND ISNULL(@isFormulario, 0) = 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La causale indicata non è valida per l''acquisizione da formulario digitale';
			GOTO BRANCH_END;
		END

		-- Duplicato: stesso numero di formulario già presente e attivo nel registro (stesso principio del
		-- controllo in uspRifiutiRegistrazioni_upd/uspRifiutiFormulari_upd, qui anticipato per non creare
		-- una bozza inutile)
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiMovimenti m
			WHERE
				m.IdRegistro = @IdRegistro
				AND m.FormularioNumero = @Numero
				AND
					(
					EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioni r WHERE r.IdMovimento = m.Id AND r.Lock < 2)
					OR EXISTS (SELECT 1 FROM dbo.tblRifiutiFormulari f WHERE f.IdMovimento = m.Id AND f.Lock < 2)
					)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra registrazione o formulario con lo stesso numero di formulario è già presente in questo registro';
			GOTO BRANCH_END;
		END

		-- ── Risoluzione FK/lookup, riusando le SP dedicate già esistenti ─────────────────────
		CREATE TABLE #match (
			IdAutorizzazioneProduttoreDetentore CHAR(16) NULL,
			IdAutorizzazioneDestinatario CHAR(16) NULL,
			IdAutorizzazioneTrasportatore1 CHAR(16) NULL,
			IdAutorizzazioneIntermediario1 CHAR(16) NULL,
			IdAutorizzazioneIntermediario2 CHAR(16) NULL
		);
		INSERT #match
		EXEC dbo.uspRifiutiAutorizzazioni_get_MatchImportazione
			@IdSessione = @IdSessione, @IdRegistro = @IdRegistro,
			@ProduttoreCodiceFiscale = @ProduttoreCodiceFiscale, @ProduttoreAutorizzazione = @ProduttoreAutorizzazione,
			@DestinatarioCodiceFiscale = @DestinatarioCodiceFiscale, @DestinatarioAutorizzazione = @DestinatarioAutorizzazione,
			@TrasportatoreCodiceFiscale = @TrasportatoreCodiceFiscale, @TrasportatoreAutorizzazione = @TrasportatoreAutorizzazioneAlbo,
			@IntermediarioCodiceFiscale = @IntermediarioCodiceFiscale, @IntermediarioAutorizzazione = @IntermediarioAutorizzazioneAlbo,
			@Intermediario2CodiceFiscale = @Intermediario2CodiceFiscale, @Intermediario2Autorizzazione = @Intermediario2AutorizzazioneAlbo;

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
			@StatoFisicoCodice = @StatoFisico, @AttivitaRsCodice = @Destinazione, @AnalisiTipoCodice = @Analisi,
			@AdrCodice = @ClasseADR, @UnitaMisuraCodice = @UnitaMisura, @EsitoCodice = @Esito,
			@CausaleRespingimentoCodice = @EsitoCausaleRespingimento;

		DECLARE
			@idAutorizzazioneProduttoreDetentore CHAR(16), @idAutorizzazioneDestinatario CHAR(16),
			@idAutorizzazioneTrasportatore1 CHAR(16), @idAutorizzazioneIntermediario1 CHAR(16), @idAutorizzazioneIntermediario2 CHAR(16),
			@idStatoFisico CHAR(1), @idAttivitaRs CHAR(2), @idAnalisiTipo CHAR(1), @idAdr CHAR(2), @idUnitaMisura CHAR(2),
			@idEsito CHAR(1), @idCausaleRespingimento CHAR(1);
		SELECT TOP 1
			@idAutorizzazioneProduttoreDetentore = IdAutorizzazioneProduttoreDetentore,
			@idAutorizzazioneDestinatario = IdAutorizzazioneDestinatario,
			@idAutorizzazioneTrasportatore1 = IdAutorizzazioneTrasportatore1,
			@idAutorizzazioneIntermediario1 = IdAutorizzazioneIntermediario1,
			@idAutorizzazioneIntermediario2 = IdAutorizzazioneIntermediario2
		FROM #match;
		SELECT TOP 1
			@idStatoFisico = IdStatoFisico, @idAttivitaRs = IdAttivitaRs, @idAnalisiTipo = IdAnalisiTipo,
			@idAdr = IdAdr, @idUnitaMisura = IdUnitaMisura, @idEsito = IdEsito, @idCausaleRespingimento = IdCausaleRespingimento
		FROM #codici;

		-- Autorizzazioni non applicabili al ruolo dell'operazione: azzerate, stesso principio di
		-- uspRifiutiRegistrazioni_upd (righe "IF @isProduttore = 0 ... SET NULL")
		IF ISNULL(@isProduttore, 0) = 0 SET @idAutorizzazioneProduttoreDetentore = NULL;
		IF ISNULL(@isDestinatario, 0) = 0 SET @idAutorizzazioneDestinatario = NULL;
		IF ISNULL(@isTrasportatore, 0) = 0 SET @idAutorizzazioneTrasportatore1 = NULL;
		IF ISNULL(@isIntermediario, 0) = 0
		BEGIN
			SET @idAutorizzazioneIntermediario1 = NULL;
			SET @idAutorizzazioneIntermediario2 = NULL;
		END
		IF ISNULL(@isEsito, 0) = 0
		BEGIN
			SET @idEsito = NULL;
			SET @idCausaleRespingimento = NULL;
			SET @RespingimentoMotivo = NULL;
		END
		IF ISNULL(@isAttivitaRs, 0) = 0 SET @idAttivitaRs = NULL;

		-- ── Normalizzazione quantità/date con sentinella (stesso principio della legacy) ─────
		DECLARE @quantitaFinale DECIMAL(18, 3) = IIF(@Quantita >= 0, @Quantita, 0);
		DECLARE @quantitaVerificataFinale DECIMAL(18, 3) = IIF(@QuantitaDestino >= 0, @QuantitaDestino, NULL);

		DECLARE @dataOraInizioTrasportoFinale DATETIME2(0) = TRY_CAST(@DataOraInizioTrasporto AS DATETIME2(0));
		IF @dataOraInizioTrasportoFinale >= '20500101' SET @dataOraInizioTrasportoFinale = NULL;

		IF @DataOraFineTrasporto >= '20500101' SET @DataOraFineTrasporto = NULL;

		DECLARE @dataEmissioneFinale DATE = IIF(ISNULL(@DataEmissione, '19000101') < '20000101', CAST(GETDATE() AS DATE), @DataEmissione);

		DECLARE @analisiDataFinale DATE = TRY_CAST(@AnalisiData AS DATE);

		DECLARE @registrazioneData DATE = COALESCE(CAST(@dataOraInizioTrasportoFinale AS DATE), CAST(@DataOraFineTrasporto AS DATE), CAST(GETDATE() AS DATE));

		CREATE TABLE #numero (Rtn INT);
		INSERT #numero EXEC dbo.uspRifiutiRegistrazioni_get_UltimoNumero @IdRegistro = @IdRegistro, @Data = @registrazioneData, @IdSessione = @IdSessione;
		DECLARE @registrazioneNumero INT = (SELECT TOP 1 Rtn + 1 FROM #numero);

		-- ── Creazione ─────────────────────────────────────────────────────────────────────
		DECLARE @idMovimento CHAR(16), @idRegistrazione CHAR(16), @idFormulario CHAR(16);

		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;
		IF @ModalitaRitorno = 'R'
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idRegistrazione OUTPUT;
		ELSE
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idFormulario OUTPUT;

		BEGIN TRANSACTION;

			INSERT dbo.tblRifiutiMovimenti
				(Id, IdRegistro, IdOperazione, IdEer, EerDescrizione, IdStatoFisico, IdUnitaMisura, IdProvenienza, Quantita, FormularioNumero, DataInizioTrasporto, Note)
			VALUES
				(@idMovimento, @IdRegistro, @IdOperazione, @Eer, @EerDescrizione, @idStatoFisico, @idUnitaMisura, @Provenienza, @quantitaFinale, @Numero, @dataOraInizioTrasportoFinale, @Note);

			IF @idAutorizzazioneProduttoreDetentore IS NOT NULL
				INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
				VALUES (@idMovimento, @idAutorizzazioneProduttoreDetentore, @quantitaFinale, 0);

			IF @idAutorizzazioneDestinatario IS NOT NULL
				INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @idAutorizzazioneDestinatario, 0);

			-- Solo il trasporto su strada e' estratto dal FIR (conducente/targhe/percorso): se presente uno
			-- di questi dati si assume 'G' (terrestre), altrimenti si lascia decidere all'utente da Edit.
			DECLARE @isTrasportoStrada BIT = CAST(IIF(@TargaMotrice IS NOT NULL OR @ConducenteNome IS NOT NULL, 1, 0) AS BIT);
			IF @idAutorizzazioneTrasportatore1 IS NOT NULL
				INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
				VALUES (@idMovimento, @idAutorizzazioneTrasportatore1, IIF(@isTrasportoStrada = 1, 'G', NULL), 0);

			IF @idAutorizzazioneIntermediario1 IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @idAutorizzazioneIntermediario1, 0);

				IF @idAutorizzazioneIntermediario2 IS NOT NULL
					INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
					VALUES (@idMovimento, @idAutorizzazioneIntermediario2, 1);
			END

			IF @ClassiPericolo IS NOT NULL
				INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
				SELECT @idMovimento, c.Id
				FROM
					STRING_SPLIT(@ClassiPericolo, ';') v
					INNER JOIN dbo.tblRifiutiClassiPericolo c ON c.Codice = v.value;

			IF @ModalitaRitorno = 'R'
			BEGIN
				INSERT dbo.tblRifiutiRegistrazioni
					(Id, IdMovimento, Operazione, [Data], Numero, IdEsito, QuantitaVerificata, DataFineTrasporto, IdCausaleRespingimento, CausaleRespingimentoAltro, Lock)
				VALUES
					(@idRegistrazione, @idMovimento, @operazione, @registrazioneData, @registrazioneNumero, @idEsito, @quantitaVerificataFinale, @DataOraFineTrasporto, @idCausaleRespingimento, LEFT(@RespingimentoMotivo, 100), 2);

				SET @returnId = @idRegistrazione;
			END
			ELSE
			BEGIN
				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, IdAdr, IdAnalisiTipo, TrasportoAdr, DataEmissione, AnalisiData, AnalisiNumero, VerificatoInPartenza, NumeroOnu, AdrNote, ColliNumero, Lock)
				VALUES
					(@idFormulario, @idMovimento, @idAdr, @idAnalisiTipo, CAST(IIF(@ClasseADR IS NOT NULL, 1, 0) AS BIT), @dataEmissioneFinale, @analisiDataFinale, @AnalisiNumero, @QuantitaVerificataPartenza, @NumeroONU, @AdrNote, @Colli, 2);

				IF @isTrasportoStrada = 1
					INSERT dbo.tblRifiutiFormulariTrasportiTerresti (Id, TargaMotrice, TargaRimorchio, ConducenteNome, ConducenteCognome, Percorso)
					VALUES (@idFormulario, @TargaMotrice, @TargaRimorchio, @ConducenteNome, @ConducenteCognome, @Percorso);

				SET @returnId = @idFormulario;
			END

		COMMIT TRANSACTION;

	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

	SELECT Id = @returnId;

END;
GO
