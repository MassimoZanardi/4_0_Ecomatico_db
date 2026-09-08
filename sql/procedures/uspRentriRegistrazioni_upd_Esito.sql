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
