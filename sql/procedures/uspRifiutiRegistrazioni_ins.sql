SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_ins]
	@IdSessione CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@IdModello CHAR(16) = NULL,
	@IdFormulario CHAR(16) = NULL,
	@IdCopia CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');
		SET @IdModello = NULLIF(LTRIM(RTRIM(@IdModello)), '');
		SET @IdFormulario = NULLIF(LTRIM(RTRIM(@IdFormulario)), '');
		SET @IdCopia = NULLIF(LTRIM(RTRIM(@IdCopia)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');

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

		DECLARE @idRegistroFinale CHAR(16);
		SELECT @idRegistroFinale = IdRegistro
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- @IdRegistro esplicito (Copia/incolla su un Registro diverso da quello corrente di sessione) sovrascrive il default
		IF @IdRegistro IS NOT NULL
			SET @idRegistroFinale = @IdRegistro;

		IF @idRegistroFinale IS NULL AND @IdFormulario IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il registro nel quale inserire la nuova registrazione';
			GOTO BRANCH_END;
		END

		IF @IdRegistro IS NOT NULL AND NOT EXISTS (
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

		IF @IdFormulario IS NOT NULL AND NOT EXISTS (SELECT 1
		FROM dbo.tblRifiutiFormulari
		WHERE
			Id = @IdFormulario
			AND Lock < 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Formulario non trovato';
			GOTO BRANCH_END;
		END

		IF @IdFormulario IS NOT NULL AND EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento
			WHERE
				f.Id = @IdFormulario
				AND r.Lock < 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Formulario già registrato';
			GOTO BRANCH_END;
		END

		IF @IdFormulario IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari f
				INNER JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE f.Id = @IdFormulario)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @IdFormulario IS NULL AND @IdModello IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @IdModello)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @IdFormulario IS NULL AND @IdCopia IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE
				r.Id = @IdCopia
				AND r.Lock < 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Lettura unica del modello (era ripetuta fino a 16 volte più sotto, una per ogni campo/EXISTS):
		-- valorizzata solo quando il ramo sottostante userà @IdModello, riusata da tutti i suoi INSERT
		DECLARE
			@mIdOperazione CHAR(1),
			@mOperazione CHAR(1),
			@mIdEer CHAR(6),
			@mIdStatoFisico CHAR(1),
			@mIdAttivita CHAR(2),
			@mIdUnitaMisura CHAR(2),
			@mIdProvenienza CHAR(1),
			@mUtenteNote VARCHAR(500),
			@mIdAutorizzazioneProduttoreDetentore CHAR(16),
			@mIdAutorizzazioneDestinatario CHAR(16),
			@mIdAutorizzazioneTrasportatore1 CHAR(16),
			@mIdAutorizzazioneTrasportatore2 CHAR(16),
			@mIdAutorizzazioneTrasportatore3 CHAR(16),
			@mIdTipoTrasporto1 CHAR(1),
			@mIdTipoTrasporto2 CHAR(1),
			@mIdTipoTrasporto3 CHAR(1),
			@mIdAutorizzazioneIntermediario1 CHAR(16),
			@mIdAutorizzazioneIntermediario2 CHAR(16),
			@mIdAutorizzazioneIntermediario3 CHAR(16),
			@mRegistrazioneNote VARCHAR(500),
			@mIdRaee CHAR(1),
			@mIdMateriale CHAR(2),
			@mMaterialeDescrizione VARCHAR(200),
			@mIdTrasportoTransfrontalieroTipo CHAR(1);

		IF @IdFormulario IS NULL AND @IdModello IS NOT NULL
			SELECT
				@mIdOperazione = m.IdOperazione,
				@mOperazione = o.Operazione,
				@mIdEer = m.IdEer,
				@mIdStatoFisico = m.IdStatoFisico,
				@mIdAttivita = m.IdAttivita,
				@mIdUnitaMisura = m.IdUnitaMisura,
				@mIdProvenienza = m.IdProvenienza,
				@mUtenteNote = m.UtenteNote,
				@mIdAutorizzazioneProduttoreDetentore = m.IdAutorizzazioneProduttoreDetentore,
				@mIdAutorizzazioneDestinatario = m.IdAutorizzazioneDestinatario,
				@mIdAutorizzazioneTrasportatore1 = m.IdAutorizzazioneTrasportatore1,
				@mIdAutorizzazioneTrasportatore2 = m.IdAutorizzazioneTrasportatore2,
				@mIdAutorizzazioneTrasportatore3 = m.IdAutorizzazioneTrasportatore3,
				@mIdTipoTrasporto1 = m.IdTipoTrasporto1,
				@mIdTipoTrasporto2 = m.IdTipoTrasporto2,
				@mIdTipoTrasporto3 = m.IdTipoTrasporto3,
				@mIdAutorizzazioneIntermediario1 = m.IdAutorizzazioneIntermediario1,
				@mIdAutorizzazioneIntermediario2 = m.IdAutorizzazioneIntermediario2,
				@mIdAutorizzazioneIntermediario3 = m.IdAutorizzazioneIntermediario3,
				@mRegistrazioneNote = m.RegistrazioneNote,
				@mIdRaee = m.IdRaee,
				@mIdMateriale = m.IdMateriale,
				@mMaterialeDescrizione = m.MaterialeDescrizione,
				@mIdTrasportoTransfrontalieroTipo = m.IdTrasportoTransfrontalieroTipo
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			WHERE m.Id = @IdModello;

		-- Lettura unica della registrazione sorgente per "Copia/incolla": stesso schema del blocco Modello sopra,
		-- ma dalla coppia Registrazione/Movimento esistente invece che da un Modello. Esclusi di proposito:
		-- Data, Numero, FormularioNumero (mai impostati anche negli altri rami di _ins), Esito/QuantitaVerificata/
		-- CausaleRespingimento*/QuantitaRespinta, DataFineTrasporto, VeicoloFuoriUso*, Quantita (dipende da
		-- relazioni/giacenze), Lock/DataStampa e le relazioni scarico/carico (tblRifiutiRegistrazioniRelazioni,
		-- mai copiate su richiesta esplicita).
		DECLARE
			@cIdMovimentoOrigine CHAR(16),
			@cIdOperazione CHAR(1),
			@cOperazione CHAR(1),
			@cIdEer CHAR(6),
			@cEerDescrizione VARCHAR(200),
			@cIdStatoFisico CHAR(1),
			@cIdAttivita CHAR(2),
			@cIdUnitaMisura CHAR(2),
			@cIdProvenienza CHAR(1),
			@cNote VARCHAR(500),
			@cIdAutorizzazioneProduttoreDetentore CHAR(16),
			@cIdAutorizzazioneDestinatario CHAR(16),
			@cIdAutorizzazioneTrasportatore1 CHAR(16),
			@cIdAutorizzazioneTrasportatore2 CHAR(16),
			@cIdAutorizzazioneTrasportatore3 CHAR(16),
			@cIdTipoTrasporto1 CHAR(1),
			@cIdTipoTrasporto2 CHAR(1),
			@cIdTipoTrasporto3 CHAR(1),
			@cIdAutorizzazioneIntermediario1 CHAR(16),
			@cIdAutorizzazioneIntermediario2 CHAR(16),
			@cIdAutorizzazioneIntermediario3 CHAR(16),
			@cRegistrazioneNote VARCHAR(500),
			@cIdRaee CHAR(1),
			@cIdMateriale CHAR(2),
			@cMaterialeDescrizione VARCHAR(200),
			@cIdAttivitaProvenienza CHAR(1),
			@cIdTrasportoTransfrontalieroTipo CHAR(1);

		IF @IdFormulario IS NULL AND @IdCopia IS NOT NULL
			SELECT
				@cIdMovimentoOrigine = m.Id,
				@cIdOperazione = m.IdOperazione,
				@cOperazione = r.Operazione,
				@cIdEer = m.IdEer,
				@cEerDescrizione = m.EerDescrizione,
				@cIdStatoFisico = m.IdStatoFisico,
				@cIdAttivita = m.IdAttivita,
				@cIdUnitaMisura = m.IdUnitaMisura,
				@cIdProvenienza = m.IdProvenienza,
				@cNote = m.Note,
				@cIdAutorizzazioneProduttoreDetentore = p.IdAutorizzazione,
				@cIdAutorizzazioneDestinatario = d.IdAutorizzazione,
				@cIdAutorizzazioneTrasportatore1 = t1.IdAutorizzazione,
				@cIdTipoTrasporto1 = t1.IdTipo,
				@cIdAutorizzazioneTrasportatore2 = t2.IdAutorizzazione,
				@cIdTipoTrasporto2 = t2.IdTipo,
				@cIdAutorizzazioneTrasportatore3 = t3.IdAutorizzazione,
				@cIdTipoTrasporto3 = t3.IdTipo,
				@cIdAutorizzazioneIntermediario1 = i1.IdAutorizzazione,
				@cIdAutorizzazioneIntermediario2 = i2.IdAutorizzazione,
				@cIdAutorizzazioneIntermediario3 = i3.IdAutorizzazione,
				@cRegistrazioneNote = r.Note,
				@cIdRaee = r.IdRaee,
				@cIdMateriale = r.IdMateriale,
				@cMaterialeDescrizione = r.MaterialeDescrizione,
				@cIdAttivitaProvenienza = r.IdAttivitaProvenienza,
				@cIdTrasportoTransfrontalieroTipo = r.IdTrasportoTransfrontalieroTipo
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				LEFT JOIN dbo.tblRifiutiMovimentiProduttori p ON m.Id = p.Id AND p.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiDestinatari d ON m.Id = d.Id AND d.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori t1 ON m.Id = t1.Id AND t1.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori t2 ON m.Id = t2.Id AND t2.Pos = 1
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori t3 ON m.Id = t3.Id AND t3.Pos = 2
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari i1 ON m.Id = i1.Id AND i1.Pos = 0
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari i2 ON m.Id = i2.Id AND i2.Pos = 1
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari i3 ON m.Id = i3.Id AND i3.Pos = 2
			WHERE r.Id = @IdCopia;

		DECLARE @idMovimento CHAR(16);

		-- uspId_get gestisce la propria transazione internamente: chiamate FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		IF @IdFormulario IS NULL
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;

		BEGIN TRANSACTION;

			IF @IdFormulario IS NULL
			BEGIN
				IF @IdOperazione IS NOT NULL
				BEGIN
					INSERT dbo.tblRifiutiMovimenti (Id, IdRegistro, IdOperazione)
					VALUES (@idMovimento, @idRegistroFinale, @IdOperazione);

					INSERT dbo.tblRifiutiRegistrazioni (Id, IdMovimento, Operazione, Lock)
					SELECT @returnId, @idMovimento, Operazione, 2
					FROM dbo.tblRifiutiOperazioni
					WHERE Id = @IdOperazione;
				END
				ELSE IF @IdModello IS NOT NULL
				BEGIN
					INSERT dbo.tblRifiutiMovimenti
						(Id, IdRegistro, IdOperazione, IdEer, IdStatoFisico, IdAttivita, IdUnitaMisura, IdProvenienza, Note)
					VALUES
						(@idMovimento, @idRegistroFinale, @mIdOperazione, @mIdEer, @mIdStatoFisico, @mIdAttivita, @mIdUnitaMisura, @mIdProvenienza, @mUtenteNote);

					IF @mIdAutorizzazioneProduttoreDetentore IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @mIdAutorizzazioneProduttoreDetentore, 0);

					IF @mIdAutorizzazioneDestinatario IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @mIdAutorizzazioneDestinatario, 0);

					IF @mIdAutorizzazioneTrasportatore1 IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
						VALUES (@idMovimento, @mIdAutorizzazioneTrasportatore1, @mIdTipoTrasporto1, 0);

					IF @mIdAutorizzazioneTrasportatore2 IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
						VALUES (@idMovimento, @mIdAutorizzazioneTrasportatore2, @mIdTipoTrasporto2, 1);

					IF @mIdAutorizzazioneTrasportatore3 IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
						VALUES (@idMovimento, @mIdAutorizzazioneTrasportatore3, @mIdTipoTrasporto3, 2);

					IF @mIdAutorizzazioneIntermediario1 IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @mIdAutorizzazioneIntermediario1, 0);

					IF @mIdAutorizzazioneIntermediario2 IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @mIdAutorizzazioneIntermediario2, 1);

					IF @mIdAutorizzazioneIntermediario3 IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @mIdAutorizzazioneIntermediario3, 2);

					IF EXISTS (SELECT 1
					FROM dbo.tblRifiutiModelliClassiPericolo
					WHERE Id = @IdModello)
						INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
						SELECT @idMovimento, IdClasse
						FROM dbo.tblRifiutiModelliClassiPericolo
						WHERE Id = @IdModello;

					INSERT dbo.tblRifiutiRegistrazioni
						(Id, IdMovimento, Operazione, Note, IdRaee, IdMateriale, MaterialeDescrizione, IdTrasportoTransfrontalieroTipo, Lock)
					VALUES
						(@returnId, @idMovimento, @mOperazione, @mRegistrazioneNote, @mIdRaee, @mIdMateriale, @mMaterialeDescrizione, @mIdTrasportoTransfrontalieroTipo, 2);

					IF EXISTS (SELECT 1
					FROM dbo.tblRifiutiModelliEtichette
					WHERE Id = @IdModello)
						INSERT dbo.tblRifiutiRegistrazioniEtichette (Id, IdEtichetta)
						SELECT @returnId, IdEtichetta
						FROM dbo.tblRifiutiModelliEtichette
						WHERE Id = @IdModello;
				END
				ELSE IF @IdCopia IS NOT NULL
				BEGIN
					INSERT dbo.tblRifiutiMovimenti
						(Id, IdRegistro, IdOperazione, IdEer, EerDescrizione, IdStatoFisico, IdAttivita, IdUnitaMisura, IdProvenienza, Note)
					VALUES
						(@idMovimento, @idRegistroFinale, @cIdOperazione, @cIdEer, @cEerDescrizione, @cIdStatoFisico, @cIdAttivita, @cIdUnitaMisura, @cIdProvenienza, @cNote);

					IF @cIdAutorizzazioneProduttoreDetentore IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @cIdAutorizzazioneProduttoreDetentore, 0);

					IF @cIdAutorizzazioneDestinatario IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @cIdAutorizzazioneDestinatario, 0);

					IF @cIdAutorizzazioneTrasportatore1 IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
						VALUES (@idMovimento, @cIdAutorizzazioneTrasportatore1, @cIdTipoTrasporto1, 0);

					IF @cIdAutorizzazioneTrasportatore2 IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
						VALUES (@idMovimento, @cIdAutorizzazioneTrasportatore2, @cIdTipoTrasporto2, 1);

					IF @cIdAutorizzazioneTrasportatore3 IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
						VALUES (@idMovimento, @cIdAutorizzazioneTrasportatore3, @cIdTipoTrasporto3, 2);

					IF @cIdAutorizzazioneIntermediario1 IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @cIdAutorizzazioneIntermediario1, 0);

					IF @cIdAutorizzazioneIntermediario2 IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @cIdAutorizzazioneIntermediario2, 1);

					IF @cIdAutorizzazioneIntermediario3 IS NOT NULL
						INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
						VALUES (@idMovimento, @cIdAutorizzazioneIntermediario3, 2);

					IF EXISTS (SELECT 1
					FROM dbo.tblRifiutiMovimentiClassiPericolo
					WHERE Id = @cIdMovimentoOrigine)
						INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
						SELECT @idMovimento, IdClasse
						FROM dbo.tblRifiutiMovimentiClassiPericolo
						WHERE Id = @cIdMovimentoOrigine;

					INSERT dbo.tblRifiutiRegistrazioni
						(Id, IdMovimento, Operazione, Note, IdRaee, IdMateriale, MaterialeDescrizione, IdAttivitaProvenienza, IdTrasportoTransfrontalieroTipo, Lock)
					VALUES
						(@returnId, @idMovimento, @cOperazione, @cRegistrazioneNote, @cIdRaee, @cIdMateriale, @cMaterialeDescrizione, @cIdAttivitaProvenienza, @cIdTrasportoTransfrontalieroTipo, 2);

					-- Nessuna copia delle relazioni scarico/carico (tblRifiutiRegistrazioniRelazioni): la nuova registrazione parte sempre senza relazioni
					INSERT dbo.tblRifiutiRegistrazioniEtichette (Id, IdEtichetta)
					SELECT @returnId, IdEtichetta
					FROM dbo.tblRifiutiRegistrazioniEtichette
					WHERE Id = @IdCopia;
				END
				ELSE
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'Parametro per Operazione, Modello o Copia non disponibile';
					GOTO BRANCH_END;
				END
			END
			ELSE
			BEGIN
				SELECT
					@idMovimento = f.IdMovimento,
					@IdOperazione = m.IdOperazione
				FROM
					dbo.tblRifiutiFormulari f
					LEFT JOIN dbo.tblRifiutiMovimenti m ON f.IdMovimento = m.Id
				WHERE f.Id = @IdFormulario;

				IF @idMovimento IS NULL
				BEGIN
					SET @returnValue = -1;
					SET @returnMessage = 'Movimento associato al formulario non trovato';
					GOTO BRANCH_END;
				END

				INSERT dbo.tblRifiutiRegistrazioni
					(Id, IdMovimento, Operazione, Lock)
				SELECT @returnId, @idMovimento, Operazione, 2
				FROM dbo.tblRifiutiOperazioni
				WHERE Id = @IdOperazione;
			END

		COMMIT TRANSACTION;

		SELECT @returnId AS Id;

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
