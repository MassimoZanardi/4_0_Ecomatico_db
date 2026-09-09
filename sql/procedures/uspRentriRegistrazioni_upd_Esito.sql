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
-- UPDATE mirato SOLO sulle colonne Esito, MAI tramite uspRifiutiRegistrazioni_upd: una Registrazione con
-- IsEsito=1 e' per definizione un conferimento a terzi gia' inviato al registro RENTRI (RentriIdentificativo/
-- RentriData valorizzati) PRIMA che il destinatario trasmetta l'esito - il "blocco modifica post-invio"
-- della SP generica bloccherebbe sistematicamente questo aggiornamento, che invece deve sempre essere
-- consentito. La clausola SET dell'UPDATE sotto e' la garanzia strutturale che nessun'altra colonna venga
-- toccata (a differenza di un ipotetico bypass del blocco esteso all'intera SP generica, che dipenderebbe
-- solo dalla correttezza di un pass-through di valori invariati, senza alcuna rete di sicurezza residua).
-- Il SOLO blocco RentriIdentificativo/RentriData viene bypassato: quello per conservazione sostitutiva
-- (ConservazioneSostitutiva) e' indipendente dal timing di invio al registro e resta valido anche qui -
-- replicato esplicitamente sotto (audit di tutti i GOTO BRANCH_END di uspRifiutiRegistrazioni_upd: gli
-- altri controlli lì presenti riguardano solo campi mai toccati da questo UPDATE - FormularioNumero,
-- RegistrazioneNumero/Data, EER/StatoFisico/UnitaMisura, Quantita - quindi non applicabili qui).
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
		-- modificata (stesso controllo di uspRifiutiRegistrazioni_upd - indipendente dal blocco post-invio
		-- RENTRI bypassato sopra, resta valido anche per il solo aggiornamento dell'esito)
		DECLARE @conservazioneSostitutiva BIT;
		SELECT @conservazioneSostitutiva = ConservazioneSostitutiva
		FROM dbo.tblRifiutiRegistrazioni
		WHERE Id = @Id;

		IF ISNULL(@conservazioneSostitutiva, 0) = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è bloccata per la conservazione sostitutiva: non può più essere modificata';
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
