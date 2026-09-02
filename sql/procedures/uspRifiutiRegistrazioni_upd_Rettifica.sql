SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Salvataggio dedicato per una registrazione di rettifica (@Id, collegata a un originale via
-- tblRentriRegistrazioniRettifiche.IdRettifica). Riusa integralmente uspRifiutiRegistrazioni_upd per
-- salvare la rettifica stessa (stessa validazione Data/Numero/rinumerazione/autorizzazioni/esito/ecc. di
-- una registrazione normale - la rettifica non è ancora inviata al RENTRI, quindi il blocco "già inviata"
-- di quella SP non la riguarda), poi applica le regole specifiche di rettifica (punti 4/5 della specifica):
-- se l'originale ha relazioni carico/scarico attive, Eer/StatoFisico/UnitaMisura/Quantita non possono
-- differire dai valori correnti dell'originale (rifiutati); altrimenti vengono propagati sull'originale
-- stesso, cosi' che eventuali future relazioni carico/scarico su di esso usino i nuovi valori corretti.
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

		-- Normalizzazione minima per il confronto col gate qui sotto (la normalizzazione "vera" per il
		-- salvataggio della rettifica resta tutta dentro uspRifiutiRegistrazioni_upd, richiamata più sotto)
		DECLARE @idEerNorm CHAR(6) = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		DECLARE @idStatoFisicoNorm CHAR(1) = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		DECLARE @idUnitaMisuraNorm CHAR(2) = ISNULL(NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), ''), 'KG');

		DECLARE @originaleIdEer CHAR(6), @originaleIdStatoFisico CHAR(1), @originaleIdUnitaMisura CHAR(2), @originaleQuantita DECIMAL(18, 2);
		SELECT
			@originaleIdEer = mo.IdEer,
			@originaleIdStatoFisico = mo.IdStatoFisico,
			@originaleIdUnitaMisura = mo.IdUnitaMisura,
			@originaleQuantita = mo.Quantita
		FROM
			dbo.tblRifiutiRegistrazioni ro
			INNER JOIN dbo.tblRifiutiMovimenti mo ON ro.IdMovimento = mo.Id
		WHERE ro.Id = @idOriginale;

		-- Punto 4: relazione carico/scarico attiva sull'originale, su entrambi i lati (figlio e padre) -
		-- Eer/StatoFisico/UnitaMisura/Quantita restano bloccati sui valori correnti dell'originale
		DECLARE @originaleHaRelazioniAttive BIT = CAST(IIF(EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.Id = r.Id
				INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
			WHERE
				(
				l.Id = @idOriginale
				OR l.IdParent = @idOriginale
				)
				AND l.Quantita > 0
				AND r.Lock < 2
				AND rp.Lock < 2
		), 1, 0) AS BIT);

		IF @originaleHaRelazioniAttive = 1 AND (
			ISNULL(@idEerNorm, '') <> ISNULL(@originaleIdEer, '')
			OR ISNULL(@idStatoFisicoNorm, '') <> ISNULL(@originaleIdStatoFisico, '')
			OR ISNULL(@idUnitaMisuraNorm, '') <> ISNULL(@originaleIdUnitaMisura, '')
			OR ISNULL(@Quantita, 0) <> ISNULL(@originaleQuantita, 0)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione rettificata è associata ad altre con carico/scarico: Eer, stato fisico, unità di misura e quantità non possono essere modificati';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

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

			-- Punto 5: nessuna relazione attiva sull'originale -> propaga i nuovi valori sull'originale
			-- stesso (bypassa volutamente il blocco "già inviata" di uspRifiutiRegistrazioni_upd: qui si
			-- sta scrivendo sull'originale per effetto della rettifica, non modificandolo direttamente da UI)
			IF @originaleHaRelazioniAttive = 0
				UPDATE mo
				SET
					IdEer = @idEerNorm,
					EerDescrizione = CASE WHEN @idEerNorm LIKE '%99' THEN @EerDescrizione ELSE NULL END,
					IdStatoFisico = @idStatoFisicoNorm,
					IdUnitaMisura = @idUnitaMisuraNorm,
					Quantita = @Quantita
				FROM
					dbo.tblRifiutiMovimenti mo
					INNER JOIN dbo.tblRifiutiRegistrazioni ro ON ro.IdMovimento = mo.Id
				WHERE ro.Id = @idOriginale;

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
