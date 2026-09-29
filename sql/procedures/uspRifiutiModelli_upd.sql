SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiModelli_upd]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdProvenienza CHAR(1) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@MaterialeDescrizione VARCHAR(200) = NULL,
	@IdAttivitaRs CHAR(2) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@IdAutorizzazioneProduttoreDetentore CHAR(16) = NULL,
	@LuogoDiProduzione BIT = NULL,
	@Detentore BIT = NULL,
	@IdAutorizzazioneDestinatario CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore1 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore2 CHAR(16) = NULL,
	@IdAutorizzazioneTrasportatore3 CHAR(16) = NULL,
	@IdTipoTrasporto1 CHAR(1) = NULL,
	@IdTipoTrasporto2 CHAR(1) = NULL,
	@IdTipoTrasporto3 CHAR(1) = NULL,
	@IdAutorizzazioneIntermediario1 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario2 CHAR(16) = NULL,
	@IdAutorizzazioneIntermediario3 CHAR(16) = NULL,
	@IdDocumentoTrasportoTipo CHAR(1) = NULL,
	@IdRaee CHAR(1) = NULL,
	@AllaRinfusa BIT = NULL,
	@IdAdr CHAR(2) = NULL,
	@IdImballo CHAR(2) = NULL,
	@TrasportoAdr BIT = NULL,
	@NumeroOnu VARCHAR(20) = NULL,
	@AdrNote VARCHAR(200) = NULL,
	@IdAnalisiTipo CHAR(1) = NULL,
	@AnalisiNumero VARCHAR(50) = NULL,
	@AnalisiData DATE = NULL,
	@RegistrazioneNote VARCHAR(500) = NULL,
	@FormularioNote VARCHAR(500) = NULL,
	@UtenteNote VARCHAR(500) = NULL,
	@ClassiPericolo VARCHAR(50) = NULL,
	@IdEtichette VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdProvenienza = NULLIF(LTRIM(RTRIM(@IdProvenienza)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdAttivitaRs = NULLIF(LTRIM(RTRIM(@IdAttivitaRs)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');
		SET @IdAutorizzazioneProduttoreDetentore = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneProduttoreDetentore)), '');
		SET @IdAutorizzazioneDestinatario = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneDestinatario)), '');
		SET @IdAutorizzazioneTrasportatore1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore1)), '');
		SET @IdAutorizzazioneTrasportatore2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore2)), '');
		SET @IdAutorizzazioneTrasportatore3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneTrasportatore3)), '');
		SET @IdTipoTrasporto1 = NULLIF(LTRIM(RTRIM(@IdTipoTrasporto1)), '');
		SET @IdTipoTrasporto2 = NULLIF(LTRIM(RTRIM(@IdTipoTrasporto2)), '');
		SET @IdTipoTrasporto3 = NULLIF(LTRIM(RTRIM(@IdTipoTrasporto3)), '');
		SET @IdAutorizzazioneIntermediario1 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario1)), '');
		SET @IdAutorizzazioneIntermediario2 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario2)), '');
		SET @IdAutorizzazioneIntermediario3 = NULLIF(LTRIM(RTRIM(@IdAutorizzazioneIntermediario3)), '');
		SET @IdDocumentoTrasportoTipo = NULLIF(LTRIM(RTRIM(@IdDocumentoTrasportoTipo)), '');
		SET @IdRaee = NULLIF(LTRIM(RTRIM(@IdRaee)), '');
		SET @IdAdr = NULLIF(LTRIM(RTRIM(@IdAdr)), '');
		SET @IdImballo = NULLIF(LTRIM(RTRIM(@IdImballo)), '');
		SET @IdAnalisiTipo = NULLIF(LTRIM(RTRIM(@IdAnalisiTipo)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 50, 1);
		SET @MaterialeDescrizione = dbo.ufnStringhe_get_SenzaSpazi(@MaterialeDescrizione, 200, 1);
		SET @NumeroOnu = dbo.ufnStringhe_get_SenzaSpazi(@NumeroOnu, 20, 1);
		SET @AdrNote = dbo.ufnStringhe_get_SenzaSpazi(@AdrNote, 200, 1);
		SET @AnalisiNumero = dbo.ufnStringhe_get_SenzaSpazi(@AnalisiNumero, 50, 1);
		SET @RegistrazioneNote = dbo.ufnStringhe_get_SenzaSpazi(@RegistrazioneNote, 500, 1);
		SET @FormularioNote = dbo.ufnStringhe_get_SenzaSpazi(@FormularioNote, 500, 1);
		SET @UtenteNote = dbo.ufnStringhe_get_SenzaSpazi(@UtenteNote, 500, 1);

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
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RMD', @Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: prima non esisteva alcun controllo che @Id appartenesse
		-- all'azienda della sessione — chiunque avesse permesso RMD≥2 poteva
		-- modificare il modello di un'altra azienda conoscendone l'Id.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro record con lo stesso nome
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiModelli
			WHERE
				Id <> @Id
				AND IdRegistro = @IdRegistro
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro modello con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		-- Il produttore/detentore del Modello viene copiato sui carichi generati automaticamente
		-- (uspRifiutiRegistrazioni_ins_CaricoAuto): con almeno una combinazione già configurata,
		-- non può restare vuoto.
		IF @IdAutorizzazioneProduttoreDetentore IS NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiModelliRegistrazioniAuto
			WHERE IdModello = @Id AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il produttore o detentore, obbligatorio con registrazioni automatiche impostate';
			GOTO BRANCH_END;
		END

		-- IdOperazione è fisso sul modello (scelto alla creazione, non modificabile qui): da esso
		-- deriviamo quali campi sono applicabili, imponendo NULL su quelli non pertinenti a
		-- prescindere da cosa viene passato dal chiamante — non ci si fida che client/C# l'abbiano
		-- già fatto correttamente. @IsMateriale = 1 solo per l'operazione 'K' (produzione di
		-- materiali): Eer/StatoFisico/Provenienza/ClassiPericolo/Raee/DocumentoTrasporto si
		-- escludono a vicenda con Materiale/MaterialeDescrizione. @IsFormulario governa i campi
		-- copiati solo su tblRifiutiFormulari (Imballo/AllaRinfusa/ADR completo/Analisi/Note
		-- formulario), inutilizzabili per le operazioni che non possono mai generare un formulario.
		DECLARE @idOperazioneModello CHAR(1);
		DECLARE @isFormulario BIT;
		SELECT
			@idOperazioneModello = m.IdOperazione,
			@isFormulario = ISNULL(o.IsFormulario, 0)
		FROM
			dbo.tblRifiutiModelli m
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
		WHERE m.Id = @Id;

		DECLARE @isMateriale BIT = IIF(@idOperazioneModello = 'K', 1, 0);

		BEGIN TRANSACTION;

			-- Aggiorna le classi di pericolo (non applicabili al Materiale)
			DELETE dbo.tblRifiutiModelliClassiPericolo
			WHERE Id = @Id;

			INSERT dbo.tblRifiutiModelliClassiPericolo
				(Id, IdClasse)
			SELECT
				@Id,
				c.Id
			FROM
				dbo.tblRifiutiClassiPericolo c
				INNER JOIN STRING_SPLIT(@ClassiPericolo, ';') v ON c.Id = v.value
			WHERE @isMateriale = 0;

			-- Aggiorna le etichette
			DELETE dbo.tblRifiutiModelliEtichette
			WHERE Id = @Id;

			INSERT dbo.tblRifiutiModelliEtichette
				(Id, IdEtichetta)
			SELECT TOP 3
				@Id,
				e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

			-- Produttore/detentore: la select propone anche le sedi senza autorizzazione specifica (Id della
			-- sede). Come in uspRifiutiRegistrazioni_upd/uspRifiutiFormulari_upd, la sede viene convertita
			-- nella sua autorizzazione "Nessuna" (creata se non esiste): la colonna ha FK verso
			-- tblRifiutiAutorizzazioni.
			IF @IdAutorizzazioneProduttoreDetentore IS NOT NULL
				AND EXISTS (SELECT 1
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
						(@IdAutorizzazioneProduttoreDetentore, @idSede, 'P', '19000101', '20501231', 1, 0, 0);
				END
			END

			UPDATE dbo.tblRifiutiModelli
			SET
				Nome = @Nome,
				IdEer = IIF(@isMateriale = 1, NULL, @IdEer),
				IdProvenienza = IIF(@isMateriale = 1, NULL, @IdProvenienza),
				IdStatoFisico = IIF(@isMateriale = 1, NULL, @IdStatoFisico),
				IdMateriale = IIF(@isMateriale = 1, @IdMateriale, NULL),
				MaterialeDescrizione = IIF(@isMateriale = 1, @MaterialeDescrizione, NULL),
				IdAttivita = @IdAttivitaRs,
				IdUnitaMisura = @IdUnitaMisura,
				IdImballo = IIF(@isFormulario = 1, @IdImballo, NULL),
				IdAdr = IIF(@isFormulario = 1, @IdAdr, NULL),
				IdAutorizzazioneProduttoreDetentore = @IdAutorizzazioneProduttoreDetentore,
				LuogoDiProduzione = @LuogoDiProduzione,
				Detentore = @Detentore,
				IdAutorizzazioneDestinatario = @IdAutorizzazioneDestinatario,
				IdAutorizzazioneTrasportatore1 = @IdAutorizzazioneTrasportatore1,
				IdAutorizzazioneTrasportatore2 = @IdAutorizzazioneTrasportatore2,
				IdAutorizzazioneTrasportatore3 = @IdAutorizzazioneTrasportatore3,
				IdTipoTrasporto1 = @IdTipoTrasporto1,
				IdTipoTrasporto2 = @IdTipoTrasporto2,
				IdTipoTrasporto3 = @IdTipoTrasporto3,
				IdAutorizzazioneIntermediario1 = @IdAutorizzazioneIntermediario1,
				IdAutorizzazioneIntermediario2 = @IdAutorizzazioneIntermediario2,
				IdAutorizzazioneIntermediario3 = @IdAutorizzazioneIntermediario3,
				IdTrasportoTransfrontalieroTipo = IIF(@isMateriale = 1, NULL, @IdDocumentoTrasportoTipo),
				IdRaee = IIF(@isMateriale = 1, NULL, @IdRaee),
				AllaRinfusa = IIF(@isFormulario = 1, @AllaRinfusa, NULL),
				TrasportoAdr = IIF(@isFormulario = 1, @TrasportoAdr, NULL),
				NumeroOnu = IIF(@isFormulario = 1, @NumeroOnu, NULL),
				AdrNote = IIF(@isFormulario = 1, @AdrNote, NULL),
				IdAnalisiTipo = IIF(@isFormulario = 1, @IdAnalisiTipo, NULL),
				AnalisiNumero = IIF(@isFormulario = 1, @AnalisiNumero, NULL),
				AnalisiData = IIF(@isFormulario = 1, @AnalisiData, NULL),
				RegistrazioneNote = @RegistrazioneNote,
				FormularioNote = IIF(@isFormulario = 1, @FormularioNote, NULL),
				UtenteNote = @UtenteNote,
				Etichette = dbo.ufnRifiutiModelli_get_Etichette(Id),
				Lock = 0
			WHERE Id = @Id;

			-- @@ROWCOUNT mancante in origine — stesso pattern già corretto altrove nel progetto.
			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Modello non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			-- Aggiorna il log per il movimento
			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		COMMIT TRANSACTION;

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
		THROW 50001, @returnMessage, 1;
	END

END;
GO
