/*
	Deploy produzione - 2026-09-02 - Rettifiche di annullamento RENTRI + esclusione da giacenze/relazioni

	Bundle combinato dei due commit non ancora deployati in produzione (tag deployed-prod fermo su
	749c429..HEAD, vedi context-4_0_ecomatico.md):
	1. adfa81a - Rettifiche di annullamento RENTRI in Rifiuti/Registrazioni (seconda sotto-tipologia di
	   rettifica, oltre alla correzione già in produzione): nota obbligatoria, nessuna propagazione
	   sull'originale, blocco permanente "già annullata".
	2. a7996ab - Esclude rettifiche/annullamenti (sia correzione che annullamento) da giacenze e
	   relazioni carico/scarico: la registrazione ORIGINALE non è mai toccata, solo la registrazione
	   di rettifica/annullamento stessa non viene più conteggiata/selezionabile.

	Entrambi i bundle sono stati testati singolarmente con dati reali su dev (dominio test1.net, dati
	di test ripuliti) e verificati eseguibili end-to-end prima di essere committati; nessun oggetto in
	comune tra i due bundle, l'ordine non è quindi critico. Vedi i commit per il dettaglio completo di
	ciascuna modifica.

	Richiede anche il deploy dell'app (repo C:\MyDoc\App\4_0_Ecomatico, commit 2f35b41 in poi) per la
	parte 1 - la parte 2 (esclusione giacenze/relazioni) è puro DB, nessun cambio app necessario.
*/

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
	@IdRegistro CHAR(16) = NULL,
	@IdRettifica CHAR(16) = NULL,
	-- Sotto-tipo di rettifica quando @IdRettifica è valorizzato: 0 = correzione (default, comportamento
	-- storico), 1 = annullamento (la registrazione risultante non modifica mai l'originale, vedi
	-- uspRifiutiRegistrazioni_upd_Annullamento e tblRentriRegistrazioniRettifiche.Annullata)
	@IsAnnullamento BIT = 0
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
		SET @IdRettifica = NULLIF(LTRIM(RTRIM(@IdRettifica)), '');

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

		-- Rettifica: nessuna scelta di registro, sempre lo stesso registro della registrazione rettificata
		-- (sovrascrive sia il default di sessione che un eventuale @IdRegistro, che il chiamante non deve passare)
		IF @IdRettifica IS NOT NULL
			SELECT @idRegistroFinale = m.IdRegistro
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			WHERE r.Id = @IdRettifica;

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
				AND r.Lock < 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Rettifica: titolarità (stesso pattern di Copia) + regole di business dedicate (punti 2/7/8 della specifica)
		IF @IdFormulario IS NULL AND @IdRettifica IS NOT NULL
		BEGIN
			IF NOT EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
					INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
					INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
				WHERE
					r.Id = @IdRettifica
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			IF NOT EXISTS (SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @IdRettifica
				AND RentriIdentificativo IS NOT NULL
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = IIF(@IsAnnullamento = 1,
					'Solo una registrazione già inviata al RENTRI può essere annullata',
					'Solo una registrazione già inviata al RENTRI può essere rettificata');
				GOTO BRANCH_END;
			END

			-- Punto 8: una rettifica (di correzione o di annullamento) non può rettificare/annullare un'altra rettifica
			IF EXISTS (SELECT 1
			FROM dbo.tblRentriRegistrazioniRettifiche
			WHERE IdRettifica = @IdRettifica)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una registrazione di rettifica non può essere a sua volta rettificata o annullata';
				GOTO BRANCH_END;
			END

			-- Un originale già annullato (annullamento confermato, inviato al RENTRI) resta annullato per
			-- sempre: non può essere annullato una seconda volta né rettificato con una correzione. La riga
			-- di tracking di un annullamento non ancora inviato viene invece hard-deleted se cancellato
			-- (mai Lock = 4), quindi qui basta verificare l'esistenza di una riga Annullata = 1 già inviata.
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRentriRegistrazioniRettifiche t
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON t.IdRettifica = rr.Id
				WHERE
					t.Id = @IdRettifica
					AND t.Annullata = 1
					AND rr.RentriIdentificativo IS NOT NULL
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è già stata annullata e non può essere annullata o rettificata nuovamente';
				GOTO BRANCH_END;
			END

			-- Punto 7: una rettifica alla volta per registrazione, di correzione O di annullamento (la
			-- successiva solo dopo che questa è stata inviata o cancellata) - le due sotto-tipologie
			-- condividono lo stesso tracking e sono quindi mutuamente esclusive. NON filtrare su Lock < 2:
			-- una rettifica appena creata resta Lock = 2 (bozza non ancora salvata) finché l'utente non la
			-- conferma da Edit - deve comunque bloccare una seconda rettifica/annullamento. L'unico stato che
			-- libera il vincolo è "inviata" (RentriIdentificativo valorizzato); una rettifica cancellata viene
			-- sempre hard-deleted insieme alla sua riga di tracking (mai Lock = 4).
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRentriRegistrazioniRettifiche t
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON t.IdRettifica = rr.Id
				WHERE
					t.Id = @IdRettifica
					AND rr.RentriIdentificativo IS NULL
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Esiste già una rettifica o un annullamento non ancora inviato al RENTRI per questa registrazione';
				GOTO BRANCH_END;
			END
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

		-- Lettura unica della registrazione sorgente per "Copia/incolla" e "Rettifica" (@IdCopia/@IdRettifica sono
		-- mutuamente esclusivi, mai valorizzati insieme dal chiamante): stesso schema del blocco Modello sopra, ma
		-- dalla coppia Registrazione/Movimento esistente invece che da un Modello. Esclusi di proposito: Data,
		-- Numero, FormularioNumero (mai impostati anche negli altri rami di _ins), Esito/QuantitaVerificata/
		-- CausaleRespingimento*/QuantitaRespinta, DataFineTrasporto, VeicoloFuoriUso*, Quantita (dipende da
		-- relazioni/giacenze - per la Rettifica viene comunque copiata pari pari dall'originale più sotto, dato
		-- che l'eventuale modifica avviene solo in fase di salvataggio, vedi uspRifiutiRegistrazioni_upd_Rettifica),
		-- Lock/DataStampa e le relazioni scarico/carico (tblRifiutiRegistrazioniRelazioni, mai copiate: per Copia
		-- su richiesta esplicita, per Rettifica perché il vincolo resta sempre sulla registrazione originale, punto 3).
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
			@cIdTrasportoTransfrontalieroTipo CHAR(1),
			@cQuantitaOriginale DECIMAL(18, 2);

		IF @IdFormulario IS NULL AND (@IdCopia IS NOT NULL OR @IdRettifica IS NOT NULL)
			SELECT
				@cIdMovimentoOrigine = m.Id,
				@cIdOperazione = m.IdOperazione,
				@cOperazione = r.Operazione,
				@cIdEer = m.IdEer,
				@cEerDescrizione = m.EerDescrizione,
				@cIdStatoFisico = m.IdStatoFisico,
				@cQuantitaOriginale = m.Quantita,
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
			WHERE r.Id = ISNULL(@IdCopia, @IdRettifica);

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
				ELSE IF @IdCopia IS NOT NULL OR @IdRettifica IS NOT NULL
				BEGIN
					-- Quantita: MAI copiata per Copia/incolla (dipende da relazioni/giacenze, la nuova
					-- registrazione parte sempre senza relazioni - invariato). Per Rettifica invece va
					-- precompilata con la quantita' corrente dell'originale (@cQuantitaOriginale): se
					-- l'originale ha relazioni attive il campo sara' disabilitato in UI e DEVE già
					-- contenere il valore reale, altrimenti uspRifiutiRegistrazioni_upd_Rettifica rifiuta
					-- il salvataggio confrontandolo con un valore mai impostato (0/NULL).
					INSERT dbo.tblRifiutiMovimenti
						(Id, IdRegistro, IdOperazione, IdEer, EerDescrizione, IdStatoFisico, IdAttivita, IdUnitaMisura, IdProvenienza, Note, Quantita)
					VALUES
						(@idMovimento, @idRegistroFinale, @cIdOperazione, @cIdEer, @cEerDescrizione, @cIdStatoFisico, @cIdAttivita, @cIdUnitaMisura, @cIdProvenienza, @cNote, IIF(@IdRettifica IS NOT NULL, @cQuantitaOriginale, NULL));

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
					WHERE Id = ISNULL(@IdCopia, @IdRettifica);

					-- Traccia il collegamento rettifica -> originale, con lo snapshot corrente dei valori
					-- dell'originale (prima di qualunque modifica): serve sia da guardia per "una rettifica
					-- alla volta" (punto 7, controllata sopra) sia da backup per il ripristino se questa bozza
					-- di rettifica viene cancellata prima di essere inviata al RENTRI (punto 6).
					IF @IdRettifica IS NOT NULL
						INSERT dbo.tblRentriRegistrazioniRettifiche
							(Id, IdRettifica, IdEer, EerDescrizione, IdStatoFisico, IdUnitaMisura, Quantita, Annullata)
						VALUES
							(@IdRettifica, @returnId, @cIdEer, @cEerDescrizione, @cIdStatoFisico, @cIdUnitaMisura, @cQuantitaOriginale, @IsAnnullamento);
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

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Salvataggio dedicato per una registrazione di rettifica di ANNULLAMENTO (@Id, collegata a un
-- originale via tblRentriRegistrazioniRettifiche.IdRettifica/Annullata=1 - vedi
-- uspRifiutiRegistrazioni_upd_Rettifica per la sotto-tipologia di correzione, stessa tabella di
-- tracking). A differenza della correzione, un annullamento non ha ALCUN campo modificabile
-- dall'utente eccetto le note (RegistrazioneNote, obbligatorie: riportano il motivo dell'annullamento
-- e diventano "annotazioni" nel payload RENTRI - vedi viewRentriRegistrazioni.RettificaIsAnnullata,
-- l'hub 1_0_RentriApi traduce la riga in un "AnnullamentoMovimento" che trasmette solo il riferimento
-- alla registrazione annullata + data + annotazioni, nessun altro campo rifiuto). Numero/Data di
-- registrazione restano quelli calcolati automaticamente (nessuna UI li espone in modifica) ma vengono
-- comunque passati a uspRifiutiRegistrazioni_upd per la sua validazione standard. Tutti gli altri campi
-- vengono riletti invariati dalla riga stessa (snapshot copiato dall'originale al momento dell'INSERT,
-- mai più toccato) e passati pari pari a uspRifiutiRegistrazioni_upd. A differenza della correzione, un
-- annullamento non propaga MAI nulla sull'originale (che infatti non viene nemmeno letto qui, se non
-- per verificare il collegamento).
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_upd_Annullamento]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@RegistrazioneData DATE = NULL,
	@RegistrazioneNumero INT = 0,
	@RegistrazioneNote VARCHAR(500) = NULL,
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

		-- Permesso + titolarità su @Id, PRIMA di leggere qualunque dato suo (stesso pattern di
		-- uspRifiutiRegistrazioni_upd_Rettifica)
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

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblRentriRegistrazioniRettifiche
		WHERE
			IdRettifica = @Id
			AND Annullata = 1)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non è un annullamento';
			GOTO BRANCH_END;
		END

		SET @RegistrazioneNote = NULLIF(LTRIM(RTRIM(@RegistrazioneNote)), '');

		-- Punto 5 della specifica: unico dato editabile dall'utente, obbligatorio (riporta il motivo
		-- dell'annullamento, diventa "annotazioni" nel payload RENTRI)
		IF @RegistrazioneNote IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il motivo dell''annullamento';
			GOTO BRANCH_END;
		END

		-- Rilettura pass-through di tutti i campi non modificabili qui (snapshot copiato dall'originale
		-- all'INSERT): stessa forma di uspRifiutiRegistrazioni_get, così uspRifiutiRegistrazioni_upd non
		-- vede alcuna differenza rispetto ai valori già presenti e non rifiuta/altera nulla oltre a
		-- Numero/Data/Note.
		DECLARE
			@idMovimento CHAR(16), @idEer CHAR(6), @idProvenienza CHAR(1), @eerDescrizione VARCHAR(200),
			@idStatoFisico CHAR(1), @idAttivitaRs CHAR(2), @idUnitaMisura CHAR(2), @quantita DECIMAL(18, 2),
			@dataInizioTrasporto SMALLDATETIME, @idDocumentoTrasportoTipo CHAR(1), @formularioNumero VARCHAR(20),
			@idAutorizzazioneProduttoreDetentore CHAR(16), @idAutorizzazioneDestinatario CHAR(16),
			@idAutorizzazioneTrasportatore1 CHAR(16), @idAutorizzazioneTrasportatore2 CHAR(16), @idAutorizzazioneTrasportatore3 CHAR(16),
			@idAutorizzazioneIntermediario1 CHAR(16), @idAutorizzazioneIntermediario2 CHAR(16), @idAutorizzazioneIntermediario3 CHAR(16),
			@utenteNote VARCHAR(500),
			@isVeicoloFuoriUso BIT, @veicoloFuoriUsoNumero VARCHAR(50), @veicoloFuoriUsoData DATE,
			@idRaee CHAR(1),
			@idEsito CHAR(1), @quantitaVerificata DECIMAL(18, 2), @isQuantitaVerificata BIT, @dataFineTrasporto SMALLDATETIME,
			@idCausaleRespingimento CHAR(1), @causaleRespingimentoAltro VARCHAR(100), @idUnitaMisuraQuantitaRespinta CHAR(2), @quantitaRespinta DECIMAL(18, 2),
			@idMateriale CHAR(2), @materialeDescrizione VARCHAR(200),
			@idAttivitaProvenienza CHAR(1);

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
			@isVeicoloFuoriUso = ISNULL(r.VeicoloFuoriUso, 0),
			@veicoloFuoriUsoNumero = r.VeicoloFuoriUsoNumero,
			@veicoloFuoriUsoData = r.VeicoloFuoriUsoData,
			@idRaee = r.IdRaee,
			@idEsito = r.IdEsito,
			@quantitaVerificata = r.QuantitaVerificata,
			@dataFineTrasporto = r.DataFineTrasporto,
			@idCausaleRespingimento = r.IdCausaleRespingimento,
			@causaleRespingimentoAltro = r.CausaleRespingimentoAltro,
			@idUnitaMisuraQuantitaRespinta = r.IdUnitaMisuraQuantitaRespinta,
			@quantitaRespinta = r.QuantitaRespinta,
			@idMateriale = r.IdMateriale,
			@materialeDescrizione = r.MaterialeDescrizione,
			@idAttivitaProvenienza = r.IdAttivitaProvenienza
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE r.Id = @Id;

		SELECT @idAutorizzazioneProduttoreDetentore = IdAutorizzazione FROM dbo.tblRifiutiMovimentiProduttori WHERE Id = @idMovimento AND Pos = 0;
		SELECT @idAutorizzazioneDestinatario = IdAutorizzazione FROM dbo.tblRifiutiMovimentiDestinatari WHERE Id = @idMovimento AND Pos = 0;
		SELECT @idAutorizzazioneTrasportatore1 = IdAutorizzazione FROM dbo.tblRifiutiMovimentiTrasportatori WHERE Id = @idMovimento AND Pos = 0;
		SELECT @idAutorizzazioneTrasportatore2 = IdAutorizzazione FROM dbo.tblRifiutiMovimentiTrasportatori WHERE Id = @idMovimento AND Pos = 1;
		SELECT @idAutorizzazioneTrasportatore3 = IdAutorizzazione FROM dbo.tblRifiutiMovimentiTrasportatori WHERE Id = @idMovimento AND Pos = 2;
		SELECT @idAutorizzazioneIntermediario1 = IdAutorizzazione FROM dbo.tblRifiutiMovimentiIntermediari WHERE Id = @idMovimento AND Pos = 0;
		SELECT @idAutorizzazioneIntermediario2 = IdAutorizzazione FROM dbo.tblRifiutiMovimentiIntermediari WHERE Id = @idMovimento AND Pos = 1;
		SELECT @idAutorizzazioneIntermediario3 = IdAutorizzazione FROM dbo.tblRifiutiMovimentiIntermediari WHERE Id = @idMovimento AND Pos = 2;

		DECLARE @classiPericolo VARCHAR(50) = (
			SELECT STRING_AGG(c.Codice, ';')
			FROM
				dbo.tblRifiutiMovimentiClassiPericolo mc
				INNER JOIN dbo.tblRifiutiClassiPericolo c ON mc.IdClasse = c.Id
			WHERE mc.Id = @idMovimento
		);

		DECLARE @idEtichette VARCHAR(50) = (
			SELECT STRING_AGG(IdEtichetta, ';')
			FROM dbo.tblRifiutiRegistrazioniEtichette
			WHERE Id = @Id
		);

		EXEC dbo.uspRifiutiRegistrazioni_upd
			@Id = @Id,
			@IdSessione = @IdSessione,
			@IdEer = @idEer,
			@IdProvenienza = @idProvenienza,
			@EerDescrizione = @eerDescrizione,
			@IdStatoFisico = @idStatoFisico,
			@ClassiPericolo = @classiPericolo,
			@IdAttivitaRs = @idAttivitaRs,
			@RegistrazioneData = @RegistrazioneData,
			@RegistrazioneNumero = @RegistrazioneNumero,
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
			@RegistrazioneNote = @RegistrazioneNote,
			@UtenteNote = @utenteNote,
			@IdEtichette = @idEtichette,
			@IsVeicoloFuoriUso = @isVeicoloFuoriUso,
			@VeicoloFuoriUsoNumero = @veicoloFuoriUsoNumero,
			@VeicoloFuoriUsoData = @veicoloFuoriUsoData,
			@IdRaee = @idRaee,
			@IdEsito = @idEsito,
			@QuantitaVerificata = @quantitaVerificata,
			@DataFineTrasporto = @dataFineTrasporto,
			@IdCausaleRespingimento = @idCausaleRespingimento,
			@CausaleRespingimentoAltro = @causaleRespingimentoAltro,
			@IdUnitaMisuraQuantitaRespinta = @idUnitaMisuraQuantitaRespinta,
			@QuantitaRespinta = @quantitaRespinta,
			@IdMateriale = @idMateriale,
			@MaterialeDescrizione = @materialeDescrizione,
			@IdAttivitaProvenienza = @idAttivitaProvenienza,
			@RegistrazioneAuto = @RegistrazioneAuto,
			@RinumeraRegistro = @RinumeraRegistro,
			-- Sempre 1, come per la rettifica di correzione: un annullamento non partecipa mai al grafo
			-- carichi/scarichi, non è un parametro esposto al chiamante
			@NessunaRegistrazioneAssociata = 1;

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

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@Soggetto VARCHAR(50) = NULL,
	@Ruolo CHAR(1) = NULL,
	@Eer VARCHAR(50) = NULL,
	@Formulario VARCHAR(50) = NULL,
	@Numeri VARCHAR(50) = NULL,
	@Etichetta VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Soggetto = dbo.ufnStringhe_get_SenzaSpazi(@Soggetto, 0, 1);
		SET @Ruolo = NULLIF(LTRIM(RTRIM(@Ruolo)), '');
		SET @Eer = dbo.ufnStringhe_get_SenzaSpazi(@Eer, 0, 1);
		SET @Formulario = dbo.ufnStringhe_get_SenzaSpazi(@Formulario, 0, 1);
		SET @Numeri = dbo.ufnStringhe_get_SenzaSpazi(@Numeri, 0, 1);
		SET @Etichetta = dbo.ufnStringhe_get_SenzaSpazi(@Etichetta, 0, 1);

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

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		DECLARE @stmt NVARCHAR(MAX);
		DECLARE @params NVARCHAR(4000) = N'
            @RowsPerPage INT,
            @Offset      INT,
            @IdSessione  CHAR(16),
            @DallaData   DATE,
            @AllaData    DATE,
            @Soggetto    VARCHAR(50),
            @Eer         VARCHAR(50),
            @Formulario  VARCHAR(50),
            @Etichetta   VARCHAR(50)';

		-- FormularioNumero: spostato da tblRifiutiFormulari.Numero a tblRifiutiMovimenti.FormularioNumero
		SET @stmt = N'
        WITH tbl AS (
            SELECT
                Id                       = r.Id,
                StatoValore              = CASE WHEN r.Lock = 1 THEN 1 ELSE 0 END,
                StatoDescrizione         = CASE WHEN r.Lock = 1 THEN ''Registrazione da confermare'' ELSE ''OK'' END,
                RegistrazioneNumero      = r.Numero,
                RegistrazioneData        = r.Data,
                OperazioneNome           = o.Nome,
                Quantita                 = m.Quantita           * IIF(r.Operazione = ''S'', -1, 1),
                IsQuantitaVerificata     = CAST(IIF(r.QuantitaVerificata IS NULL, 0, 1) AS BIT),
                QuantitaVerificata       = r.QuantitaVerificata * IIF(r.Operazione = ''S'', -1, 1),
                EerNome                  = ISNULL(c.Nome, t.Codice),
                EerDescrizione           = ISNULL(c.Descrizione, t.Nome),
                StatoFisicoCodice        = s.Codice,
                StatoFisicoNome          = s.Nome,
                AttivitaRsCodice         = a.Codice,
                AttivitaRsNome           = a.Nome,
                FormularioNumero         = m.FormularioNumero,
                ProduttoreDetentoreSede  = sp.NomeCompleto + '' - '' + sp.IndirizzoCompleto,
                Trasportatore1Sede       = st.NomeCompleto + '' - '' + st.IndirizzoCompleto,
                DestinatarioSede         = sd.NomeCompleto + '' - '' + sd.IndirizzoCompleto,
                Intermediario1Sede       = si.NomeCompleto + '' - '' + si.IndirizzoCompleto,
                r.Etichette,
                IsRentriCollegato        = CAST(IIF(z.Id IS NOT NULL, 1, 0) AS BIT),
                r.RentriIdentificativo,
                r.RentriData,
                IsRettifica              = CAST(IIF(rett.Id IS NOT NULL, 1, 0) AS BIT),
                IsAnnullamento           = CAST(ISNULL(rett.Annullata, 0) AS BIT),
                RettificaRegistrazioneNumero = ro.Numero,
                RettificaRegistrazioneData   = ro.Data
            FROM
                dbo.tblRifiutiRegistrazioni                  r
                INNER JOIN dbo.tblRifiutiMovimenti           m  ON r.IdMovimento               = m.Id
                INNER JOIN dbo.tblRifiutiRegistri            g  ON m.IdRegistro                = g.Id
                INNER JOIN dbo.tblSessioni                   e  ON g.Id                        = e.IdRegistro
                LEFT  JOIN dbo.tblRifiutiOperazioni          o  ON m.IdOperazione              = o.Id
                LEFT  JOIN dbo.tblRifiutiEer                 c  ON m.IdEer                     = c.Id
                LEFT  JOIN dbo.tblRifiutiStatiFisici         s  ON m.IdStatoFisico             = s.Id
				LEFT  JOIN dbo.tblRifiutiMateriali		     t  ON r.IdMateriale			   = t.Id
                LEFT  JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento
                                                             a  ON m.IdAttivita                = a.Id
                LEFT  JOIN dbo.tblSedi                       sp ON m.IdSedeProduttoreDetentore = sp.Id
                LEFT  JOIN dbo.tblSedi                       st ON m.IdSedeTrasportatore1      = st.Id
                LEFT  JOIN dbo.tblSedi                       sd ON m.IdSedeDestinatario        = sd.Id
                LEFT  JOIN dbo.tblSedi                       si ON m.IdSedeIntermediario1      = si.Id
                LEFT  JOIN dbo.tblRentriRegistri             z  ON g.Id                        = z.Id
                LEFT  JOIN dbo.tblRentriRegistrazioniRettifiche
                                                             rett ON rett.IdRettifica          = r.Id
                LEFT  JOIN dbo.tblRifiutiRegistrazioni       ro ON rett.Id                     = ro.Id
            WHERE
                e.Id      = @IdSessione
                AND r.Lock < 2
                AND (@DallaData IS NULL OR r.Data >= @DallaData)
                AND (@AllaData  IS NULL OR r.Data <= @AllaData)';

		IF @Soggetto IS NOT NULL
		BEGIN
			IF @Ruolo = 'P'
				SET @stmt = @stmt + N' AND (sp.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sp.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'T'
				SET @stmt = @stmt + N' AND (st.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR st.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'D'
				SET @stmt = @stmt + N' AND (sd.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sd.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE IF @Ruolo = 'I'
				SET @stmt = @stmt + N' AND (si.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR si.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
			ELSE
				SET @stmt = @stmt + N' AND (sp.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sp.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR st.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR st.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR sd.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR sd.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'''
						  + N'        OR si.NomeCompleto LIKE ''%'' + @Soggetto + ''%'' OR si.IndirizzoCompleto LIKE ''%'' + @Soggetto + ''%'')';
		END

		-- Filtro numeri: interi validati con TRY_CAST prima della concatenazione.
		-- Eccezione documentata al divieto di concatenazione: solo interi puri vengono inseriti.
		IF @Numeri IS NOT NULL
		BEGIN
			IF @Numeri LIKE '[1-9]%-%[0-9]' AND @Numeri LIKE '%[1-9]-[0-9]%'
			BEGIN
				DECLARE @numeroInizio VARCHAR(20) = SUBSTRING(@Numeri, 1, CHARINDEX('-', @Numeri) - 1);
				DECLARE @numeroFine VARCHAR(20) = SUBSTRING(@Numeri, CHARINDEX('-', @Numeri) + 1, 20);
				IF TRY_CAST(@numeroInizio AS INT) IS NOT NULL AND TRY_CAST(@numeroFine AS INT) IS NOT NULL
					SET @stmt = @stmt + N' AND r.Numero BETWEEN ' + @numeroInizio + N' AND ' + @numeroFine;
			END
			ELSE IF TRY_CAST(@Numeri AS INT) IS NOT NULL
				SET @stmt = @stmt + N' AND r.Numero = ' + @Numeri;
		END

		IF @Etichetta IS NOT NULL
			SET @stmt = @stmt + N' AND r.Id IN ('
					  + N'    SELECT t.Id FROM dbo.tblRifiutiRegistrazioniEtichette t'
					  + N'    INNER JOIN dbo.tblEtichette et ON t.IdEtichetta = et.Id'
					  + N'    WHERE et.Nome LIKE ''%'' + @Etichetta + ''%'')';

		IF @Eer IS NOT NULL
			SET @stmt = @stmt + N' AND m.IdEer LIKE ''%'' + REPLACE(@Eer, ''.'', '''') + ''%''';

		IF @Formulario IS NOT NULL
			SET @stmt = @stmt + N' AND m.FormularioNumero LIKE ''%'' + @Formulario + ''%''';

		SET @stmt = @stmt + N'
        )
        SELECT
            tbl.Id, tbl.StatoValore, tbl.StatoDescrizione,
            tbl.RegistrazioneNumero, tbl.RegistrazioneData,
            tbl.OperazioneNome, tbl.Quantita, tbl.IsQuantitaVerificata, tbl.QuantitaVerificata,
            tbl.EerNome, tbl.EerDescrizione,
            tbl.StatoFisicoCodice, tbl.StatoFisicoNome,
            tbl.AttivitaRsCodice, tbl.AttivitaRsNome,
            tbl.FormularioNumero, tbl.ProduttoreDetentoreSede, tbl.Trasportatore1Sede, tbl.DestinatarioSede, tbl.Intermediario1Sede,
            tbl.Etichette,
            tbl.IsRentriCollegato, tbl.RentriIdentificativo, tbl.RentriData,
            tbl.IsRettifica, tbl.IsAnnullamento, tbl.RettificaRegistrazioneNumero, tbl.RettificaRegistrazioneData,
            RowsCount = COUNT(*) OVER ()
        FROM tbl
        ORDER BY tbl.RegistrazioneData DESC, tbl.RegistrazioneNumero DESC
        OFFSET @Offset ROWS
        FETCH NEXT @RowsPerPage ROWS ONLY
        OPTION (RECOMPILE);';

		EXEC sp_executesql
			@stmt,
			@params,
			@RowsPerPage = @RowsPerPage,
			@Offset = @Offset,
			@IdSessione = @IdSessione,
			@DallaData = @DallaData,
			@AllaData = @AllaData,
			@Soggetto = @Soggetto,
			@Eer = @Eer,
			@Formulario = @Formulario,
			@Etichetta = @Etichetta;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Vista consumata dall'hub condiviso 1_0_rentri (branch @App='40' di uspRegistrazioni_get_List/uspRegistrazioni_upd_ByRegistrazioni),
-- referenziata letteralmente come [4_0_ecomatico]..viewRentriRegistrazioni: nome e insieme di colonne NON sono
-- rinominabili/estendibili senza coordinarsi con l'hub. Colonne allineate alla versione più aggiornata (produzione)
-- del branch gemello @App='31' (3_1_ecomatico..viewRentriRegistrazioni, fornita dall'utente il 2026-09-01) - stesso
-- sottoinsieme, non di più. Hanno un equivalente reale in questo schema e sono implementate: ClassiPericolo
-- (tblRifiutiMovimentiClassiPericolo), RegistrazioniAssociate (tblRifiutiRegistrazioniRelazioni: la
-- registrazione con RegistrazioniAssociate e' sempre in ruolo IdParent, le referenziate in ruolo Id -
-- verificato empiricamente sia per Scarico che per Materiale), MaterialeSecondarioDescrizione (tblRifiutiRegistrazioni.MaterialeDescrizione),
-- EsitoCausaleRespingimento/RespingimentoMotivo/RespingimentoQuantita (IdCausaleRespingimento/
-- CausaleRespingimentoAltro/QuantitaRespinta), TransfrontalieroTipo (IdTrasportoTransfrontalieroTipo),
-- Rettifica* (tblRentriRegistrazioniRettifiche - vedi sotto). Resta invece a NULL/0 (nessun concetto
-- equivalente, l'hub lo gestisce già con ISNULL/CASE lato C#): il secondo Intermediario (Intermediario2* lato
-- 31 - qui tblRifiutiMovimenti ha solo IdSedeIntermediario1, nessun supporto multi-intermediario su
-- Registrazioni). La logica di Provenienza=NULL per le operazioni di Trasporto/Intermediazione (equivalente
-- delle causali CSF/CSM/CST/CSX/TRD di 3_1) è replicata filtrando su tblRifiutiOperazioni.Codice ('T*aT'/'TR',
-- i codici RENTRI reali - non su Operazione CHAR(1), che è solo una classificazione interna C/S/X senza
-- mappatura univoca verso le causali di 3_1), confermato dall'utente.
CREATE OR ALTER VIEW [dbo].[viewRentriRegistrazioni]
AS
SELECT
    IDRegistro                  = g.Id,
    IDRentri                    = z.IdRentri,

    IdRegistrazione             = r.Id,
    RentriIdentificativo        = r.RentriIdentificativo,
    Numero                      = r.Numero,
    Anno                        = YEAR(r.Data),

    -- Registrazione di rettifica (tblRentriRegistrazioniRettifiche.IdRettifica = r.Id): riferimento alla
    -- registrazione originale rettificata/annullata, letta dal JOIN rett/ro sotto. RettificaIsAnnullata
    -- (tblRentriRegistrazioniRettifiche.Annullata) distingue le due sotto-tipologie per l'hub condiviso
    -- (1_0_RentriApi, Api/ApiRegistro.cs + RegistrazioneService.cs): 0 = rettifica di correzione (payload
    -- movimento completo con numero_registrazione_rettifica), 1 = rettifica di annullamento (payload
    -- ridotto, solo riferimento alla registrazione annullata + data + annotazioni).
    RettificaNumero              = ISNULL(ro.Numero, 0),
    RettificaAnno                 = ISNULL(YEAR(ro.Data), 0),
    RettificaIdentificativo      = ro.RentriIdentificativo,
    RettificaIsAnnullata          = CAST(ISNULL(rett.Annullata, 0) AS BIT),

    Data                         = r.Data,
    -- Il codice RENTRI reale (DT/aT/T*aT/RE/I/NP/M/TR/SI/T*) e' tblRifiutiOperazioni.Codice, non
    -- r.Operazione (CHAR(1) C/S/X/..., solo una classificazione interna) - confermato confrontando
    -- con l'esito di uspRegistrazioni_get_List sul DB gemello 3_1_ecomatico (causale_operazione='DT'/'aT').
    Operazione                   = o.Codice,

    Eer                          = m.IdEer,
    EerDescrizione               = m.EerDescrizione,
    StatoFisico                  = sf.Codice,
    -- Provenienza non applicabile per operazioni di Trasporto/Intermediazione (equivalente delle
    -- causali CSF/CSM/CST/CSX/TRD di 3_1 - qui filtrate sul codice RENTRI o.Codice, non su Operazione)
    Provenienza                  = CASE WHEN o.Codice IN ('T*aT', 'TR') THEN NULL ELSE ISNULL(m.IdProvenienza, 'S') END,

    Quantita                     = m.Quantita,
    UnitaMisura                  = LOWER(um.Codice),
    ClassiPericolo               = cp.ClassiPericolo,

    VeicoloFuoriUso               = ISNULL(r.VeicoloFuoriUso, 0),
    VeicoloFuoriUsoNumero        = r.VeicoloFuoriUsoNumero,
    -- Non NULL: il modello C# lato hub (Registrazione.VeicoloFuoriUsoData) e' un DateTime non nullable,
    -- Dapper lancia un'eccezione non gestita (500 generico) se la colonna arriva NULL. Il valore e'
    -- comunque irrilevante quando VeicoloFuoriUso=0 (non inviato/non consumato dall'hub in quel caso).
    VeicoloFuoriUsoData          = ISNULL(r.VeicoloFuoriUsoData, r.Data),

    CategorieAee                 = raee.Codice,

    MaterialeSecondario           = mat.Codice,
    MaterialeSecondarioDescrizione = r.MaterialeDescrizione,

    Esito                        = es.Codice,
    -- Stesso motivo di VeicoloFuoriUsoData: Registrazione.DataEsito e' DateTime non nullable lato hub.
    DataEsito                    = ISNULL(r.DataFineTrasporto, r.Data),
    QuantitaDestino               = ISNULL(r.QuantitaVerificata, m.Quantita),

    EsitoCausaleRespingimento    = CASE WHEN ISNULL(es.Codice, 'A') = 'A' THEN NULL ELSE ISNULL(ecr.Codice, 'NC') END,
    RespingimentoMotivo          = CASE WHEN ISNULL(es.Codice, 'A') = 'A' THEN NULL ELSE ISNULL(r.CausaleRespingimentoAltro, 'Non conforme') END,
    RespingimentoQuantita        = ISNULL(r.QuantitaRespinta, m.Quantita),

    Destinazione                 = attv.Codice,

    -- Scarico (o.Operazione = 'S') e Materiale (o.Codice = 'M', operazione Carico "K") usano LO STESSO
    -- verso della relazione: in tblRifiutiRegistrazioniRelazioni, IdParent e' sempre il record
    -- successivo/dipendente (chi ha attinto), Id e' sempre il record precedente/sorgente (da cui si e'
    -- attinto) - a prescindere dal tipo di operazione. Quindi "cosa ha attinto QUESTA registrazione" e'
    -- sempre "le righe con IdParent = r.Id, prendi il lato Id" (assocRiferimenti). La distinzione di
    -- verso ipotizzata inizialmente (dedotta da IDCarico/IDScarico di 3_1, Scarico/Materiale su colonne
    -- diverse) non si applica a questo schema - provato sulla registrazione reale N.3 (Scarico): la
    -- stessa riga di relazione letta nel verso "opposto" avrebbe dato un riferimento ad un Numero
    -- SUPERIORE al proprio, che RENTRI rifiuta esplicitamente (vedi vincolo Anno/Progressivo sotto).
    RegistrazioniAssociate       = CASE
        WHEN o.Operazione = 'S' OR o.Codice = 'M' THEN assocRiferimenti.Registrazioni
        ELSE NULL
    END,

    FormularioNumero              = m.FormularioNumero,
    FormularioDataInizioTrasporto = ISNULL(m.DataInizioTrasporto, r.Data),
    TransfrontalieroTipo         = tt.Codice,

    ProduttoreNome                = sp.NomeCompleto,
    ProduttoreCodiceFiscale       = ISNULL(sp.CodiceFiscale, sp.PartitaIva),
    ProduttoreNazione             = nzp.Sigla,
    ProduttoreIdComune            = ip.IdComune,
    ProduttoreIndirizzo           = ip.Indirizzo,
    ProduttoreCAP                 = ip.CAP,
    ProduttoreLocalita            = ip.Localita,

    TrasportatoreNome             = st.NomeCompleto,
    TrasportatoreCodiceFiscale    = ISNULL(st.CodiceFiscale, st.PartitaIva),
    TrasportatoreNazione          = nzt.Sigla,
    TrasportatoreAutorizzazione   = at.Numero,

    DestinatarioNome               = sd.NomeCompleto,
    DestinatarioCodiceFiscale     = ISNULL(sd.CodiceFiscale, sd.PartitaIva),
    DestinatarioNazione           = nzd.Sigla,
    DestinatarioAutorizzazione    = ad.Numero,

    IntermediarioNome              = si.NomeCompleto,
    IntermediarioCodiceFiscale    = ISNULL(si.CodiceFiscale, si.PartitaIva),
    IntermediarioNazione          = nzi.Sigla,
    IntermediarioAutorizzazione   = ai.Numero,

    -- Nessun supporto multi-intermediario su Registrazioni in questo schema (solo IdSedeIntermediario1)
    Intermediario2Nome            = CAST(NULL AS VARCHAR(200)),
    Intermediario2CodiceFiscale   = CAST(NULL AS VARCHAR(20)),
    Intermediario2Nazione         = CAST(NULL AS CHAR(2)),
    Intermediario2Autorizzazione  = CAST(NULL AS VARCHAR(20)),

    -- ISNULL su tutti gli Is*: Registrazione lato hub li mappa su bool non nullable, o e' una LEFT JOIN.
    -- Il flag su tblRifiutiOperazioni indica solo che il TIPO di operazione ammette quel ruolo in
    -- generale - va combinato con la presenza reale della Sede su QUESTA registrazione, altrimenti
    -- l'hub include comunque il blocco anagrafica nel payload RENTRI (IsProduttore/Trasportatore/
    -- Destinatario/Intermediario come gate in ApiRegistro.cs) con campi vuoti/NULL, respinto da
    -- RENTRI (es. "[0].intermediario.codice_fiscale" su una registrazione senza alcun Intermediario).
    IsProduttore                  = CAST(IIF(ISNULL(o.IsProduttore, 0)     = 1 AND m.IdSedeProduttoreDetentore IS NOT NULL, 1, 0) AS BIT),
    IsTrasportatore                = CAST(IIF(ISNULL(o.IsTrasportatore, 0) = 1 AND m.IdSedeTrasportatore1      IS NOT NULL, 1, 0) AS BIT),
    IsDestinatario                 = CAST(IIF(ISNULL(o.IsDestinatario, 0)  = 1 AND m.IdSedeDestinatario        IS NOT NULL, 1, 0) AS BIT),
    IsIntermediario                = CAST(IIF(ISNULL(o.IsIntermediario, 0) = 1 AND m.IdSedeIntermediario1      IS NOT NULL, 1, 0) AS BIT),
    IsEsito                        = ISNULL(o.IsEsito, 0),
    -- Non da tblRifiutiOperazioni.IsFormulario (governa il comportamento applicativo, non la
    -- compilazione RENTRI): l'API dati-registri vieta il blocco integrazione_fir solo per causali
    -- diverse da aT/TR/T*/T*aT (schema OpenAPI dati-registri v1.0, campo integrazione_fir) - con la
    -- vecchia logica (o.IsFormulario) TR/T* lo perdevano sempre, anche con un FIR reale.
    IsFormulario                   = CAST(IIF(o.Codice IN ('aT', 'TR', 'T*', 'T*aT'), 1, 0) AS BIT),
    IsTransfrontaliero            = CAST(IIF(r.IdTrasportoTransfrontalieroTipo IS NOT NULL, 1, 0) AS BIT),
    IsStoccaggioIstantaneo        = ISNULL(o.IsStoccaggioIstantaneo, 0),

    Lock                          = r.Lock,

    Note                          = LEFT(r.Note, 500)
FROM
    dbo.tblRifiutiRegistrazioni                        r
    INNER JOIN dbo.tblRifiutiMovimenti                 m    ON r.IdMovimento               = m.Id
    INNER JOIN dbo.tblRifiutiRegistri                  g    ON m.IdRegistro                = g.Id
    LEFT  JOIN dbo.tblRentriRegistri                   z    ON g.Id                        = z.Id
    LEFT  JOIN dbo.tblRifiutiOperazioni                o    ON m.IdOperazione              = o.Id
    LEFT  JOIN dbo.tblRifiutiStatiFisici               sf   ON m.IdStatoFisico             = sf.Id
    LEFT  JOIN dbo.tblUnitaMisura                      um   ON m.IdUnitaMisura             = um.Id
    LEFT  JOIN dbo.tblRifiutiAttivitaRecuperoSmaltimento attv ON m.IdAttivita              = attv.Id
    LEFT  JOIN dbo.tblRifiutiRaee                      raee ON r.IdRaee                    = raee.Id
    LEFT  JOIN dbo.tblRifiutiMateriali                 mat  ON r.IdMateriale               = mat.Id
    LEFT  JOIN dbo.tblRifiutiRegistrazioniEsiti        es   ON r.IdEsito                   = es.Id
    LEFT  JOIN dbo.tblRifiutiRegistrazioniEsitiCausaliRespingimento ecr ON r.IdCausaleRespingimento = ecr.Id
    LEFT  JOIN dbo.tblRifiutiTrasportiTransfrontalieriTipi tt ON r.IdTrasportoTransfrontalieroTipo = tt.Id
    LEFT  JOIN dbo.tblRentriRegistrazioniRettifiche    rett ON r.Id                        = rett.IdRettifica
    LEFT  JOIN dbo.tblRifiutiRegistrazioni             ro   ON rett.Id                     = ro.Id

    LEFT  JOIN dbo.tblSedi                             sp   ON m.IdSedeProduttoreDetentore = sp.Id
    LEFT  JOIN dbo.tblSediIndirizzi                    sip  ON sp.Id                       = sip.Id
    LEFT  JOIN dbo.tblIndirizzi                        ip   ON sip.IdIndirizzo             = ip.Id
    LEFT  JOIN dbo.tblNazioni                          nzp  ON ip.IdNazione                = nzp.Id

    LEFT  JOIN dbo.tblSedi                             st   ON m.IdSedeTrasportatore1      = st.Id
    LEFT  JOIN dbo.tblSediIndirizzi                    sit  ON st.Id                       = sit.Id
    LEFT  JOIN dbo.tblIndirizzi                        it_  ON sit.IdIndirizzo             = it_.Id
    LEFT  JOIN dbo.tblNazioni                          nzt  ON it_.IdNazione               = nzt.Id
    LEFT  JOIN dbo.tblRifiutiMovimentiTrasportatori    mt   ON m.Id                        = mt.Id AND mt.Pos = 0
    LEFT  JOIN dbo.tblRifiutiAutorizzazioni            at   ON mt.IdAutorizzazione         = at.Id

    LEFT  JOIN dbo.tblSedi                             sd   ON m.IdSedeDestinatario        = sd.Id
    LEFT  JOIN dbo.tblSediIndirizzi                    sid  ON sd.Id                       = sid.Id
    LEFT  JOIN dbo.tblIndirizzi                        id_  ON sid.IdIndirizzo             = id_.Id
    LEFT  JOIN dbo.tblNazioni                          nzd  ON id_.IdNazione               = nzd.Id
    LEFT  JOIN dbo.tblRifiutiMovimentiDestinatari      md   ON m.Id                        = md.Id AND md.Pos = 0
    LEFT  JOIN dbo.tblRifiutiAutorizzazioni            ad   ON md.IdAutorizzazione         = ad.Id

    LEFT  JOIN dbo.tblSedi                             si   ON m.IdSedeIntermediario1      = si.Id
    LEFT  JOIN dbo.tblSediIndirizzi                    sii  ON si.Id                       = sii.Id
    LEFT  JOIN dbo.tblIndirizzi                        ii_  ON sii.IdIndirizzo             = ii_.Id
    LEFT  JOIN dbo.tblNazioni                          nzi  ON ii_.IdNazione               = nzi.Id
    LEFT  JOIN dbo.tblRifiutiMovimentiIntermediari     mi   ON m.Id                        = mi.Id AND mi.Pos = 0
    LEFT  JOIN dbo.tblRifiutiAutorizzazioni            ai   ON mi.IdAutorizzazione         = ai.Id

    LEFT JOIN (
        SELECT
            mc.Id,
            ClassiPericolo = STRING_AGG(c.Codice, ';') WITHIN GROUP (ORDER BY c.Codice)
        FROM
            dbo.tblRifiutiMovimentiClassiPericolo mc
            LEFT JOIN dbo.tblRifiutiClassiPericolo c ON mc.IdClasse = c.Id
        GROUP BY
            mc.Id
    ) cp ON m.Id = cp.Id

    OUTER APPLY (
        -- Registrazioni sorgente (r e' in ruolo IdParent, il record dipendente) da cui questa
        -- registrazione ha attinto - usato sia per Scarico (o.Operazione='S') che per Materiale
        -- (o.Codice='M'), vedi commento su RegistrazioniAssociate sopra.
        SELECT Registrazioni = (
            SELECT
                progressivo = rif.Numero,
                anno = YEAR(rif.Data)
            FROM
                dbo.tblRifiutiRegistrazioniRelazioni rl
                INNER JOIN dbo.tblRifiutiRegistrazioni rif ON rl.Id = rif.Id
            WHERE
                rl.IdParent = r.Id
                AND rif.Lock = 0
            ORDER BY
                rif.Data, rif.Numero
            FOR JSON PATH
        )
    ) assocRiferimenti
GO


CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiGiacenze_get_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Data DATE = NULL,
	@Vista CHAR(1) = 'E',
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

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
		IF @Vista NOT IN ('E', 'M', 'T')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve valere ''E'', ''M'' oppure ''T''';
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

		-- Titolarità: prima non esisteva alcun controllo che @IdRegistro appartenesse
		-- all'azienda della sessione — chiunque conoscesse un Id di registro poteva
		-- leggere le giacenze di un'altra azienda.
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

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;
		IF @Data IS NULL SET @Data = GETDATE();

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		-- @Vista IN ('E', 'M'): solo righe Rifiuto prodotto/trattato, raggruppate per EER + stato fisico.
		-- @Vista = 'M': solo righe Materiale prodotto, raggruppate per materiale.
		-- @Vista = 'T': tutti i tipi, raggruppati per combinazione esatta di etichette (r.Etichette,
		-- JSON canonico già mantenuto da uspEtichette_upd/_del su tblRifiutiRegistrazioni.Etichette;
		-- NULL = bucket "Nessuna etichetta"). Le tre modalità condividono la stessa query: i rami
		-- P/T (Rifiuto prodotto/trattato) sono attivi per @Vista IN ('E','T'), il ramo M (Materiale)
		-- per @Vista IN ('M','T'); la chiave di GROUP BY usa CASE su @Vista, così la dimensione non
		-- richiesta collassa a una costante per ogni riga e non spezza ulteriormente i gruppi.
		-- StatoValore/StatoDescrizione (semaforo anzianità giacenza) sono derivati in un SELECT
		-- esterno alla CTE Giacenze, per non ripetere tre volte l'espressione DATEDIFF.
		;WITH QuantitaAssegnata AS (
			SELECT
				l.Id,
				Quantita = SUM(l.Quantita)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
				INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
			WHERE
				p.Lock = 0
				AND mp.Quantita > 0
				AND p.[Data] <= @Data
			GROUP BY l.Id
		),
		Giacenze AS (
			SELECT
				TipoCodice = 'P',
				Tipo = 'Rifiuto prodotto',
				Id = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Descrizione END),
				IdStatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN m.IdStatoFisico END),
				StatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END),
				Etichette = MIN(CASE WHEN @Vista = 'T' THEN r.Etichette END),
				Quantita = SUM(m.Quantita - ISNULL(a.Quantita, 0)),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(CASE WHEN m.Quantita - ISNULL(a.Quantita, 0) > 0 THEN r.[Data] END), @Data),
				MovimentiNumero = COUNT(DISTINCT IIF(m.Quantita - ISNULL(a.Quantita, 0) > 0, r.Id, NULL))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				INNER JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			WHERE
				r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'C'
				AND @Vista IN ('E', 'T')
				AND (@Search IS NULL OR m.IdEer LIKE '%' + REPLACE(@Search, '.', '') + '%')
				-- Una registrazione di rettifica o annullamento non è un movimento reale di
				-- carico/scarico: non deve mai contribuire alla giacenza
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
			GROUP BY
				CASE WHEN @Vista IN ('E', 'M') THEN e.Id END,
				CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(m.Quantita - ISNULL(a.Quantita, 0)) > 0

			UNION ALL

			SELECT
				TipoCodice = 'T',
				Tipo = 'Rifiuto trattato',
				Id = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Descrizione END),
				IdStatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN m.IdStatoFisico END),
				StatoFisico = MIN(CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END),
				Etichette = MIN(CASE WHEN @Vista = 'T' THEN r.Etichette END),
				Quantita = SUM(m.Quantita - ISNULL(a.Quantita, 0)),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(CASE WHEN m.Quantita - ISNULL(a.Quantita, 0) > 0 THEN r.[Data] END), @Data),
				MovimentiNumero = COUNT(DISTINCT IIF(m.Quantita - ISNULL(a.Quantita, 0) > 0, r.Id, NULL))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				LEFT JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				LEFT JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			WHERE
				r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND m.IdOperazione = 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'S'
				AND @Vista IN ('E', 'T')
				AND (@Search IS NULL OR m.IdEer LIKE '%' + REPLACE(@Search, '.', '') + '%')
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
			GROUP BY
				CASE WHEN @Vista IN ('E', 'M') THEN e.Id END,
				CASE WHEN @Vista IN ('E', 'M') THEN s.Nome END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(m.Quantita - ISNULL(a.Quantita, 0)) > 0

			UNION ALL

			SELECT
				TipoCodice = 'M',
				Tipo = 'Materiale prodotto',
				Id = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Id END),
				Nome = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				Descrizione = MIN(CASE WHEN @Vista IN ('E', 'M') THEN e.Nome END),
				IdStatoFisico = NULL,
				StatoFisico = CASE WHEN @Vista IN ('E', 'M') THEN 'nd' END,
				Etichette = MIN(CASE WHEN @Vista = 'T' THEN r.Etichette END),
				Quantita = SUM(m.Quantita - ISNULL(a.Quantita, 0)),
				GiacenzaGiorni = DATEDIFF(DAY, MIN(CASE WHEN m.Quantita - ISNULL(a.Quantita, 0) > 0 THEN r.[Data] END), @Data),
				MovimentiNumero = COUNT(DISTINCT IIF(m.Quantita - ISNULL(a.Quantita, 0) > 0, r.Id, NULL))
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiMateriali e ON r.IdMateriale = e.Id
			WHERE
				r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'C'
				AND @Vista IN ('M', 'T')
				AND (@Search IS NULL OR e.Id LIKE '%' + @Search + '%' OR e.Nome LIKE '%' + @Search + '%')
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
			GROUP BY
				CASE WHEN @Vista IN ('E', 'M') THEN e.Id END,
				CASE WHEN @Vista = 'T' THEN r.Etichette END
			HAVING SUM(m.Quantita - ISNULL(a.Quantita, 0)) > 0
		)
		SELECT
			TipoCodice, Tipo, Id, Nome, Descrizione, IdStatoFisico, StatoFisico, Etichette,
			Quantita, GiacenzaGiorni, MovimentiNumero,
			StatoValore = CASE
				WHEN GiacenzaGiorni > 365 THEN 2
				WHEN GiacenzaGiorni > 30  THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN GiacenzaGiorni > 365 THEN 'In giacenza da oltre un anno (' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni)'
				WHEN GiacenzaGiorni > 30  THEN 'In giacenza da oltre 30 giorni (' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni)'
				WHEN GiacenzaGiorni = 1   THEN 'In giacenza da 1 giorno'
				ELSE 'In giacenza da ' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni'
			END
		FROM Giacenze
		ORDER BY
			GiacenzaGiorni DESC,
			Nome,
			StatoFisico,
			Tipo,
			Etichette
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

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

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiGiacenze_get_Carichi_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Data DATE = NULL,
	@Vista CHAR(1) = 'E',
	@Tipo CHAR(1) = NULL,
	@Id CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@Etichette VARCHAR(2000) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Tipo = NULLIF(LTRIM(RTRIM(@Tipo)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @Etichette = NULLIF(LTRIM(RTRIM(@Etichette)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

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
		IF @Vista NOT IN ('E', 'T')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve valere ''E'' oppure ''T''';
			GOTO BRANCH_END;
		END
		-- @Tipo = NULL: vista "senza filtri", elenca tutti i carichi in giacenza a prescindere
		-- da tipo/EER/etichetta (raggiungibile direttamente dal menu Azioni). Se invece @Tipo è
		-- valorizzato (drill-down da una riga EER o Etichette), deve essere uno dei tre codici noti.
		IF @Tipo IS NOT NULL AND @Tipo NOT IN ('P', 'T', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve valere ''P'', ''T'' oppure ''M''';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NOT NULL AND @Vista = 'E' AND @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto con @Vista = ''E''';
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

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;
		IF @Data IS NULL SET @Data = GETDATE();

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		-- Dettaglio dei singoli carichi (registrazioni) che compongono una riga aggregata
		-- di uspRifiutiGiacenze_get_List: stessa logica di quantità residua (Quantita -
		-- QuantitaAssegnata), stesse tre casistiche (Rifiuto prodotto/trattato, Materiale
		-- prodotto), ma senza aggregazione e filtrate sul gruppo scelto da chi ha cliccato
		-- la riga (@Vista = 'E' -> @Id [+@IdStatoFisico], @Vista = 'T' -> @Etichette).
		-- RowsCount e StatoValore/StatoDescrizione (semaforo anzianità giacenza) sono calcolati
		-- nel SELECT esterno alla CTE Carichi, non dentro ciascun ramo: altrimenti con @Tipo =
		-- NULL (nessun filtro, tutti i rami attivi) RowsCount riporterebbe solo il conteggio
		-- parziale del proprio ramo invece del totale.
		;WITH QuantitaAssegnata AS (
			SELECT
				l.Id,
				Quantita = SUM(l.Quantita)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
				INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
			WHERE
				p.Lock = 0
				AND mp.Quantita > 0
				AND p.[Data] <= @Data
			GROUP BY l.Id
		),
		Carichi AS (
			SELECT
				r.Id,
				r.Numero,
				r.[Data],
				IdEer = e.Id,
				EerNome = e.Nome,
				IdStatoFisico = m.IdStatoFisico,
				StatoFisico = s.Nome,
				r.Etichette,
				m.IdUnitaMisura,
				Quantita = m.Quantita,
				QuantitaAssegnata = ISNULL(a.Quantita, 0),
				QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0),
				GiacenzaGiorni = DATEDIFF(DAY, r.[Data], @Data)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				INNER JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			WHERE
				(@Tipo IS NULL OR @Tipo = 'P')
				AND r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'C'
				AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0
				AND (@Tipo IS NULL OR @Vista = 'T' OR (e.Id = @Id AND m.IdStatoFisico = @IdStatoFisico))
				AND (@Tipo IS NULL OR @Vista = 'E' OR ((@Etichette IS NULL AND r.Etichette IS NULL) OR r.Etichette = @Etichette))
				AND (@Search IS NULL OR e.Id LIKE '%' + REPLACE(@Search, '.', '') + '%')
				-- Una registrazione di rettifica o annullamento non è un movimento reale di
				-- carico/scarico: non deve mai contribuire alla giacenza
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)

			UNION ALL

			SELECT
				r.Id,
				r.Numero,
				r.[Data],
				IdEer = e.Id,
				EerNome = e.Nome,
				IdStatoFisico = m.IdStatoFisico,
				StatoFisico = s.Nome,
				r.Etichette,
				m.IdUnitaMisura,
				Quantita = m.Quantita,
				QuantitaAssegnata = ISNULL(a.Quantita, 0),
				QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0),
				GiacenzaGiorni = DATEDIFF(DAY, r.[Data], @Data)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				LEFT JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
				LEFT JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
			WHERE
				(@Tipo IS NULL OR @Tipo = 'T')
				AND r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND m.IdOperazione = 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'S'
				AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0
				AND (@Tipo IS NULL OR @Vista = 'T' OR (ISNULL(e.Id, '') = ISNULL(@Id, '') AND ISNULL(m.IdStatoFisico, '') = ISNULL(@IdStatoFisico, '')))
				AND (@Tipo IS NULL OR @Vista = 'E' OR ((@Etichette IS NULL AND r.Etichette IS NULL) OR r.Etichette = @Etichette))
				AND (@Search IS NULL OR ISNULL(e.Id, '') LIKE '%' + REPLACE(@Search, '.', '') + '%')
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)

			UNION ALL

			SELECT
				r.Id,
				r.Numero,
				r.[Data],
				IdEer = e.Id,
				EerNome = e.Nome,
				IdStatoFisico = NULL,
				StatoFisico = NULL,
				r.Etichette,
				m.IdUnitaMisura,
				Quantita = m.Quantita,
				QuantitaAssegnata = ISNULL(a.Quantita, 0),
				QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0),
				GiacenzaGiorni = DATEDIFF(DAY, r.[Data], @Data)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
				INNER JOIN dbo.tblRifiutiMateriali e ON r.IdMateriale = e.Id
			WHERE
				(@Tipo IS NULL OR @Tipo = 'M')
				AND r.Lock = 0
				AND r.[Data] <= @Data
				AND m.IdRegistro = @IdRegistro
				AND ISNULL(m.IdOperazione, '') <> 'R'
				AND m.Quantita > 0
				AND o.Operazione = 'C'
				AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0
				AND (@Tipo IS NULL OR @Vista = 'T' OR e.Id = @Id)
				AND (@Tipo IS NULL OR @Vista = 'E' OR ((@Etichette IS NULL AND r.Etichette IS NULL) OR r.Etichette = @Etichette))
				AND (@Search IS NULL OR e.Id LIKE '%' + @Search + '%' OR e.Nome LIKE '%' + @Search + '%')
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
		)
		SELECT
			Id, Numero, [Data], IdEer, EerNome, IdStatoFisico, StatoFisico, Etichette,
			IdUnitaMisura, Quantita, QuantitaAssegnata, QuantitaResidua, GiacenzaGiorni,
			StatoValore = CASE
				WHEN GiacenzaGiorni > 365 THEN 2
				WHEN GiacenzaGiorni > 30  THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN GiacenzaGiorni > 365 THEN 'In giacenza da oltre un anno (' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni)'
				WHEN GiacenzaGiorni > 30  THEN 'In giacenza da oltre 30 giorni (' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni)'
				WHEN GiacenzaGiorni = 1   THEN 'In giacenza da 1 giorno'
				ELSE 'In giacenza da ' + CAST(GiacenzaGiorni AS VARCHAR(10)) + ' giorni'
			END,
			RowsCount = COUNT(*) OVER ()
		FROM Carichi
		ORDER BY GiacenzaGiorni DESC, EerNome, Numero
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

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

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiGiacenze_get_Quantita]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdEer CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@Data DATE = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @Giacenza DECIMAL(18, 2);

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');

		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdEer IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdEer non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdStatoFisico IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdStatoFisico non può essere vuoto';
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

		-- Titolarità: stesso controllo di uspRifiutiGiacenze_get_List/_get_Carichi_List.
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

		SET @Data = ISNULL(@Data, GETDATE());

		-- Stessa logica di quantità residua di uspRifiutiGiacenze_get_List/_get_Carichi_List
		-- (Quantita - QuantitaAssegnata), ma senza raggruppamento/paginazione: un unico SUM
		-- per la combinazione Registro+Eer+StatoFisico richiesta. I due rami "Rifiuto prodotto"
		-- (IdOperazione <> 'R', Operazione = 'C') e "Rifiuto trattato" (IdOperazione = 'R',
		-- Operazione = 'S') sono mutuamente esclusivi sullo stesso record, quindi si possono
		-- unire in un solo OR invece di due UNION ALL separate.
		;WITH QuantitaAssegnata AS (
			SELECT
				l.Id,
				Quantita = SUM(l.Quantita)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
				INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
			WHERE
				p.Lock = 0
				AND mp.Quantita > 0
				AND p.[Data] <= @Data
			GROUP BY l.Id
		)
		SELECT
			@Giacenza = SUM(m.Quantita - ISNULL(a.Quantita, 0))
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN QuantitaAssegnata a ON r.Id = a.Id
		WHERE
			r.Lock = 0
			AND r.[Data] <= @Data
			AND m.IdRegistro = @IdRegistro
			AND m.IdEer = @IdEer
			AND m.IdStatoFisico = @IdStatoFisico
			AND m.Quantita > 0
			AND (
				(ISNULL(m.IdOperazione, '') <> 'R' AND o.Operazione = 'C')
				OR (m.IdOperazione = 'R' AND o.Operazione = 'S')
			)
			AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0
			-- Una registrazione di rettifica o annullamento non è un movimento reale di
			-- carico/scarico: non deve mai contribuire alla giacenza
			AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id);

		SELECT rtn = ISNULL(@Giacenza, 0);

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

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_get_RegistrazioniDaAssociare_List]
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdParent CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@IdEer CHAR(6),
	@IdStatoFisico CHAR(1),
	@IdUnitaMisura CHAR(2),
	@Numero INT,
	@Data DATE,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
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

		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		DECLARE @Offset INT = (@PageNumber - 1) * @RowsPerPage;

		-- Legge l'operazione della registrazione padre FUORI dalla query principale
		DECLARE @idOperazione CHAR(1);
		SELECT @idOperazione = m.IdOperazione
		FROM dbo.tblRifiutiRegistrazioni r
		INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE r.Id = @IdParent;

		-- Materializzazione unica del set "registrazioni da associare": evita di
		-- ricalcolare la stessa catena di join/aggregazioni due volte (una per il
		-- risultato principale, una per il NOT EXISTS del placeholder)
		SELECT
			Verso = 1,
			r.Id,
			r.Operazione,
			r.Numero,
			r.[Data],
			m.IdUnitaMisura,
			Quantita = ISNULL(a.Quantita, 0),
			QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0),
			EerNome = e.Nome,
			StatoFisicoNome = s.Nome,
			Anno = YEAR(r.[Data])
		INTO #cte
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN (
				SELECT
					l.Id,
					Quantita = SUM(l.Quantita)
				FROM
					dbo.tblRifiutiRegistrazioniRelazioni l
					INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
					INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
				WHERE
					p.Lock < 2
					AND mp.Quantita > 0
				GROUP BY l.Id
			) a ON r.Id = a.Id
					LEFT JOIN dbo.tblRifiutiEer e ON m.IdEer = e.Id
					LEFT JOIN dbo.tblRifiutiStatiFisici s ON m.IdStatoFisico = s.Id
		WHERE
			r.Lock = 0
			AND m.IdRegistro = @IdRegistro
			AND
				(
				@idOperazione IN ('M', 'K')
				OR m.IdEer = @IdEer
				)
			AND
				(
				@idOperazione IN ('M', 'K')
				OR m.IdStatoFisico = @IdStatoFisico
				)
			AND
				(
				@idOperazione IN ('M', 'K')
				OR m.IdUnitaMisura = @IdUnitaMisura
				)
			AND
				(
				r.[Data] < @Data
				OR
					(
					r.[Data] = @Data
					AND r.Numero < @Numero
					)
				)
			AND m.IdOperazione IN ( SELECT IdParent FROM dbo.tblRifiutiOperazioniRelazioni WHERE Id = @idOperazione )
			AND (m.Quantita - ISNULL(a.Quantita, 0)) > 0
			AND r.Id NOT IN ( SELECT Id FROM dbo.tblRifiutiRegistrazioniRelazioni WHERE IdParent = @IdParent )
			-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
			-- proprie: non deve mai comparire come candidata da associare
			AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id);

		CREATE UNIQUE CLUSTERED INDEX IX_cte_Anno_Numero ON #cte (Anno, Numero, Id);

		;WITH cteTotali AS (
			SELECT
				Operazione,
				Registrazioni = COUNT(*),
				Totali = IIF(Operazione = 'S', 'Scarichi ', 'Carichi ') +
					'da associare: ' + FORMAT(COUNT(*), 'N0', 'IT-it') +
					' | Tot. q.tà associata: ' + FORMAT(ISNULL(SUM(Quantita), 0), 'N2', 'IT-it') +
					' | Tot. q.tà residua: ' + FORMAT(ISNULL(SUM(QuantitaResidua), 0), 'N2', 'IT-it')
			FROM #cte
			GROUP BY Operazione
		)
		SELECT
			c.Verso, c.Id, c.Operazione, c.Numero, c.[Data],
			c.IdUnitaMisura, c.Quantita, c.QuantitaResidua,
			c.EerNome, c.StatoFisicoNome, c.Anno,
			t.Registrazioni, t.Totali
		FROM #cte c
		CROSS JOIN cteTotali t

		UNION ALL

		SELECT
			Verso = 1,
			Id = NULL,
			Operazione = NULL,
			Numero = 0,
			[Data] = '19000101',
			IdUnitaMisura = NULL,
			Quantita = 0,
			QuantitaResidua = 0,
			EerNome = NULL,
			StatoFisicoNome = NULL,
			Anno = 1900,
			Registrazioni = 0,
			Totali = IIF(r.Operazione = 'C', 'Scarichi da associare', 'Carichi da associare')
		FROM dbo.tblRifiutiRegistrazioni r
		WHERE
			r.Id = @IdParent
			AND NOT EXISTS (SELECT 1 FROM #cte)
		ORDER BY Anno, Numero
		OFFSET @Offset ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;

GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_ins_RelazioniTutte]
	@IdSessione CHAR(16) = NULL,
	@IdParent CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@IdEer CHAR(6),
	@IdStatoFisico CHAR(1),
	@IdUnitaMisura CHAR(2),
	@Numero INT,
	@Data DATE
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
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

		-- Calcolata una sola volta e riusata nei due controlli titolarità sottostanti,
		-- invece di richiamare la function separatamente per ciascuno
		DECLARE @sedi TABLE (Id CHAR(16) PRIMARY KEY);
		INSERT @sedi (Id)
		SELECT Id
		FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione);

		IF (
			SELECT COUNT(DISTINCT g.Id)
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN @sedi i ON g.IdSede = i.Id
			WHERE g.Id = @IdRegistro) = 0
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
				INNER JOIN @sedi i ON g.IdSede = i.Id
			WHERE r.Id = @IdParent)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La registrazione padre, già trasmessa a RENTRI, non può cambiare le proprie associazioni
		IF EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @IdParent
				AND (RentriIdentificativo IS NOT NULL OR RentriData IS NOT NULL)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può essere associata ad altre registrazioni';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
		-- proprie - difesa in profondità, la UI già nasconde la sezione per queste registrazioni
		IF EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = @IdParent)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può avere relazioni di carico/scarico';
			GOTO BRANCH_END;
		END

		DECLARE @pos INT;
		SELECT @pos = ISNULL(MAX(s.Pos), -1)
		FROM
			dbo.tblRifiutiRegistrazioniRelazioni s
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON s.Id = r.Id
		WHERE
			s.IdParent = @IdParent
			AND r.Lock < 2;

		IF @pos >= 499
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Superato il numero massimo di registrazioni associabili';
			GOTO BRANCH_END;
		END

		DECLARE @idOperazione CHAR(1);
		SELECT @idOperazione = m.IdOperazione
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE r.Id = @IdParent;

		BEGIN TRANSACTION;

			--      QuantitaResidua = m.Quantita - ISNULL(a.Quantita, 0)
			INSERT dbo.tblRifiutiRegistrazioniRelazioni
				(Id, IdParent, Operazione, Quantita, Pos)
			SELECT TOP(499 - @pos)
				r.Id,
				@IdParent,
				IIF(r.Operazione = 'C', 'S', 'C'),
				0,
				@pos + ROW_NUMBER() OVER (ORDER BY YEAR(r.[Data]), r.Numero)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN (
					SELECT
						l.Id,
						Quantita = SUM(l.Quantita)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni l
						INNER JOIN dbo.tblRifiutiRegistrazioni p ON l.IdParent = p.Id
						INNER JOIN dbo.tblRifiutiMovimenti mp ON p.IdMovimento = mp.Id
					WHERE
						p.Lock < 2
						AND mp.Quantita > 0
					GROUP BY l.Id
				) a ON r.Id = a.Id
			WHERE
				r.Lock = 0
				AND m.IdRegistro = @IdRegistro
				AND
					(
					@idOperazione IN ('K', 'M')
					OR m.IdEer = @IdEer
					)
				AND
					(
					@idOperazione IN ('K', 'M')
					OR m.IdStatoFisico = @IdStatoFisico
					)
				AND
					(
					@idOperazione IN ('K', 'M')
					OR m.IdUnitaMisura = @IdUnitaMisura
					)
				AND
					(
					r.[Data] < @Data
					OR
						(
						r.[Data] = @Data
						AND r.Numero < @Numero
						)
					)
				AND m.IdOperazione IN ( SELECT IdParent FROM dbo.tblRifiutiOperazioniRelazioni WHERE Id = @idOperazione )
				AND m.Quantita - ISNULL(a.Quantita, 0) > 0 -- QuantitaResidua > 0
				AND NOT EXISTS ( SELECT 1 FROM dbo.tblRifiutiRegistrazioniRelazioni x WHERE x.Id = r.Id AND x.IdParent = @IdParent )
				-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
				-- proprie: non deve mai comparire come candidata da associare
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica = r.Id)
			ORDER BY YEAR(r.[Data]), r.Numero;

			SET @returnValue = @@ROWCOUNT;

			-- Imposta la registrazione nello stato "Da confermare"
			UPDATE dbo.tblRifiutiRegistrazioni
			SET Lock = 1
			WHERE
				Id = @IdParent
				AND Lock = 0;

		COMMIT TRANSACTION;

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

	SELECT ReturnValue = @returnValue;
END;

GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_ins_Relazione]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdParent CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
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

		-- Recupera l'operazione del padre e verifica che esista
		DECLARE @operazioneParent CHAR(1);
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);
		SELECT
			@operazioneParent = Operazione,
			@rentriIdentificativo = RentriIdentificativo,
			@rentriData = RentriData
		FROM dbo.tblRifiutiRegistrazioni
		WHERE Id = @IdParent;

		IF @operazioneParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione padre non trovata';
			GOTO BRANCH_END;
		END

		-- La registrazione padre, già trasmessa a RENTRI, non può cambiare le proprie associazioni
		IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può essere associata ad altre registrazioni';
			GOTO BRANCH_END;
		END

		-- Una registrazione di rettifica o annullamento non ha mai relazioni carico/scarico
		-- proprie (né come padre né come figlia) - difesa in profondità, la UI già la esclude
		-- dalle liste di selezione (uspRifiutiRegistrazioni_get_RegistrazioniDaAssociare_List)
		IF EXISTS (SELECT 1 FROM dbo.tblRentriRegistrazioniRettifiche WHERE IdRettifica IN (@Id, @IdParent))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica o annullamento non può avere relazioni di carico/scarico';
			GOTO BRANCH_END;
		END

		IF (
			SELECT COUNT(DISTINCT r.Id)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE r.Id IN (@Id, @IdParent)) < 2
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @pos INT;
		SELECT @pos = ISNULL(MAX(s.Pos), -1) + 1
		FROM dbo.tblRifiutiRegistrazioniRelazioni s
		INNER JOIN dbo.tblRifiutiRegistrazioni r ON s.Id = r.Id
		WHERE
			s.IdParent = @IdParent
			AND r.Lock < 2;
		IF @pos >= 499
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Superato il numero massimo di registrazioni associabili';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			INSERT INTO dbo.tblRifiutiRegistrazioniRelazioni
				(Id, IdParent, Operazione, Quantita, Pos)
			VALUES
				(@Id, @IdParent, @operazioneParent, 0, @pos);

			-- Imposta la registrazione padre nello stato "Da confermare"
			UPDATE dbo.tblRifiutiRegistrazioni
			SET Lock = 1
			WHERE
				Id = @IdParent
				AND Lock = 0;
		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;
	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;

GO

