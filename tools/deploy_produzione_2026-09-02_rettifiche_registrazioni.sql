/*
	Deploy produzione - 2026-09-02 - Rettifiche RENTRI in Rifiuti/Registrazioni

	Nuova funzionalità: una rettifica è una nuova registrazione (stesso pattern di Copia/incolla,
	senza scelta registro) collegata alla registrazione originale già inviata al RENTRI che corregge.

	Regole di business:
	- L'originale dev'essere già inviato al RENTRI (RentriIdentificativo valorizzato).
	- Una rettifica non ha mai relazioni carico/scarico proprie.
	- Se l'originale ha relazioni carico/scarico attive, Eer/StatoFisico/UnitaMisura/Quantita
	  della rettifica restano bloccati sui valori correnti dell'originale; altrimenti la rettifica
	  li può modificare e li propaga sull'originale al salvataggio (ripristinati dalla tabella di
	  tracking se la rettifica viene cancellata prima di essere inviata).
	- Una rettifica alla volta per originale (la successiva solo dopo che questa è stata inviata o
	  cancellata). Una rettifica non può rettificare un'altra rettifica.
	- Cancellazione di una rettifica non ancora inviata sempre irreversibile (mai soft-delete/Undo),
	  bloccata se multipla (@IsMultipla, nuovo parametro di uspRifiutiRegistrazioni_del).

	Oggetti inclusi:
	1. dbo.tblRentriRegistrazioniRettifiche (NUOVA TABELLA, con guard IF NOT EXISTS)
	2. dbo.uspRifiutiRegistrazioni_ins (esteso con @IdRettifica)
	3. dbo.uspRifiutiRegistrazioni_del (esteso con hard-delete+ripristino rettifica, @IsMultipla)
	4. dbo.uspRifiutiRegistrazioni_upd_Rettifica (NUOVA SP)
	5. dbo.uspRifiutiRegistrazioni_get (esteso con IsRettifica/IsRettificaCampiBloccati/
	   IdRegistrazioneOriginaleRettifica/RettificaRegistrazioneNumero/RettificaRegistrazioneData -
	   quest'ultime due per il banner "Questa registrazione rettifica la registrazione n. XXX del
	   dd/MM/yyyy" in Edit.cshtml; aggiunto anche l'header SET ANSI_NULLS/QUOTED_IDENTIFIER mancante,
	   QUOTED_IDENTIFIER era OFF lato server - nessun impatto funzionale)
	6. dbo.uspRifiutiRegistrazioni_get_List (esteso con IsRettifica/RettificaRegistrazioneNumero/
	   RettificaRegistrazioneData - servono a _RentriStatoPartial per l'icona di rettifica in Index)
	7. dbo.viewRentriRegistrazioni (valorizza RettificaNumero/RettificaAnno/RettificaIdentificativo
	   per l'hub RENTRI condiviso - RettificaIsAnnullata resta sempre 0, nessun concetto di
	   annullamento in questo schema)

	Nessun impatto sulle registrazioni esistenti: tutte le nuove colonne sono aggiuntive (LEFT JOIN,
	default NULL/0/false quando non applicabile), nessuna colonna/comportamento rimosso o modificato
	per le registrazioni che non sono rettifiche.

	Testato con dati reali su dev (dominio test1.net): creazione, blocco doppia rettifica pendente,
	blocco rettifica-di-rettifica, salvataggio con gate/propagazione, cancellazione con ripristino,
	blocco cancellazione multipla, vista, icona in Index - nessuna regressione sulle registrazioni
	non-rettifica. Formattazione uniformata con tools/SqlFormatter.cs dove applicabile.

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-02_rettifiche_registrazioni.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)

	Richiede in produzione (già presenti in dev/verificati in questa sessione):
	- uspRifiutiRegistrazioni_upd aggiornata con RentriIdentificativo/RentriData e il blocco
	  "già inviata al RENTRI" (commit eac42b2/8f4ead2, bundle
	  deploy_produzione_2026-09-02_blocco_modifica_post_invio.sql) - se non ancora deployato in
	  produzione, deployarlo PRIMA di questo bundle: uspRifiutiRegistrazioni_upd_Rettifica ne
	  richiama la versione corrente via EXEC.
*/

--------------------------------------------------------------------------------
-- dbo.tblRentriRegistrazioniRettifiche (nuova tabella)
--------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'tblRentriRegistrazioniRettifiche' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
	EXEC('
	CREATE TABLE [dbo].[tblRentriRegistrazioniRettifiche](
		[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
		[IdRettifica] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
		[IdUnitaMisura] [char](2) COLLATE Latin1_General_CI_AS NULL,
		[IdEer] [char](6) COLLATE Latin1_General_CI_AS NULL,
		[IdStatoFisico] [char](1) COLLATE Latin1_General_CI_AS NULL,
		[Quantita] [decimal](18, 2) NULL,
		[EerDescrizione] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	 CONSTRAINT [PK_tblRentriRegistrazioniRettifiche] PRIMARY KEY CLUSTERED
	(
		[Id] ASC,
		[IdRettifica] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
	) ON [PRIMARY]');

	EXEC('
	CREATE UNIQUE NONCLUSTERED INDEX [IX_RentriRegistrazioniRettifiche_IdRettifica] ON [dbo].[tblRentriRegistrazioniRettifiche]
	(
		[IdRettifica] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]');

	ALTER TABLE [dbo].[tblRentriRegistrazioniRettifiche]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriRegistrazioniRettifiche_tblRifiutiRegistrazioni_id] FOREIGN KEY([Id])
	REFERENCES [dbo].[tblRifiutiRegistrazioni] ([Id]);

	ALTER TABLE [dbo].[tblRentriRegistrazioniRettifiche] CHECK CONSTRAINT [FK_tblRentriRegistrazioniRettifiche_tblRifiutiRegistrazioni_id];

	ALTER TABLE [dbo].[tblRentriRegistrazioniRettifiche]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriRegistrazioniRettifiche_tblRifiutiRegistrazioni_idRettifica] FOREIGN KEY([IdRettifica])
	REFERENCES [dbo].[tblRifiutiRegistrazioni] ([Id]);

	ALTER TABLE [dbo].[tblRentriRegistrazioniRettifiche] CHECK CONSTRAINT [FK_tblRentriRegistrazioniRettifiche_tblRifiutiRegistrazioni_idRettifica];
END
GO

--------------------------------------------------------------------------------
-- dbo.uspRifiutiRegistrazioni_ins
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
	@IdRegistro CHAR(16) = NULL,
	@IdRettifica CHAR(16) = NULL
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
				SET @returnMessage = 'Solo una registrazione già inviata al RENTRI può essere rettificata';
				GOTO BRANCH_END;
			END

			-- Punto 8: una rettifica non può rettificare un'altra rettifica
			IF EXISTS (SELECT 1
			FROM dbo.tblRentriRegistrazioniRettifiche
			WHERE IdRettifica = @IdRettifica)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una registrazione di rettifica non può essere a sua volta rettificata';
				GOTO BRANCH_END;
			END

			-- Punto 7: una rettifica alla volta per registrazione (la successiva solo dopo che questa è stata
			-- inviata o cancellata). NON filtrare su Lock < 2: una rettifica appena creata resta Lock = 2
			-- (bozza non ancora salvata) finché l'utente non la conferma da Edit - deve comunque bloccare una
			-- seconda rettifica. L'unico stato che libera il vincolo è "inviata" (RentriIdentificativo valorizzato);
			-- una rettifica cancellata viene sempre hard-deleted insieme alla sua riga di tracking (mai Lock = 4).
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
				SET @returnMessage = 'Esiste già una rettifica non ancora inviata al RENTRI per questa registrazione';
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
							(Id, IdRettifica, IdEer, EerDescrizione, IdStatoFisico, IdUnitaMisura, Quantita)
						VALUES
							(@IdRettifica, @returnId, @cIdEer, @cEerDescrizione, @cIdStatoFisico, @cIdUnitaMisura, @cQuantitaOriginale);
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

--------------------------------------------------------------------------------
-- dbo.uspRifiutiRegistrazioni_del
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0,
	@IsMultipla BIT = 0
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

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblRifiutiRegistrazioni
		WHERE Id = @Id);

		-- Se @Id è una registrazione di rettifica, @idOriginaleRettifica è l'Id della registrazione
		-- rettificata (tblRentriRegistrazioniRettifiche.Id) - NULL per una registrazione normale.
		DECLARE @idOriginaleRettifica CHAR(16) = (SELECT Id
		FROM dbo.tblRentriRegistrazioniRettifiche
		WHERE IdRettifica = @Id);

		IF @lock IS NULL
		BEGIN
			-- Idempotenza: registrazione mai esistita o già cancellata (es. doppio invio della
			-- richiesta di annullamento lato UI) — trattata come cancellazione già avvenuta con
			-- successo, non come errore. Salta anche il controllo di titolarità sottostante e
			-- l'intera catena Lock, che non hanno senso su un record inesistente.
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

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

		-- Una registrazione di rettifica non ancora inviata al RENTRI è sempre cancellata in modo
		-- irreversibile (mai soft-delete/Undo, vedi sotto) tramite una modale dedicata con conferma
		-- esplicita: la cancellazione multipla (checkbox in elenco) non è ammessa su di essa.
		IF @IsMultipla = 1 AND @idOriginaleRettifica IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiRegistrazioni
			WHERE
				Id = @Id
				AND RentriIdentificativo IS NOT NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione di rettifica non ancora inviata al RENTRI va cancellata singolarmente';
			GOTO BRANCH_END;
		END

		DECLARE @idMovimento CHAR(16);
		DECLARE @idFormulario CHAR(16);
		DECLARE @operazione CHAR(1);
		DECLARE @idOperazione CHAR(1);
		DECLARE @isFormulario BIT;
		DECLARE @rentriIdentificativo VARCHAR(20);
		DECLARE @rentriData DATETIME2(0);

		-- ── CASO 1: registrazione attiva (Lock = 0) → soft delete, o hard delete se è una rettifica ──
		IF @lock = 0
		BEGIN
			SELECT @rentriIdentificativo = RentriIdentificativo, @rentriData = RentriData
			FROM dbo.tblRifiutiRegistrazioni
			WHERE Id = @Id;

			-- Una registrazione già trasmessa a RENTRI non può più essere cancellata (vale anche per una rettifica)
			IF @rentriIdentificativo IS NOT NULL OR @rentriData IS NOT NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La registrazione è già stata inviata al RENTRI: non può più essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiRegistrazioniRelazioni a
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON a.IdParent = r.Id
				WHERE
					a.Id = @Id
					AND r.Lock < 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una registrazione associata ad altre non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Recupero dati registrazione
			SELECT
				@idMovimento = r.IdMovimento,
				@idFormulario = f.Id,
				@operazione = r.Operazione,
				@idOperazione = m.IdOperazione
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				LEFT JOIN dbo.tblRifiutiFormulari f ON m.Id = f.IdMovimento
			WHERE r.Id = @Id;

			IF @idOriginaleRettifica IS NOT NULL
			BEGIN
				-- Rettifica confermata (Lock = 0) ma non ancora inviata al RENTRI: cancellazione sempre
				-- irreversibile (punto 6 della specifica, mai passa da Lock = 4/Undo). Ripristina prima
				-- sull'originale i valori precedenti la rettifica (no-op se non erano mai stati modificati,
				-- caso in cui l'originale aveva relazioni carico/scarico attive - punto 4), poi hard delete
				-- completo della rettifica, stessa sequenza del CASO 3 sotto.
				BEGIN TRANSACTION;

					UPDATE mo
					SET
						IdEer = t.IdEer,
						EerDescrizione = t.EerDescrizione,
						IdStatoFisico = t.IdStatoFisico,
						IdUnitaMisura = t.IdUnitaMisura,
						Quantita = t.Quantita
					FROM
						dbo.tblRentriRegistrazioniRettifiche t
						INNER JOIN dbo.tblRifiutiRegistrazioni ro ON t.Id = ro.Id
						INNER JOIN dbo.tblRifiutiMovimenti mo ON ro.IdMovimento = mo.Id
					WHERE
						t.Id = @idOriginaleRettifica
						AND t.IdRettifica = @Id;

					DELETE dbo.tblRifiutiRegistrazioniRelazioni
					WHERE
						Id = @Id
						OR IdParent = @Id;
					DELETE dbo.tblRifiutiMovimentiClassiPericolo
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiProduttori
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiTrasportatori
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiIntermediari
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimentiLog
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiRegistrazioniEtichette
					WHERE Id = @Id;
					UPDATE dbo.tblEoWMovimenti
					SET IdRegistrazione = NULL
					WHERE IdRegistrazione = @Id;
					DELETE dbo.tblRentriRegistrazioniRettifiche
					WHERE
						Id = @idOriginaleRettifica
						AND IdRettifica = @Id;
					DELETE dbo.tblRifiutiRegistrazioni
					WHERE Id = @Id;
					DELETE dbo.tblRifiutiFormulari
					WHERE
						IdMovimento = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblRifiutiMovimenti
					WHERE
						Id = @idMovimento
						AND @idFormulario IS NULL;
					DELETE dbo.tblIdLog
					WHERE
						Id = @Id
						OR
							(
							Id = @idMovimento
							AND @idFormulario IS NULL
							);
					DELETE dbo.tblId
					WHERE
						Id = @Id
						OR
							(
							Id = @idMovimento
							AND @idFormulario IS NULL
							);

				COMMIT TRANSACTION;
			END
			ELSE
			BEGIN
				BEGIN TRANSACTION;
					UPDATE dbo.tblRifiutiRegistrazioni
					SET Lock = 4
					WHERE
						Id = @Id
						AND Lock = 0;

					IF @@ROWCOUNT = 0
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Registrazione non trovata o già eliminata';
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
		END

		-- ── CASO 2: registrazione non confermata (Lock = 1) ──────────────────
		ELSE IF @lock = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Una registrazione non confermata non può essere cancellata';
			GOTO BRANCH_END;
		END

		-- ── CASO 3: registrazione in bozza (Lock = 2) → hard delete ──────────
		ELSE IF @lock = 2
		BEGIN
			SELECT
				@idMovimento = r.IdMovimento,
				@idFormulario = f.Id
			FROM
				dbo.tblRifiutiRegistrazioni r
				LEFT JOIN dbo.tblRifiutiFormulari f ON r.IdMovimento = f.IdMovimento
			WHERE r.Id = @Id;

			BEGIN TRANSACTION;
				DELETE dbo.tblRifiutiRegistrazioniRelazioni
				WHERE
					Id = @Id
					OR IdParent = @Id;
				DELETE dbo.tblRifiutiMovimentiClassiPericolo
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiProduttori
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiTrasportatori
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimentiIntermediari
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				-- Mancante in precedenza: dettaglio 1:1 a chiave condivisa (Id NOT NULL) di
				-- tblRifiutiMovimenti, blocca la DELETE su tblRifiutiMovimenti se esistono righe
				-- (stesso gap trovato e corretto in uspRifiutiFormulari_del il 2026-08-21)
				DELETE dbo.tblRifiutiMovimentiLog
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiRegistrazioniEtichette
				WHERE Id = @Id;
				-- Gestione EoW: tblEoWMovimenti.IdRegistrazione (nullable) può referenziare questa
				-- registrazione se l'automatismo sulla causale K l'ha già collegata a un movimento
				-- di magazzino EoW - si azzera il collegamento anziché bloccare la cancellazione,
				-- il movimento resta un record di magazzino valido anche senza la registrazione di
				-- origine (stesso pattern di uspSYS_del_RegistroCascade).
				UPDATE dbo.tblEoWMovimenti
				SET IdRegistrazione = NULL
				WHERE IdRegistrazione = @Id;
				-- Bozza di rettifica mai confermata: nessun valore è mai stato propagato sull'originale
				-- (la propagazione avviene solo in uspRifiutiRegistrazioni_upd_Rettifica al salvataggio),
				-- quindi qui basta rimuovere il collegamento, nessun ripristino necessario.
				DELETE dbo.tblRentriRegistrazioniRettifiche
				WHERE IdRettifica = @Id;
				DELETE dbo.tblRifiutiRegistrazioni
				WHERE Id = @Id;
				DELETE dbo.tblRifiutiFormulari
				WHERE
					IdMovimento = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblRifiutiMovimenti
				WHERE
					Id = @idMovimento
					AND @idFormulario IS NULL;
				DELETE dbo.tblIdLog
				WHERE
					Id = @Id
					OR
						(
						Id = @idMovimento
						AND @idFormulario IS NULL
						);
				DELETE dbo.tblId
				WHERE
					Id = @Id
					OR
						(
						Id = @idMovimento
						AND @idFormulario IS NULL
						);
			COMMIT TRANSACTION;
		END

		-- ── CASO 4: Lock in stato non gestito ────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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
-- dbo.uspRifiutiRegistrazioni_upd_Rettifica (nuova SP)
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- dbo.uspRifiutiRegistrazioni_get
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

--------------------------------------------------------------------------------
-- dbo.uspRifiutiRegistrazioni_get_List
--------------------------------------------------------------------------------
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
            tbl.IsRettifica, tbl.RettificaRegistrazioneNumero, tbl.RettificaRegistrazioneData,
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

--------------------------------------------------------------------------------
-- dbo.viewRentriRegistrazioni
--------------------------------------------------------------------------------
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
    -- registrazione originale corretta, letta dal JOIN rett/ro sotto. Nessun concetto di
    -- "annullamento" in questo schema (solo correzione), RettificaIsAnnullata resta sempre 0.
    RettificaNumero              = ISNULL(ro.Numero, 0),
    RettificaAnno                 = ISNULL(YEAR(ro.Data), 0),
    RettificaIdentificativo      = ro.RentriIdentificativo,
    RettificaIsAnnullata          = CAST(0 AS BIT),

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
