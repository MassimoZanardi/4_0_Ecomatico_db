/*
	Deploy produzione - 2026-08-30

	Contenuto (8 stored procedure, solo CREATE OR ALTER, nessuna modifica di
	schema/dati, idempotente - eseguibile piu' volte senza effetti collaterali):

	1) Copia/incolla Registrazioni/Formulari (nuova funzione applicativa)
	   - dbo.uspRifiutiRegistrazioni_ins: nuovi parametri @IdCopia/@IdRegistro,
	     nuovo ramo che copia i dati di una Registrazione esistente in una
	     nuova, con Registro di destinazione opzionale.
	   - dbo.uspRifiutiFormulari_ins: stesso pattern per i Formulari. Il ramo
	     Copia genera sempre un nuovo Movimento proprio e non referenzia mai
	     tblRifiutiRegistrazioni*, cosi' la Registrazione eventualmente
	     associata al formulario sorgente non viene mai creata/copiata.

	2) Fix gap FK modulo Rentri sulla cancellazione di Registri/Sedi
	   Le tabelle tblRentriRegistri (1:1 su tblRifiutiRegistri.Id) e
	   tblRentriCredenzialiSedi (giunzione su tblSedi.Id) sono state aggiunte
	   dopo l'ultimo aggiornamento di queste SP: cancellare un Registro o una
	   Sede con credenziali/registri RENTRI associati falliva per violazione
	   FK. Aggiunto sia il blocco esplicito sul soft-delete (Lock=0, coerente
	   con i blocchi gia' esistenti su Modelli/Registrazioni/Limiti) sia la
	   DELETE mancante sull'hard-delete di una bozza (Lock=2).
	   - dbo.uspRifiutiRegistri_del
	   - dbo.uspSedi_del_SediInterne
	   - dbo.uspSedi_del_SediEsterne

	3) Stesso fix sui tool di manutenzione dev-only (mai chiamati dall'app,
	   utility manuali per il reset dati in sviluppo), inclusi per coerenza
	   con le corrispondenti SP applicative sopra. Corretti anche un header
	   SET ANSI_NULLS/QUOTED_IDENTIFIER mancante (rischio di regressione sul
	   redeploy via sqlcmd, che compila QUOTED_IDENTIFIER OFF di default a
	   differenza di SSMS) e un bug di collation su CREATE TABLE #Sedi (senza
	   COLLATE esplicito eredita quella di tempdb, non convertita insieme al
	   DB - vedi conversione collation di agosto 2026).
	   - dbo.uspSYS_del_RegistroCascade
	   - dbo.uspSYS_del_SedeInternaCascade
	   - dbo.uspSYS_del_SedeEsternaCascade

	Verificato su DB dev: build pulita, verifica batch (ANSI_NULLS/QUOTED_IDENTIFIER/
	CRLF/XACT_ABORT) su tutte e 8, smoke test con sessione a basso privilegio,
	dry run transazionale (BEGIN TRAN + ROLLBACK) su dati reali per le SP di
	cancellazione - nessun errore, nessuna modifica persistita.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-08-30.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- 1) dbo.uspRifiutiRegistrazioni_ins
--------------------------------------------------------------------------------
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

GO

--------------------------------------------------------------------------------
-- 2) dbo.uspRifiutiFormulari_ins
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_ins]
	@IdSessione CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@IdModello CHAR(16) = NULL,
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
			@IdFunzione = 'RFR',
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

		IF @idRegistroFinale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il registro nel quale inserire il nuovo formulario';
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

		-- Titolarità sul modello
		IF @IdModello IS NOT NULL AND NOT EXISTS (
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

		-- Il modello deve generare un vero Formulario (FIR): se dichiara un documento di trasporto
		-- alternativo (es. Allegato VII/I-B per trasporto transfrontaliero), da questo modello non
		-- può essere creato un Formulario
		IF @IdModello IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiModelli m
			WHERE
				m.Id = @IdModello
				AND m.IdTrasportoTransfrontalieroTipo IS NOT NULL
				AND m.IdTrasportoTransfrontalieroTipo <> 'F')
		BEGIN
			SET @returnValue = -1;
			SELECT @returnMessage = 'Il modello utilizza "' + t.Nome + '" come documento di trasporto: non può essere usato per generare un formulario'
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiDocumentiTrasportiTipi t ON t.Id = m.IdTrasportoTransfrontalieroTipo
			WHERE m.Id = @IdModello;
			GOTO BRANCH_END;
		END

		-- Titolarità sul formulario sorgente (Copia/incolla)
		IF @IdCopia IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiFormulari r
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

		-- Lettura unica del modello (era ripetuta fino a 17 volte più sotto, una per ogni campo/EXISTS):
		-- valorizzata solo se @IdModello è specificato, riusata da tutti gli INSERT del ramo sottostante
		DECLARE
			@mIdOperazione CHAR(1),
			@mIdUnitaMisura CHAR(2),
			@mIdEer CHAR(6),
			@mIdStatoFisico CHAR(1),
			@mIdAttivita CHAR(2),
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
			@mIdImballo CHAR(2),
			@mAllaRinfusa BIT,
			@mIdAdr CHAR(2),
			@mTrasportoAdr BIT,
			@mNumeroOnu VARCHAR(20),
			@mAdrNote VARCHAR(200),
			@mIdAnalisiTipo CHAR(1),
			@mAnalisiNumero VARCHAR(50),
			@mAnalisiData DATE,
			@mLuogoDiProduzione BIT,
			@mDetentore BIT,
			@mFormularioNote VARCHAR(500);

		IF @IdModello IS NOT NULL
			SELECT
				@mIdOperazione = IdOperazione,
				@mIdUnitaMisura = IdUnitaMisura,
				@mIdEer = IdEer,
				@mIdStatoFisico = IdStatoFisico,
				@mIdAttivita = IdAttivita,
				@mIdProvenienza = IdProvenienza,
				@mUtenteNote = UtenteNote,
				@mIdAutorizzazioneProduttoreDetentore = IdAutorizzazioneProduttoreDetentore,
				@mIdAutorizzazioneDestinatario = IdAutorizzazioneDestinatario,
				@mIdAutorizzazioneTrasportatore1 = IdAutorizzazioneTrasportatore1,
				@mIdAutorizzazioneTrasportatore2 = IdAutorizzazioneTrasportatore2,
				@mIdAutorizzazioneTrasportatore3 = IdAutorizzazioneTrasportatore3,
				@mIdTipoTrasporto1 = IdTipoTrasporto1,
				@mIdTipoTrasporto2 = IdTipoTrasporto2,
				@mIdTipoTrasporto3 = IdTipoTrasporto3,
				@mIdAutorizzazioneIntermediario1 = IdAutorizzazioneIntermediario1,
				@mIdAutorizzazioneIntermediario2 = IdAutorizzazioneIntermediario2,
				@mIdAutorizzazioneIntermediario3 = IdAutorizzazioneIntermediario3,
				@mIdImballo = IdImballo,
				@mAllaRinfusa = AllaRinfusa,
				@mIdAdr = IdAdr,
				@mTrasportoAdr = TrasportoAdr,
				@mNumeroOnu = NumeroOnu,
				@mAdrNote = AdrNote,
				@mIdAnalisiTipo = IdAnalisiTipo,
				@mAnalisiNumero = AnalisiNumero,
				@mAnalisiData = AnalisiData,
				@mLuogoDiProduzione = LuogoDiProduzione,
				@mDetentore = Detentore,
				@mFormularioNote = FormularioNote
			FROM dbo.tblRifiutiModelli
			WHERE Id = @IdModello;

		-- Lettura unica del formulario sorgente per "Copia/incolla": stesso schema del blocco Modello sopra,
		-- ma dalla coppia Formulario/Movimento esistente invece che da un Modello. Esclusi di proposito:
		-- DataEmissione (analogo di "Data di registrazione"), VerificatoInPartenza (stato legato
		-- all'esecuzione fisica del trasporto), ColliNumero, FormularioNumero (su tblRifiutiMovimenti,
		-- mai impostato da _ins), le tabelle TrasportiFerroviari/Marittimi/Terresti (dati di esecuzione
		-- del trasporto reale) e, per costruzione, qualunque riferimento a tblRifiutiRegistrazioni*:
		-- la Registrazione eventualmente associata al formulario sorgente non deve mai essere copiata.
		DECLARE
			@cIdMovimentoOrigine CHAR(16),
			@cIdOperazione CHAR(1),
			@cIdUnitaMisura CHAR(2),
			@cIdEer CHAR(6),
			@cEerDescrizione VARCHAR(200),
			@cIdStatoFisico CHAR(1),
			@cIdAttivita CHAR(2),
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
			@cIdImballo CHAR(2),
			@cAllaRinfusa BIT,
			@cIdAdr CHAR(2),
			@cTrasportoAdr BIT,
			@cNumeroOnu VARCHAR(20),
			@cAdrNote VARCHAR(200),
			@cIdAnalisiTipo CHAR(1),
			@cAnalisiNumero VARCHAR(50),
			@cAnalisiData DATE,
			@cLuogoDiProduzione BIT,
			@cDetentore BIT,
			@cFormularioNote VARCHAR(500);

		IF @IdCopia IS NOT NULL
			SELECT
				@cIdMovimentoOrigine = m.Id,
				@cIdOperazione = m.IdOperazione,
				@cIdUnitaMisura = m.IdUnitaMisura,
				@cIdEer = m.IdEer,
				@cEerDescrizione = m.EerDescrizione,
				@cIdStatoFisico = m.IdStatoFisico,
				@cIdAttivita = m.IdAttivita,
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
				@cIdImballo = r.IdImballo,
				@cAllaRinfusa = r.AllaRinfusa,
				@cIdAdr = r.IdAdr,
				@cTrasportoAdr = r.TrasportoAdr,
				@cNumeroOnu = r.NumeroOnu,
				@cAdrNote = r.AdrNote,
				@cIdAnalisiTipo = r.IdAnalisiTipo,
				@cAnalisiNumero = r.AnalisiNumero,
				@cAnalisiData = r.AnalisiData,
				@cLuogoDiProduzione = r.LuogoDiProduzione,
				@cDetentore = r.Detentore,
				@cFormularioNote = r.Note
			FROM
				dbo.tblRifiutiFormulari r
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

		-- uspId_get gestisce la propria transazione internamente: chiamata FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		DECLARE @idMovimento CHAR(16);
		-- Genera l'Id del movimento FUORI dalla transazione: usato in tutti i rami IF/ELSE IF
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;

		BEGIN TRANSACTION;

			IF @IdOperazione IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimenti
					(Id, IdRegistro, IdOperazione)
				VALUES
					(@idMovimento, @idRegistroFinale, @IdOperazione);

				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, Lock)
				VALUES
					(@returnId, @idMovimento, 2);
			END
			ELSE IF @IdModello IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimenti
					(Id, IdRegistro, IdOperazione, IdUnitaMisura, IdEer, IdStatoFisico, IdAttivita, IdProvenienza, Note)
				VALUES
					(@idMovimento, @idRegistroFinale, @mIdOperazione, @mIdUnitaMisura, @mIdEer, @mIdStatoFisico, @mIdAttivita, @mIdProvenienza, @mUtenteNote);

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

				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, IdImballo, AllaRinfusa, IdAdr, TrasportoAdr, NumeroOnu, AdrNote, IdAnalisiTipo, AnalisiNumero, AnalisiData, LuogoDiProduzione, Detentore, Note, Lock)
				VALUES
					(@returnId, @idMovimento, @mIdImballo, @mAllaRinfusa, @mIdAdr, @mTrasportoAdr, @mNumeroOnu, @mAdrNote, @mIdAnalisiTipo, @mAnalisiNumero, @mAnalisiData, @mLuogoDiProduzione, @mDetentore, @mFormularioNote, 2);

				IF EXISTS (SELECT 1
				FROM dbo.tblRifiutiModelliEtichette
				WHERE Id = @IdModello)
					INSERT dbo.tblRifiutiFormulariEtichette (Id, IdEtichetta)
					SELECT @returnId, IdEtichetta
					FROM dbo.tblRifiutiModelliEtichette
					WHERE Id = @IdModello;
			END
			ELSE IF @IdCopia IS NOT NULL
			BEGIN
				INSERT dbo.tblRifiutiMovimenti
					(Id, IdRegistro, IdOperazione, IdUnitaMisura, IdEer, EerDescrizione, IdStatoFisico, IdAttivita, IdProvenienza, Note)
				VALUES
					(@idMovimento, @idRegistroFinale, @cIdOperazione, @cIdUnitaMisura, @cIdEer, @cEerDescrizione, @cIdStatoFisico, @cIdAttivita, @cIdProvenienza, @cNote);

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

				INSERT dbo.tblRifiutiFormulari
					(Id, IdMovimento, IdImballo, AllaRinfusa, IdAdr, TrasportoAdr, NumeroOnu, AdrNote, IdAnalisiTipo, AnalisiNumero, AnalisiData, LuogoDiProduzione, Detentore, Note, Lock)
				VALUES
					(@returnId, @idMovimento, @cIdImballo, @cAllaRinfusa, @cIdAdr, @cTrasportoAdr, @cNumeroOnu, @cAdrNote, @cIdAnalisiTipo, @cAnalisiNumero, @cAnalisiData, @cLuogoDiProduzione, @cDetentore, @cFormularioNote, 2);

				-- Nessuna copia delle tabelle Trasporti Ferroviari/Marittimi/Terresti (dati di esecuzione del
				-- trasporto reale) né di tblRifiutiRegistrazioni*: la Registrazione eventualmente associata al
				-- formulario sorgente non viene mai creata/copiata.
				INSERT dbo.tblRifiutiFormulariEtichette (Id, IdEtichetta)
				SELECT @returnId, IdEtichetta
				FROM dbo.tblRifiutiFormulariEtichette
				WHERE Id = @IdCopia;
			END
			ELSE
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Parametro per Operazione, Modello o Copia non disponibile';
				GOTO BRANCH_END;
			END

		COMMIT TRANSACTION;

		SELECT Id = @returnId;

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

GO

--------------------------------------------------------------------------------
-- 3) dbo.uspRifiutiRegistri_del
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistri_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
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
			@IdFunzione = 'RRT',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: verifica prima di tutto se il registro esiste, indipendentemente dalla
		-- titolarità sottostante — mai esistito o già cancellato (es. doppio invio della
		-- richiesta di annullamento lato UI) viene trattato come cancellazione già avvenuta con
		-- successo, non come errore.
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRifiutiRegistri
		WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblRifiutiRegistri
		WHERE Id = @Id);

		-- ── CASO 1: registro attivo (Lock = 0) → soft delete ─────────────────
		IF @lock = 0
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti m
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON m.Id = r.IdMovimento
				WHERE
					m.IdRegistro = @Id
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un registro che ha registrazioni associate non può essere cancellato';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti m
				INNER JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
				WHERE
					m.IdRegistro = @Id
					AND f.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un registro che ha formulari associati non può essere cancellato';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiModelli
				WHERE
					IdRegistro = @Id
					AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un registro che ha modelli associati non può essere cancellato';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiLimiti
			WHERE
				IdRegistro = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un registro con limiti rifiuti associati non può essere cancellato';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRentriRegistri
			WHERE Id = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un registro associato/registrato su RENTRI non può essere cancellato';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblRifiutiRegistri
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Registro non trovato o già eliminato';
					GOTO BRANCH_END;
				END

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END

		-- ── CASO 2: registro in bozza (Lock = 2) → hard delete ───────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				-- Gestione EoW: la configurazione dell'automatismo per questo registro
				-- (tblEoWMaterialiRegistri.IdRegistro) va rimossa prima del registro stesso.
				DELETE dbo.tblEoWMaterialiRegistri
				WHERE IdRegistro = @Id;

				-- tblRifiutiLimiti.IdRegistro è nullable e il Limite appartiene alla Sede (non al
				-- Registro): un Limite scoped a questo registro perde solo lo scoping specifico,
				-- torna a valere sull'intera sede. Ramo di fatto irraggiungibile in pratica (il
				-- picker dei Registri di uspRifiutiLimiti_get_Registri_SelectList espone solo
				-- registri Lock=0, mai in bozza), mantenuto per difesa dalla FK NO_ACTION.
				UPDATE dbo.tblRifiutiLimiti
				SET IdRegistro = NULL
				WHERE IdRegistro = @Id;

				-- tblRentriRegistri è 1:1 a chiave condivisa (Id NOT NULL, nessun ON DELETE CASCADE):
				-- va rimosso prima, altrimenti la DELETE sottostante fallisce per violazione FK.
				-- Ramo di fatto irraggiungibile in pratica (il blocco sopra su Lock=0 impedisce di
				-- arrivare in bozza già registrata su RENTRI), mantenuto per difesa.
				DELETE dbo.tblRentriRegistri
				WHERE Id = @Id;

				DELETE dbo.tblRifiutiRegistri
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: Lock in stato non gestito ────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

		END

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
-- 4) dbo.uspSedi_del_SediInterne
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspSedi_del_SediInterne]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
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
			@IdFunzione = 'AZI',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblSedi
		WHERE Id = @Id);

		IF @lock IS NULL
		BEGIN
			-- Idempotenza: sede mai esistita o già cancellata (es. doppio invio della richiesta
			-- di annullamento lato UI) — trattata come cancellazione già avvenuta con successo,
			-- non come errore.
			SET @returnValue = 0;
		END
		ELSE IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblSedi
			WHERE
				IdParent = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede non può essere cancellata se contiene altre sedi';
				GOTO BRANCH_END;
			END

			-- Titolarità: Admin dello stesso Dominio della sede, oppure Admin di un Dominio Master.
			-- Il bypass Master è intenzionale (confermato dall'utente): un Master-admin deve poter
			-- cancellare/modificare aziende interne di qualsiasi dominio, non solo del proprio.
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi s
				INNER JOIN dbo.tblSediInterne i ON ISNULL(s.IdParent, s.Id) = i.Id
				INNER JOIN dbo.tblUtenti a ON i.IdDominio = a.IdDominio
				INNER JOIN dbo.tblSessioni e ON a.Id = e.IdUtente
				WHERE
					s.Id = @Id
					AND e.Id = @IdSessione
					AND a.IdRuolo = 'AD'
					AND a.Lock = 0
			)
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblSessioni e
				INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
				INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
				WHERE
					e.Id = @IdSessione
					AND ut.IdRuolo = 'AD'
					AND ut.Lock = 0
					AND d.[Master] = 1
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblSediEsterne e INNER JOIN dbo.tblSedi s ON e.Id = s.Id
			WHERE
				e.IdSedeInterna = @Id
				AND s.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''azienda con soggetti associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblOggetti
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con oggetti associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblPersone
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con persone associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblCalendari
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con calendari associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblMagazzini
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con magazzini associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Gestione EoW: stesso controllo del magazzino tradizionale, sui magazzini EoW propri della sede
			IF EXISTS (SELECT 1
			FROM dbo.tblEoWMagazzini
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con magazzini EoW associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiRegistri
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con registri c/s rifiuti associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblEtichette
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con etichette associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblTipi
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con tipi di scadenze/servizi associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblAreeSediInterne ai
				INNER JOIN dbo.tblAree a ON ai.Id = a.Id
				WHERE
					ai.IdSede = @Id
					AND a.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un''area non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiAutorizzazioni
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con autorizzazioni rifiuti associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiLimiti
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con limiti rifiuti associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRentriRegistri rr
				INNER JOIN dbo.tblRifiutiRegistri r ON rr.Id = r.Id
				WHERE r.IdSede = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con registri RENTRI associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRentriCredenzialiSedi
			WHERE IdSede = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con credenziali RENTRI associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblSedi
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END
		ELSE IF @lock = 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				DELETE dbo.tblUtentiSediInterne
				WHERE IdSede = @Id;
				DELETE dbo.tblAreeSediInterne
				WHERE IdSede = @Id;
				DELETE dbo.tblCalendari
				WHERE IdSede = @Id;
				DELETE dbo.tblEtichette
				WHERE IdSede = @Id;
				DELETE dbo.tblMagazzini
				WHERE IdSede = @Id;

				-- Gestione EoW: magazzini/lotti/movimenti EoW di proprietà esclusiva della sede, e
				-- le configurazioni MaterialiRegistri legate ai lotti o ai registri in cancellazione
				-- (stesso ordine/logica di uspSYS_del_SedeInternaCascade).
				DELETE r
				FROM dbo.tblEoWMovimentiRelazioni r
				INNER JOIN dbo.tblEoWMovimenti m ON r.Id = m.Id OR r.IdParent = m.Id
				INNER JOIN dbo.tblEoWLotti l ON m.IdLotto = l.Id
				INNER JOIN dbo.tblEoWMagazzini g ON l.IdMagazzino = g.Id
				WHERE g.IdSede = @Id;

				DELETE m
				FROM dbo.tblEoWMovimenti m
				INNER JOIN dbo.tblEoWLotti l ON m.IdLotto = l.Id
				INNER JOIN dbo.tblEoWMagazzini g ON l.IdMagazzino = g.Id
				WHERE g.IdSede = @Id;

				DELETE mr
				FROM dbo.tblEoWMaterialiRegistri mr
				WHERE
					mr.IdLotto IN (SELECT l.Id FROM dbo.tblEoWLotti l INNER JOIN dbo.tblEoWMagazzini g ON l.IdMagazzino = g.Id WHERE g.IdSede = @Id)
					OR mr.IdRegistro IN (SELECT Id FROM dbo.tblRifiutiRegistri WHERE IdSede = @Id);

				DELETE l
				FROM dbo.tblEoWLotti l
				INNER JOIN dbo.tblEoWMagazzini g ON l.IdMagazzino = g.Id
				WHERE g.IdSede = @Id;

				DELETE dbo.tblEoWMagazzini
				WHERE IdSede = @Id;

				DELETE dbo.tblRifiutiAutorizzazioni
				WHERE IdSede = @Id;

				-- tblRifiutiLimiti* va rimosso prima di tblRifiutiRegistri: FK NO_ACTION su IdRegistro
				-- bloccherebbe altrimenti la cancellazione del registro sottostante.
				DELETE dbo.tblRifiutiLimitiEer
				WHERE IdLimite IN (SELECT Id FROM dbo.tblRifiutiLimiti WHERE IdSede = @Id);
				DELETE dbo.tblRifiutiLimitiEtichette
				WHERE IdLimite IN (SELECT Id FROM dbo.tblRifiutiLimiti WHERE IdSede = @Id);
				DELETE dbo.tblRifiutiLimitiOperazioni
				WHERE IdLimite IN (SELECT Id FROM dbo.tblRifiutiLimiti WHERE IdSede = @Id);
				DELETE dbo.tblRifiutiLimiti
				WHERE IdSede = @Id;

				-- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL,
				-- nessun ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante
				-- fallisce per FK. Ramo di fatto irraggiungibile in pratica (il blocco sopra su
				-- Lock=0 impedisce di arrivare in bozza con registri RENTRI già associati).
				DELETE dbo.tblRentriRegistri
				WHERE Id IN (SELECT Id FROM dbo.tblRifiutiRegistri WHERE IdSede = @Id);

				DELETE dbo.tblRifiutiRegistri
				WHERE IdSede = @Id;
				DELETE dbo.tblTipi
				WHERE IdSede = @Id;
				DELETE dbo.tblOggetti
				WHERE IdSede = @Id;
				DELETE dbo.tblPersone
				WHERE IdSede = @Id;
				DELETE dbo.tblSediEsterne
				WHERE IdSedeInterna = @Id;

				-- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL
				-- (nessuna colonna da azzerare) - si cancella la riga di associazione, mai
				-- tblRentriCredenziali stessa. Ramo di fatto irraggiungibile in pratica (blocco
				-- sopra su Lock=0), mantenuto per difesa dalla FK NO_ACTION.
				DELETE dbo.tblRentriCredenzialiSedi
				WHERE IdSede = @Id;

				DELETE dbo.tblSediInterne
				WHERE Id = @Id;
				DELETE dbo.tblSedi
				WHERE Id = @Id;
				DELETE dbo.tblOsepe
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

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
		THROW 50001, @returnMessage, 1
	END

END;

GO

--------------------------------------------------------------------------------
-- 5) dbo.uspSedi_del_SediEsterne
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspSedi_del_SediEsterne]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
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
			@IdFunzione = 'ANS',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblSedi
		WHERE Id = @Id);

		IF @lock IS NULL
		BEGIN
			-- Idempotenza: sede mai esistita o già cancellata (es. doppio invio della richiesta
			-- di annullamento lato UI, senza protezione anti-doppio-submit sul pulsante) — la
			-- si tratta come cancellazione già avvenuta con successo, non come errore: lo stato
			-- desiderato ("questa sede non esiste") è già raggiunto.
			SET @returnValue = 0;
		END
		ELSE IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblSedi
			WHERE
				IdParent = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede non può essere cancellata se contiene altre sedi';
				GOTO BRANCH_END;
			END

			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi s
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
				WHERE
					s.Id = @Id
					AND e.Id = @IdSessione
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede condivisa da altre aziende non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblAreeOsepe ao
				INNER JOIN dbo.tblAree a ON ao.Id = a.Id
				WHERE
					ao.IdOsepe = @Id
					AND a.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un''area non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiAutorizzazioni
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un''autorizzazione rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRentriCredenzialiSedi
			WHERE IdSede = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con credenziali RENTRI associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblSedi
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END
		ELSE IF @lock = 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				DELETE dbo.tblAreeOsepe
				WHERE IdOsepe = @Id;

				-- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL. In
				-- pratica non popolata per una sede esterna (blocco sopra su Lock=0 comunque già la
				-- impedisce), mantenuta per difesa dalla FK NO_ACTION.
				DELETE dbo.tblRentriCredenzialiSedi
				WHERE IdSede = @Id;

				DELETE dbo.tblSediEsterne
				WHERE Id = @Id;
				DELETE dbo.tblSedi
				WHERE Id = @Id;
				DELETE dbo.tblOsepe
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

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
		THROW 50001, @returnMessage, 1
	END

END;

GO

--------------------------------------------------------------------------------
-- 6) dbo.uspSYS_del_RegistroCascade
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_RegistroCascade
    @IdRegistro CHAR(16)    = NULL,
    @Conferma   VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
        SET @Conferma   = NULLIF(LTRIM(RTRIM(@Conferma)),   '');

        IF @IdRegistro IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistri WHERE Id = @IdRegistro)
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il registro indicato non esiste';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui). A differenza di
        -- una sede, un registro non possiede etichette/autorizzazioni proprie (sono risorse della
        -- sede, non del registro): non vengono quindi mai toccate da questa SP, solo scollegate
        -- dalle proprie righe di giunzione (che appartengono ai record cancellati, non alla
        -- risorsa condivisa).
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro = @IdRegistro;
        SELECT Id INTO #RifiutiMovimenti FROM dbo.tblRifiutiMovimenti WHERE IdRegistro = @IdRegistro;
        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            DELETE FROM dbo.tblRifiutiFormulariEtichette           WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi  WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Gestione EoW: il registro non ha magazzini/lotti propri, ma le sue Registrazioni
            -- possono essere referenziate da tblEoWMovimenti.IdRegistrazione (nullable - si azzera
            -- anziché cancellare il movimento, che resta un record di magazzino valido anche senza
            -- la registrazione di origine) e la sua chiave da tblEoWMaterialiRegistri (configurazione
            -- dell'automatismo per questo registro, va rimossa insieme al registro).
            UPDATE dbo.tblEoWMovimenti SET IdRegistrazione = NULL WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblEoWMaterialiRegistri WHERE IdRegistro = @IdRegistro;

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRifiutiRegistrazioniRelazioni.IdParent è NOT NULL: una registrazione di un ALTRO
            -- registro (non in cancellazione) può avere come genitore una registrazione di questo
            -- registro. Non essendo azzerabile, la riga di relazione va cancellata anche quando
            -- appartiene a quell'altra registrazione - perde il collegamento e la relativa
            -- Quantita/Pos. Stessa logica "UPDATE=NULL dove possibile, DELETE dove NOT NULL"
            -- applicata alle risorse condivise di uspSYS_del_SedeInternaCascade.
            DECLARE @relazioniEsterneRimosse INT = (
                SELECT COUNT(*) FROM dbo.tblRifiutiRegistrazioniRelazioni
                WHERE IdParent IN (SELECT Id FROM #RifiutiRegistrazioni)
                  AND Id NOT IN (SELECT Id FROM #RifiutiRegistrazioni)
            );
            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRifiutiLimiti.IdRegistro è nullable e il Limite appartiene alla Sede (non al
            -- Registro, non toccato da questa SP): cancellando solo il Registro il Limite resta
            -- valido, perde solo lo scoping specifico al registro (torna a valere sull'intera sede).
            DECLARE @limitiScollegati INT;
            UPDATE dbo.tblRifiutiLimiti SET IdRegistro = NULL WHERE IdRegistro = @IdRegistro;
            SET @limitiScollegati = @@ROWCOUNT;

            -- tblRentriRegistri è 1:1 a chiave condivisa (Id NOT NULL, nessun ON DELETE CASCADE):
            -- va rimosso prima, altrimenti la DELETE sottostante fallisce per violazione FK.
            DELETE FROM dbo.tblRentriRegistri WHERE Id = @IdRegistro;

            DELETE FROM dbo.tblRifiutiRegistri WHERE Id = @IdRegistro;

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT @IdRegistro
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT(
            'Cancellazione completata. Movimenti rimossi: ', (SELECT COUNT(*) FROM #RifiutiMovimenti),
            ', Modelli rimossi: ', (SELECT COUNT(*) FROM #RifiutiModelli),
            ', Formulari rimossi: ', (SELECT COUNT(*) FROM #RifiutiFormulari),
            ', Registrazioni rimosse: ', (SELECT COUNT(*) FROM #RifiutiRegistrazioni),
            '. Relazioni di altre registrazioni scollegate: ', @relazioniEsterneRimosse,
            '. Limiti rifiuti scollegati dal registro: ', @limitiScollegati, '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
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
-- 7) dbo.uspSYS_del_SedeInternaCascade
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_SedeInternaCascade
    @IdSede   CHAR(16)    = NULL,
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSede   = NULLIF(LTRIM(RTRIM(@IdSede)),   '');
        SET @Conferma = NULLIF(LTRIM(RTRIM(@Conferma)), '');

        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @IdSede AND InternaEsterna = 'I')
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La sede indicata non esiste o non è una sede interna';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- Sede di partenza + tutte le sotto-sedi collegate (tblSedi.IdParent, tblSedi.IdAziendaInterna,
        -- tblSediEsterne.IdSedeInterna), a qualunque profondità. Ciclo con deduplica esplicita anziché
        -- CTE ricorsiva: le tre relazioni unite possono formare cicli sui dati reali, e una CTE
        -- ricorsiva pura non deduplica tra un livello e l'altro, rischiando MAXRECURSION anche in
        -- assenza di un vero ciclo logico.
        -- COLLATE DATABASE_DEFAULT esplicito: senza, la colonna erediterebbe la collation di tempdb
        -- (non convertita insieme al DB, vedi project_collation_conversion), in conflitto con le
        -- colonne CHAR(16) del database nei confronti/JOIN sottostanti.
        CREATE TABLE #Sedi (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
        INSERT INTO #Sedi (Id) VALUES (@IdSede);

        DECLARE @nuoveRighe INT = 1;
        WHILE @nuoveRighe > 0
        BEGIN
            INSERT INTO #Sedi (Id)
            SELECT DISTINCT x.Id
            FROM (
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdParent = c.Id
                UNION
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdAziendaInterna = c.Id
                UNION
                SELECT se.Id FROM dbo.tblSediEsterne se INNER JOIN #Sedi c ON se.IdSedeInterna = c.Id
            ) x
            WHERE NOT EXISTS (SELECT 1 FROM #Sedi t WHERE t.Id = x.Id);

            SET @nuoveRighe = @@ROWCOUNT;
        END

        DECLARE @totaleSedi INT = (SELECT COUNT(*) FROM #Sedi);

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui)
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #Etichette FROM dbo.tblEtichette WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Calendari FROM dbo.tblCalendari WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Eventi FROM dbo.tblEventi WHERE IdCalendario IN (SELECT Id FROM #Calendari);
        SELECT Id INTO #Tipi FROM dbo.tblTipi WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #TipiProprieta FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #Tipi);
        SELECT Id INTO #Persone FROM dbo.tblPersone WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Oggetti FROM dbo.tblOggetti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Magazzini FROM dbo.tblMagazzini WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Gestione EoW: magazzini specifici EoW di proprietà della sede (solo sedi interne), con
        -- i rispettivi lotti e movimenti - vedi project_eow_module_design in memoria persistente.
        SELECT Id INTO #EoWMagazzini FROM dbo.tblEoWMagazzini WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #EoWLotti FROM dbo.tblEoWLotti WHERE IdMagazzino IN (SELECT Id FROM #EoWMagazzini);
        SELECT Id INTO #EoWMovimenti FROM dbo.tblEoWMovimenti WHERE IdLotto IN (SELECT Id FROM #EoWLotti);

        -- tblSedi/tblPersone/tblOggetti sono sottotipi a chiave condivisa di tblOsepe (stesso Id)
        SELECT Id INTO #OsepeIds FROM (
            SELECT Id FROM #Sedi
            UNION
            SELECT Id FROM #Persone
            UNION
            SELECT Id FROM #Oggetti
        ) x;

        SELECT Id INTO #RifiutiRegistri FROM dbo.tblRifiutiRegistri WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiAutorizzazioni FROM dbo.tblRifiutiAutorizzazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblRifiutiLimiti.IdSede è NOT NULL (proprietà della sede) e IdRegistro è nullable (scoping
        -- opzionale a un registro specifico della stessa sede) - entrambi i rami coperti per sicurezza.
        SELECT Id INTO #RifiutiLimiti FROM dbo.tblRifiutiLimiti
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiMovimenti
        FROM dbo.tblRifiutiMovimenti
        WHERE IdSedeProduttoreDetentore IN (SELECT Id FROM #Sedi)
           OR IdSedeDestinatario        IN (SELECT Id FROM #Sedi)
           OR IdSedeTrasportatore1      IN (SELECT Id FROM #Sedi)
           OR IdSedeIntermediario1      IN (SELECT Id FROM #Sedi)
           OR IdRegistro                IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        SELECT Id INTO #Scadenze
        FROM dbo.tblScadenze
        WHERE IdEvento IN (SELECT Id FROM #Eventi)
           OR IdTipo   IN (SELECT Id FROM #Tipi);

        SELECT Id INTO #Servizi
        FROM dbo.tblServizi
        WHERE IdEvento      IN (SELECT Id FROM #Eventi)
           OR IdRichiedente IN (SELECT Id FROM #Sedi)
           OR IdTipo        IN (SELECT Id FROM #Tipi);

        -- tblAreeSediInterne/tblAreeOsepe/tblUtentiSediInterne sono giunzioni a chiave composita
        -- verso risorse condivise a livello di Dominio (tblAree, tblUtenti), non di proprietà della
        -- sede: si cancellano solo le righe di giunzione, mai tblAree/tblUtenti stesse.
        SELECT Id, IdSede  INTO #AreeSediInterne FROM dbo.tblAreeSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id, IdOsepe INTO #AreeOsepe       FROM dbo.tblAreeOsepe       WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            DELETE FROM dbo.tblRifiutiAutorizzazioniAttivita         WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniConducenti       WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniEer              WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTarghe           WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            DELETE FROM dbo.tblRifiutiFormulariEtichette             WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti     WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                      WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Gestione EoW: va fatta prima di cancellare Registrazioni/Registri sottostanti, per
            -- rispettare le FK di tblEoWMovimenti.IdRegistrazione e tblEoWMaterialiRegistri.IdRegistro/
            -- IdLotto. I movimenti/lotti/magazzini EoW di questa sede vengono cancellati per intero
            -- (non azzerati) perché sono risorse di proprietà esclusiva della sede stessa, non
            -- condivise con altre sedi.
            DELETE FROM dbo.tblEoWMovimentiRelazioni
            WHERE Id       IN (SELECT Id FROM #EoWMovimenti)
               OR IdParent IN (SELECT Id FROM #EoWMovimenti);
            DELETE FROM dbo.tblEoWMovimenti WHERE Id IN (SELECT Id FROM #EoWMovimenti);
            DELETE FROM dbo.tblEoWMaterialiRegistri
            WHERE IdLotto    IN (SELECT Id FROM #EoWLotti)
               OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblEoWLotti     WHERE Id IN (SELECT Id FROM #EoWLotti);
            DELETE FROM dbo.tblEoWMagazzini WHERE Id IN (SELECT Id FROM #EoWMagazzini);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRifiutiLimiti* va rimosso prima di tblRifiutiRegistri: FK NO_ACTION su IdRegistro
            -- bloccherebbe altrimenti la cancellazione del registro sottostante.
            DELETE FROM dbo.tblRifiutiLimitiEer        WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiEtichette  WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiOperazioni WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimiti           WHERE Id IN (SELECT Id FROM #RifiutiLimiti);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL, nessun
            -- ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante fallisce per FK.
            DELETE FROM dbo.tblRentriRegistri  WHERE Id IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblRifiutiRegistri WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            DELETE FROM dbo.tblScadenzeOsepe
            WHERE Id      IN (SELECT Id FROM #Scadenze)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblScadenze WHERE Id IN (SELECT Id FROM #Scadenze);

            DELETE FROM dbo.tblServiziOsepe
            WHERE Id      IN (SELECT Id FROM #Servizi)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblServizi WHERE Id IN (SELECT Id FROM #Servizi);

            DELETE FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipi          WHERE Id IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblEventiFirme      WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiProprieta  WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiUtenti     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenzeEccezioni
            WHERE Id       IN (SELECT Id FROM #Eventi)
               OR IdEvento IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenze WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventi     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblCalendari  WHERE Id IN (SELECT Id FROM #Calendari);

            -- Risorse riutilizzabili di proprietà della sede: prima di cancellarle si liberano da
            -- eventuali riferimenti di ALTRE sedi non coinvolte nella cascata. Dove la colonna è
            -- nullable si azzera il riferimento (la riga esterna resta, perde solo il collegamento);
            -- dove è NOT NULL non è possibile azzerarla, quindi si cancella la riga di giunzione
            -- esterna stessa. Scelta esplicita dell'utente: tocca dati di altre sedi pur di
            -- garantire che Etichette/Autorizzazioni di questa sede vengano sempre rimosse.
            DECLARE @rifEsterniRimossi INT = 0;

            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneDestinatario = NULL         WHERE IdAutorizzazioneDestinatario         IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneIntermediario1 = NULL       WHERE IdAutorizzazioneIntermediario1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneProduttoreDetentore = NULL  WHERE IdAutorizzazioneProduttoreDetentore  IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore1 = NULL       WHERE IdAutorizzazioneTrasportatore1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiMovimentiDestinatari   WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari  WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiProduttori    WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiFormulariEtichette     WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblEtichette             WHERE Id IN (SELECT Id FROM #Etichette);
            DELETE FROM dbo.tblRifiutiAutorizzazioni WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblPersoneRuoli WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblPersone      WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblOggetti      WHERE Id IN (SELECT Id FROM #Oggetti);
            DELETE FROM dbo.tblMagazzini    WHERE Id IN (SELECT Id FROM #Magazzini);

            -- Giunzioni a chiave composita verso risorse condivise (tblAree/tblUtenti non toccate)
            DELETE asi FROM dbo.tblAreeSediInterne asi INNER JOIN #AreeSediInterne t ON t.Id = asi.Id AND t.IdSede  = asi.IdSede;
            DELETE ao  FROM dbo.tblAreeOsepe       ao  INNER JOIN #AreeOsepe       t ON t.Id = ao.Id  AND t.IdOsepe = ao.IdOsepe;
            DELETE FROM dbo.tblUtentiSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL (nessuna
            -- colonna da azzerare) - si cancella la riga di associazione, mai tblRentriCredenziali stessa.
            DELETE FROM dbo.tblRentriCredenzialiSedi WHERE IdSede IN (SELECT Id FROM #Sedi);

            DELETE FROM dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediRecapiti  WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediEsterne   WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediInterne   WHERE Id IN (SELECT Id FROM #Sedi);

            -- Radice e sotto-sedi cancellate in un'unica istruzione set-based: i vincoli
            -- auto-referenziati IdParent/IdAziendaInterna sono verificati a fine istruzione (non
            -- riga per riga), quindi non si bloccano a vicenda anche su gerarchie a più livelli.
            DELETE FROM dbo.tblSedi WHERE Id IN (SELECT Id FROM #Sedi);

            -- tblOsepe: supertipo condiviso di Sedi/Persone/Oggetti, cancellato per ultimo
            DELETE FROM dbo.tblOsepe WHERE Id IN (SELECT Id FROM #OsepeIds);

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get), solo per le entità con Id
            -- proprio (non per le tabelle a chiave condivisa/giunzione, già coperte a monte)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #OsepeIds
                UNION SELECT Id FROM #Calendari
                UNION SELECT Id FROM #Etichette
                UNION SELECT Id FROM #Eventi
                UNION SELECT Id FROM #Magazzini
                UNION SELECT Id FROM #EoWMagazzini
                UNION SELECT Id FROM #EoWLotti
                UNION SELECT Id FROM #EoWMovimenti
                UNION SELECT Id FROM #RifiutiAutorizzazioni
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiRegistri
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT Id FROM #RifiutiLimiti
                UNION SELECT Id FROM #Scadenze
                UNION SELECT Id FROM #Servizi
                UNION SELECT Id FROM #Tipi
                UNION SELECT Id FROM #TipiProprieta
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT('Cancellazione completata. Sedi rimosse: ', @totaleSedi, '. Riferimenti esterni azzerati/rimossi su Etichette/Autorizzazioni condivise: ', @rifEsterniRimossi, '. Movimenti EoW rimossi: ', (SELECT COUNT(*) FROM #EoWMovimenti), ', Lotti EoW rimossi: ', (SELECT COUNT(*) FROM #EoWLotti), ', Magazzini EoW rimossi: ', (SELECT COUNT(*) FROM #EoWMagazzini), ', Limiti rifiuti rimossi: ', (SELECT COUNT(*) FROM #RifiutiLimiti), '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
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
-- 8) dbo.uspSYS_del_SedeEsternaCascade
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_SedeEsternaCascade
    @IdSede   CHAR(16)    = NULL,
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSede   = NULLIF(LTRIM(RTRIM(@IdSede)),   '');
        SET @Conferma = NULLIF(LTRIM(RTRIM(@Conferma)), '');

        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @IdSede AND InternaEsterna = 'E')
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La sede indicata non esiste o non è una sede esterna';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- Sede di partenza + eventuali sotto-sedi collegate tramite tblSedi.IdParent (es. altre
        -- sedi/filiali dello stesso cliente/fornitore esterno), a qualunque profondità. A
        -- differenza di una sede interna, da una sede esterna NON si scende mai tramite
        -- IdAziendaInterna (punta sempre in alto verso la sede interna che la gestisce, mai verso
        -- un'altra sede da cancellare) né tramite tblSediEsterne.IdSedeInterna (stesso concetto).
        -- COLLATE DATABASE_DEFAULT esplicito: senza, la colonna erediterebbe la collation di tempdb
        -- (non convertita insieme al DB, vedi project_collation_conversion), in conflitto con le
        -- colonne CHAR(16) del database nei confronti/JOIN sottostanti.
        CREATE TABLE #Sedi (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
        INSERT INTO #Sedi (Id) VALUES (@IdSede);

        DECLARE @nuoveRighe INT = 1;
        WHILE @nuoveRighe > 0
        BEGIN
            INSERT INTO #Sedi (Id)
            SELECT DISTINCT s.Id
            FROM dbo.tblSedi s
            INNER JOIN #Sedi c ON s.IdParent = c.Id
            WHERE NOT EXISTS (SELECT 1 FROM #Sedi t WHERE t.Id = s.Id);

            SET @nuoveRighe = @@ROWCOUNT;
        END

        DECLARE @totaleSedi INT = (SELECT COUNT(*) FROM #Sedi);

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui). Stessa struttura
        -- generica di uspSYS_del_SedeInternaCascade: tutte queste tabelle referenziano tblSedi.Id
        -- indipendentemente dal tipo (interna/esterna), anche se in pratica per una sede esterna
        -- oggi solo Autorizzazioni e Movimenti risultano popolati (verificato). Gestione EoW esclusa:
        -- i Magazzini EoW sono di sede interna (confermato dall'utente), una sede esterna non ne ha
        -- di propri - può però avere un proprio Registro/Registrazioni referenziati da movimenti EoW
        -- di un magazzino interno, gestiti più sotto.
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #Etichette FROM dbo.tblEtichette WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Calendari FROM dbo.tblCalendari WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Eventi FROM dbo.tblEventi WHERE IdCalendario IN (SELECT Id FROM #Calendari);
        SELECT Id INTO #Tipi FROM dbo.tblTipi WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #TipiProprieta FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #Tipi);
        SELECT Id INTO #Persone FROM dbo.tblPersone WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Oggetti FROM dbo.tblOggetti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Magazzini FROM dbo.tblMagazzini WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- tblSedi/tblPersone/tblOggetti sono sottotipi a chiave condivisa di tblOsepe (stesso Id)
        SELECT Id INTO #OsepeIds FROM (
            SELECT Id FROM #Sedi
            UNION
            SELECT Id FROM #Persone
            UNION
            SELECT Id FROM #Oggetti
        ) x;

        SELECT Id INTO #RifiutiRegistri FROM dbo.tblRifiutiRegistri WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiAutorizzazioni FROM dbo.tblRifiutiAutorizzazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblRifiutiLimiti* non è mai popolato per una sede esterna (i Limiti si possono creare
        -- solo su sedi interne, confermato dall'utente): a differenza di uspSYS_del_SedeInternaCascade,
        -- qui non serve raccoglierlo/cancellarlo.

        SELECT Id INTO #RifiutiMovimenti
        FROM dbo.tblRifiutiMovimenti
        WHERE IdSedeProduttoreDetentore IN (SELECT Id FROM #Sedi)
           OR IdSedeDestinatario        IN (SELECT Id FROM #Sedi)
           OR IdSedeTrasportatore1      IN (SELECT Id FROM #Sedi)
           OR IdSedeIntermediario1      IN (SELECT Id FROM #Sedi)
           OR IdRegistro                IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        SELECT Id INTO #Scadenze
        FROM dbo.tblScadenze
        WHERE IdEvento IN (SELECT Id FROM #Eventi)
           OR IdTipo   IN (SELECT Id FROM #Tipi);

        SELECT Id INTO #Servizi
        FROM dbo.tblServizi
        WHERE IdEvento      IN (SELECT Id FROM #Eventi)
           OR IdRichiedente IN (SELECT Id FROM #Sedi)
           OR IdTipo        IN (SELECT Id FROM #Tipi);

        -- tblAreeSediInterne/tblAreeOsepe sono giunzioni a chiave composita verso risorse condivise
        -- a livello di Dominio (tblAree), non di proprietà della sede: si cancellano solo le righe
        -- di giunzione, mai tblAree stessa.
        SELECT Id, IdSede  INTO #AreeSediInterne FROM dbo.tblAreeSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id, IdOsepe INTO #AreeOsepe       FROM dbo.tblAreeOsepe       WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            DELETE FROM dbo.tblRifiutiAutorizzazioniAttivita         WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniConducenti       WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniEer              WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTarghe           WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            DELETE FROM dbo.tblRifiutiFormulariEtichette             WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti     WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                      WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Gestione EoW: questa sede esterna non ha magazzini/lotti EoW propri, ma il suo Registro
            -- può essere referenziato da tblEoWMaterialiRegistri e le sue Registrazioni da
            -- tblEoWMovimenti.IdRegistrazione (nullable - si azzera anziché cancellare il movimento,
            -- che resta un record di magazzino valido di un magazzino interno anche senza la
            -- registrazione di origine).
            UPDATE dbo.tblEoWMovimenti SET IdRegistrazione = NULL WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblEoWMaterialiRegistri WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL, nessun
            -- ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante fallisce per FK.
            -- In pratica un Registro RENTRI appartiene sempre a una sede interna, ma la SP resta
            -- generica per coerenza con la raccolta #RifiutiRegistri già fatta sopra.
            DELETE FROM dbo.tblRentriRegistri  WHERE Id IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblRifiutiRegistri WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            DELETE FROM dbo.tblScadenzeOsepe
            WHERE Id      IN (SELECT Id FROM #Scadenze)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblScadenze WHERE Id IN (SELECT Id FROM #Scadenze);

            DELETE FROM dbo.tblServiziOsepe
            WHERE Id      IN (SELECT Id FROM #Servizi)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblServizi WHERE Id IN (SELECT Id FROM #Servizi);

            DELETE FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipi          WHERE Id IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblEventiFirme      WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiProprieta  WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiUtenti     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenzeEccezioni
            WHERE Id       IN (SELECT Id FROM #Eventi)
               OR IdEvento IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenze WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventi     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblCalendari  WHERE Id IN (SELECT Id FROM #Calendari);

            -- Risorse riutilizzabili di proprietà della sede: prima di cancellarle si liberano da
            -- eventuali riferimenti di ALTRE sedi non coinvolte nella cascata (stessa logica
            -- ibrida di uspSYS_del_SedeInternaCascade: UPDATE=NULL dove la colonna è nullable,
            -- DELETE della riga di giunzione dove è NOT NULL).
            DECLARE @rifEsterniRimossi INT = 0;

            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneDestinatario = NULL         WHERE IdAutorizzazioneDestinatario         IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneIntermediario1 = NULL       WHERE IdAutorizzazioneIntermediario1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneProduttoreDetentore = NULL  WHERE IdAutorizzazioneProduttoreDetentore  IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore1 = NULL       WHERE IdAutorizzazioneTrasportatore1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiMovimentiDestinatari   WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari  WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiProduttori    WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiFormulariEtichette     WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblEtichette             WHERE Id IN (SELECT Id FROM #Etichette);
            DELETE FROM dbo.tblRifiutiAutorizzazioni WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblPersoneRuoli WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblPersone      WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblOggetti      WHERE Id IN (SELECT Id FROM #Oggetti);
            DELETE FROM dbo.tblMagazzini    WHERE Id IN (SELECT Id FROM #Magazzini);

            -- Giunzioni a chiave composita verso risorse condivise (tblAree non toccata)
            DELETE asi FROM dbo.tblAreeSediInterne asi INNER JOIN #AreeSediInterne t ON t.Id = asi.Id AND t.IdSede  = asi.IdSede;
            DELETE ao  FROM dbo.tblAreeOsepe       ao  INNER JOIN #AreeOsepe       t ON t.Id = ao.Id  AND t.IdOsepe = ao.IdOsepe;
            DELETE FROM dbo.tblUtentiSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL (nessuna
            -- colonna da azzerare). In pratica associata solo a sedi interne, ma la SP resta generica
            -- per lo stesso motivo della raccolta #RifiutiRegistri sopra.
            DELETE FROM dbo.tblRentriCredenzialiSedi WHERE IdSede IN (SELECT Id FROM #Sedi);

            DELETE FROM dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediRecapiti  WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediEsterne   WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediInterne   WHERE Id IN (SELECT Id FROM #Sedi);

            -- Radice e sotto-sedi cancellate in un'unica istruzione set-based: il vincolo
            -- auto-referenziato IdParent è verificato a fine istruzione (non riga per riga), quindi
            -- non si blocca da solo anche su gerarchie a più livelli.
            DELETE FROM dbo.tblSedi WHERE Id IN (SELECT Id FROM #Sedi);

            -- tblOsepe: supertipo condiviso di Sedi/Persone/Oggetti, cancellato per ultimo
            DELETE FROM dbo.tblOsepe WHERE Id IN (SELECT Id FROM #OsepeIds);

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get), solo per le entità con Id
            -- proprio (non per le tabelle a chiave condivisa/giunzione, già coperte a monte)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #OsepeIds
                UNION SELECT Id FROM #Calendari
                UNION SELECT Id FROM #Etichette
                UNION SELECT Id FROM #Eventi
                UNION SELECT Id FROM #Magazzini
                UNION SELECT Id FROM #RifiutiAutorizzazioni
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiRegistri
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT Id FROM #Scadenze
                UNION SELECT Id FROM #Servizi
                UNION SELECT Id FROM #Tipi
                UNION SELECT Id FROM #TipiProprieta
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT('Cancellazione completata. Sedi rimosse: ', @totaleSedi, '. Riferimenti esterni azzerati/rimossi su Etichette/Autorizzazioni condivise: ', @rifEsterniRimossi, '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
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

