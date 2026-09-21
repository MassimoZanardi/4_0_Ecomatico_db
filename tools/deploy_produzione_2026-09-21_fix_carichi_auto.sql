/*
	Deploy produzione - 2026-09-21 - Fix "Generazione automatica carichi da Modello"

	Repo: 4_0_ecomatico. Corregge 4 stored procedure del modulo "Generazione automatica
	carichi da Modello" (deployato in produzione con deploy_produzione_2026-09-18_
	registrazioni_auto_modello.sql, tag deployed-prod), trovati durante il test manuale
	del modulo. Nessuna modifica di schema: solo CREATE OR ALTER su SP già esistenti.

	PREREQUISITO: le tabelle/SP di deploy_produzione_2026-09-18_registrazioni_auto_modello.sql
	devono essere già presenti (risultano già deployate, il tag deployed-prod è successivo
	a quel commit).

	Contenuto di questo script:
	  1) CREATE OR ALTER uspRifiutiModelli_ins_RegistrazioniAuto (aggiunge il controllo:
	     somma percentuali delle righe attive del Modello <= 100)
	  2) CREATE OR ALTER uspRifiutiModelli_upd_RegistrazioniAuto (idem, esclusa la riga in
	     modifica dalla somma)
	  3) CREATE OR ALTER uspRifiutiModelli_get_RegistrazioniAuto (aggiunge EerNome/
	     MaterialeNome al payload, mancavano - causavano select EER vuota nella modale di
	     modifica quando il codice non era tra le opzioni già caricate a inizio pagina)
	  4) CREATE OR ALTER uspRifiutiRegistrazioni_ins_CaricoAuto (3 fix cumulativi):
	     - inserisce la relazione mancante in tblRifiutiRegistrazioniRelazioni tra il
	       carico generato e la registrazione di scarico di origine (Id=origine,
	       IdParent=nuovo carico, Operazione=Operazione del carico)
	     - blocca la generazione se la quantità già associata + quella nuova supera la
	       quantità residua disponibile sulla registrazione di origine

	ATTENZIONE PRIMA DI ESEGUIRE:
	  - Tutte le stored procedure usano CREATE OR ALTER: idempotenti, ridistribuibili senza
	    errore anche se già presenti.
	  - Nessuna modifica di schema (tabelle) in questo script.
	  - Verificato su DB dev: tutte le SP deployate e verificate (ANSI_NULLS/QUOTED_IDENTIFIER/
	    CRLF/XACT_ABORT), smoke test con sessione a basso privilegio; controllo somma
	    percentuali verificato contro il Modello reale cc75f34854344261 (5 righe che sommavano
	    112, correttamente bloccato dal nuovo controllo); fix relazione/quantità residua
	    verificati contro la registrazione Id=65bddb1e1fe94a5a e lo scarico Numero 14
	    (Id=d2f15ef77ce2408e).
	  - NOTA DATI: sul DB dev, lo scarico Numero 14 (Id d2f15ef77ce2408e) ha ancora 5 relazioni
	    verso i Carichi Numero 15-19 che sommano 33,60 kg contro i suoi 30 kg, create PRIMA di
	    questo fix - dato sporco di test, non presente in produzione (il modulo non era ancora
	    usato). Nessuna azione correttiva necessaria in questo script.
	  - Eseguire con: sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i <questo file>
	    (il flag -f 65001 è obbligatorio per non corrompere gli accenti italiani)
*/
--------------------------------------------------------------------------------
-- 1) dbo.uspRifiutiModelli_ins_RegistrazioniAuto
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiModelli_ins_RegistrazioniAuto]
	@IdSessione CHAR(16) = NULL,
	@IdModello CHAR(16) = NULL,
	@Percentuale INT = NULL,
	@IdEer CHAR(6) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@IdEtichette VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdModello = NULLIF(LTRIM(RTRIM(@IdModello)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdModello IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModello non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Percentuale IS NULL OR @Percentuale <= 0 OR @Percentuale > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La percentuale deve essere compresa tra 1 e 100';
			GOTO BRANCH_END;
		END
		IF (@IdEer IS NULL AND @IdMateriale IS NULL) OR (@IdEer IS NOT NULL AND @IdMateriale IS NOT NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare Eer oppure Materiale, non entrambi';
			GOTO BRANCH_END;
		END
		-- Lo Stato fisico non ha senso per il Materiale (per cui deve restare NULL).
		IF @IdMateriale IS NULL AND @IdStatoFisico IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdStatoFisico non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdMateriale IS NOT NULL
			SET @IdStatoFisico = NULL;
		-- L'unità di misura per il Materiale è sempre KG: non ci si fida che client/C# l'abbiano
		-- già impostata correttamente (il campo è disabilitato lato UI quando si seleziona Materiale).
		IF @IdMateriale IS NOT NULL
			SET @IdUnitaMisura = 'KG';
		IF @IdUnitaMisura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUnitaMisura non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RMD', @Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sul Modello padre.
		IF NOT EXISTS (
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

		-- Solo i modelli con Operazione 'I' (Scarico di rifiuto per trattamento interno) possono
		-- avere righe di generazione automatica.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelli m
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			WHERE
				m.Id = @IdModello
				AND o.Codice = 'I')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le registrazioni automatiche sono disponibili solo per l''operazione di scarico per trattamento interno';
			GOTO BRANCH_END;
		END

		-- Limite massimo di righe per Modello.
		IF 10 <= (SELECT COUNT(*)
		FROM dbo.tblRifiutiModelliRegistrazioniAuto
		WHERE
			IdModello = @IdModello
			AND Lock = 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'È stato raggiunto il limite massimo di registrazioni automatiche inseribili';
			GOTO BRANCH_END;
		END

		-- La somma delle percentuali delle righe attive non può superare 100: altrimenti la
		-- generazione automatica (uspRifiutiRegistrazioni_ins_CaricoAuto) produrrebbe sempre più
		-- materiale di quanto scaricato, sforando la quantità residua dello scarico di origine.
		IF @Percentuale + ISNULL((
			SELECT SUM(Percentuale)
			FROM dbo.tblRifiutiModelliRegistrazioniAuto
			WHERE
				IdModello = @IdModello
				AND Lock = 0
		), 0) > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La somma delle percentuali delle registrazioni automatiche non può superare 100';
			GOTO BRANCH_END;
		END

		DECLARE @posizione INT = 1 + ISNULL((SELECT MAX(Posizione)
		FROM dbo.tblRifiutiModelliRegistrazioniAuto
		WHERE
			IdModello = @IdModello
			AND Lock = 0), 0);

		-- uspId_get gestisce la propria transazione internamente: chiamata FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;

			INSERT dbo.tblRifiutiModelliRegistrazioniAuto
				(Id, IdModello, Posizione, Percentuale, IdEer, IdMateriale, IdStatoFisico, IdUnitaMisura, Lock)
			VALUES
				(@returnId, @IdModello, @posizione, @Percentuale, @IdEer, @IdMateriale, @IdStatoFisico, @IdUnitaMisura, 0);

			INSERT dbo.tblRifiutiModelliRegistrazioniAutoEtichette
				(Id, IdEtichetta)
			SELECT TOP 3
				@returnId,
				e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

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

--------------------------------------------------------------------------------
-- 2) dbo.uspRifiutiModelli_upd_RegistrazioniAuto
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiModelli_upd_RegistrazioniAuto]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Percentuale INT = NULL,
	@IdEer CHAR(6) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@IdEtichette VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEer = NULLIF(LTRIM(RTRIM(@IdEer)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdStatoFisico = NULLIF(LTRIM(RTRIM(@IdStatoFisico)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');

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
		IF @Percentuale IS NULL OR @Percentuale <= 0 OR @Percentuale > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La percentuale deve essere compresa tra 1 e 100';
			GOTO BRANCH_END;
		END
		IF (@IdEer IS NULL AND @IdMateriale IS NULL) OR (@IdEer IS NOT NULL AND @IdMateriale IS NOT NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare Eer oppure Materiale, non entrambi';
			GOTO BRANCH_END;
		END
		-- Lo Stato fisico non ha senso per il Materiale (per cui deve restare NULL).
		IF @IdMateriale IS NULL AND @IdStatoFisico IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdStatoFisico non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdMateriale IS NOT NULL
			SET @IdStatoFisico = NULL;
		-- L'unità di misura per il Materiale è sempre KG: non ci si fida che client/C# l'abbiano
		-- già impostata correttamente (il campo è disabilitato lato UI quando si seleziona Materiale).
		IF @IdMateriale IS NOT NULL
			SET @IdUnitaMisura = 'KG';
		IF @IdUnitaMisura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUnitaMisura non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RMD', @Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: incatenata da tblRifiutiModelliRegistrazioniAuto a tblRifiutiModelli. Recupera
		-- anche l'IdModello, serve per il controllo di somma percentuali sotto.
		DECLARE @idModello CHAR(16);
		SELECT @idModello = ra.IdModello
		FROM
			dbo.tblRifiutiModelliRegistrazioniAuto ra
			INNER JOIN dbo.tblRifiutiModelli m ON ra.IdModello = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE ra.Id = @Id;

		IF @idModello IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La somma delle percentuali delle righe attive (esclusa questa stessa, che viene
		-- sostituita) non può superare 100 - stesso motivo di uspRifiutiModelli_ins_RegistrazioniAuto.
		IF @Percentuale + ISNULL((
			SELECT SUM(Percentuale)
			FROM dbo.tblRifiutiModelliRegistrazioniAuto
			WHERE
				IdModello = @idModello
				AND Lock = 0
				AND Id <> @Id
		), 0) > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La somma delle percentuali delle registrazioni automatiche non può superare 100';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			DELETE dbo.tblRifiutiModelliRegistrazioniAutoEtichette
			WHERE Id = @Id;

			INSERT dbo.tblRifiutiModelliRegistrazioniAutoEtichette
				(Id, IdEtichetta)
			SELECT TOP 3
				@Id,
				e.Id
			FROM
				dbo.tblEtichette e
				INNER JOIN STRING_SPLIT(@IdEtichette, ';') v ON e.Id = v.value;

			UPDATE dbo.tblRifiutiModelliRegistrazioniAuto
			SET
				Percentuale = @Percentuale,
				IdEer = @IdEer,
				IdMateriale = @IdMateriale,
				IdStatoFisico = @IdStatoFisico,
				IdUnitaMisura = @IdUnitaMisura
			WHERE
				Id = @Id
				AND Lock = 0;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Registrazione automatica non trovata o già eliminata';
				GOTO BRANCH_END;
			END

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

--------------------------------------------------------------------------------
-- 3) dbo.uspRifiutiModelli_get_RegistrazioniAuto
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiModelli_get_RegistrazioniAuto]
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
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RMD', @Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità: stesso pattern di uspRifiutiModelli_get_Etichette_SelectList, incatenato da
		-- tblRifiutiModelliRegistrazioniAuto a tblRifiutiModelli.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiModelliRegistrazioniAuto ra
				INNER JOIN dbo.tblRifiutiModelli m ON ra.IdModello = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE ra.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- EerNome/MaterialeNome: mancavano del tutto - il payload JSON arrivava al modale di modifica
		-- (Pages/Rifiuti/Modelli/Edit.cshtml, registrazioneAutoEdit) senza la descrizione necessaria
		-- per aggiungere l'opzione mancante nella select EER quando il codice non è tra quelle già
		-- caricate a inizio pagina - stessa risoluzione già presente in
		-- uspRifiutiModelli_get_RegistrazioniAuto_List, qui replicata.
		SELECT
			ra.Id,
			ra.IdModello,
			ra.Posizione,
			ra.Percentuale,
			IsMateriale = CAST(IIF(ra.IdMateriale IS NOT NULL, 1, 0) AS BIT),
			ra.IdEer,
			EerNome = eer.Nome + ISNULL(' - ' + eer.Descrizione, ''),
			ra.IdMateriale,
			MaterialeNome = mat.Nome,
			ra.IdStatoFisico,
			ra.IdUnitaMisura,
			IdEtichette = (
				SELECT STRING_AGG(IdEtichetta, ';')
				FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette
				WHERE Id = ra.Id)
		FROM
			dbo.tblRifiutiModelliRegistrazioniAuto ra
			LEFT JOIN dbo.tblRifiutiEer eer ON ra.IdEer = eer.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON ra.IdMateriale = mat.Id
		WHERE ra.Id = @Id;

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
-- 4) dbo.uspRifiutiRegistrazioni_ins_CaricoAuto
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiRegistrazioni_ins_CaricoAuto]
	@IdSessione CHAR(16) = NULL,
	@IdRegistrazioneOrigine CHAR(16) = NULL,
	@IdRegistrazioneAuto CHAR(16) = NULL,
	@Quantita DECIMAL(18, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON
	BEGIN TRY

		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistrazioneOrigine = NULLIF(LTRIM(RTRIM(@IdRegistrazioneOrigine)), '');
		SET @IdRegistrazioneAuto = NULLIF(LTRIM(RTRIM(@IdRegistrazioneAuto)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistrazioneOrigine IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazioneOrigine non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistrazioneAuto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistrazioneAuto non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NULL OR @Quantita <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso @Id = @IdSessione, @IdFunzione = 'RRG', @Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Registrazione di origine (scarico 'I'): titolarità + dati da ereditare (stessa Sede/Data/Registro).
		-- Il produttore/detentore NON viene dalla registrazione di origine (uno scarico a trattamento
		-- interno non ne ha uno), ma dal Modello usato per configurare la registrazione automatica.
		DECLARE @idRegistro CHAR(16);
		DECLARE @idModello CHAR(16);
		DECLARE @data DATE;
		DECLARE @quantitaOrigine DECIMAL(18, 2);

		SELECT
			@idRegistro = m.IdRegistro,
			@idModello = m.IdModello,
			@data = r.[Data],
			@quantitaOrigine = m.Quantita
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE r.Id = @IdRegistrazioneOrigine;

		IF @idRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione di origine non trovata o non disponibile';
			GOTO BRANCH_END;
		END

		-- Verifica quantità già scaricata (stesso pattern di uspRifiutiRegistrazioni_upd, righe
		-- ~554-572): la somma dei carichi già generati/associati dallo scarico di origine, più
		-- questo nuovo, non può superare la quantità totale dello scarico stesso - altrimenti la
		-- quantità residua diventa negativa (bug reale trovato sui dati: scarico da 30 kg con 5
		-- carichi generati per un totale di 33,60 kg).
		DECLARE @quantitaGiaAssociata DECIMAL(18, 2) = ISNULL((
			SELECT SUM(l.Quantita)
			FROM
				dbo.tblRifiutiRegistrazioniRelazioni l
				INNER JOIN dbo.tblRifiutiRegistrazioni rp ON l.IdParent = rp.Id
			WHERE
				l.Id = @IdRegistrazioneOrigine
				AND l.Quantita > 0
				AND rp.Lock < 2
		), 0);

		IF @quantitaGiaAssociata + @Quantita > ISNULL(@quantitaOrigine, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità supera quella residua disponibile sulla registrazione di origine';
			GOTO BRANCH_END;
		END

		DECLARE @idAutorizzazioneProduttoreDetentore CHAR(16);
		SELECT @idAutorizzazioneProduttoreDetentore = IdAutorizzazioneProduttoreDetentore
		FROM dbo.tblRifiutiModelli
		WHERE Id = @idModello;

		IF @idAutorizzazioneProduttoreDetentore IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il modello non ha impostato il produttore o detentore, obbligatorio per le registrazioni automatiche';
			GOTO BRANCH_END;
		END

		-- Riga di configurazione (tblRifiutiModelliRegistrazioniAuto): deve appartenere allo stesso
		-- Modello della registrazione di origine, non a un Modello arbitrario passato dal chiamante.
		DECLARE @idEer CHAR(6);
		DECLARE @idMateriale CHAR(2);
		DECLARE @idStatoFisico CHAR(1);
		DECLARE @idUnitaMisura CHAR(2);

		SELECT
			@idEer = ra.IdEer,
			@idMateriale = ra.IdMateriale,
			@idStatoFisico = ra.IdStatoFisico,
			@idUnitaMisura = ra.IdUnitaMisura
		FROM dbo.tblRifiutiModelliRegistrazioniAuto ra
		WHERE
			ra.Id = @IdRegistrazioneAuto
			AND ra.IdModello = @idModello
			AND ra.Lock = 0;

		IF @idEer IS NULL AND @idMateriale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione automatica non trovata o non appartenente al modello di origine';
			GOTO BRANCH_END;
		END

		-- Operazione destinazione via lookup su Codice (mai sul singolo carattere Id, che non è
		-- mnemonico: Id='M' ha Codice='NP', Id='K' ha Codice='M'). @operazioneGruppo è la colonna
		-- 'Operazione' (raggruppamento S/C/X usato da tblRifiutiRegistrazioni.Operazione), diversa
		-- dall'Id specifico che invece va su tblRifiutiMovimenti.IdOperazione - stesso schema di
		-- uspRifiutiRegistrazioni_ins (@mOperazione vs @mIdOperazione).
		DECLARE @idOperazioneDestinazione CHAR(1);
		DECLARE @operazioneGruppo CHAR(1);
		SELECT
			@idOperazioneDestinazione = Id,
			@operazioneGruppo = Operazione
		FROM dbo.tblRifiutiOperazioni
		WHERE Codice = IIF(@idMateriale IS NOT NULL, 'M', 'NP');

		IF @idOperazioneDestinazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Operazione di destinazione non configurata';
			GOTO BRANCH_END;
		END

		DECLARE @eerDescrizione VARCHAR(200);
		DECLARE @materialeDescrizione VARCHAR(200);
		SELECT @eerDescrizione = Descrizione FROM dbo.tblRifiutiEer WHERE Id = @idEer;
		SELECT @materialeDescrizione = Nome FROM dbo.tblRifiutiMateriali WHERE Id = @idMateriale;

		-- Prossimo numero disponibile per Registro/anno (stesso schema di uspRifiutiRegistrazioni_upd,
		-- ramo di rinumerazione: 1 + MAX(Numero) tra le registrazioni confermate/bozza dell'anno).
		DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@data), 1, 1);
		DECLARE @annoFine DATE = DATEFROMPARTS(YEAR(@data) + 1, 1, 1);
		DECLARE @numero INT = 1 + ISNULL((
			SELECT MAX(r.Numero)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			WHERE
				r.Lock < 2
				AND m.IdRegistro = @idRegistro
				AND r.[Data] >= @annoInizio
				AND r.[Data] < @annoFine
		), 0);

		DECLARE @idMovimento CHAR(16);

		-- uspId_get gestisce la propria transazione internamente: chiamate FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		-- @returnId è appena stato generato in questa stessa esecuzione: non può già esistere
		-- nessuna relazione con IdParent = @returnId, la posizione è sempre 0 (stesso schema di
		-- calcolo di uspRifiutiRegistrazioni_ins_Relazione, qui degenera per costruzione).
		DECLARE @pos INT = 0;

		BEGIN TRANSACTION;

			INSERT dbo.tblRifiutiMovimenti
				(Id, IdRegistro, IdOperazione, IdEer, EerDescrizione, IdStatoFisico, IdUnitaMisura, Quantita)
			VALUES
				(@idMovimento, @idRegistro, @idOperazioneDestinazione, @idEer, @eerDescrizione, @idStatoFisico, @idUnitaMisura, @Quantita);

			INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Pos)
			VALUES (@idMovimento, @idAutorizzazioneProduttoreDetentore, 0);

			INSERT dbo.tblRifiutiRegistrazioni
				(Id, IdMovimento, Operazione, [Data], Numero, QuantitaVerificata, IdMateriale, MaterialeDescrizione, Lock)
			VALUES
				(@returnId, @idMovimento, @operazioneGruppo, @data, @numero, @Quantita, @idMateriale, @materialeDescrizione, 0);

			-- Relazione mancava del tutto, il carico auto restava senza legame con lo scarico che lo ha
			-- generato. Verificato sui dati reali (registrazione Id=65bddb1e1fe94a5a, carico K/M) contro
			-- una relazione creata manualmente: Id = la registrazione di SCARICO (qui l'origine 'I'),
			-- IdParent = la registrazione di CARICO (qui il nuovo @returnId) - il verso opposto a quanto
			-- inserito nel primo tentativo. Operazione = @operazioneGruppo, l'Operazione del CARICO
			-- (sempre 'C' per NP/M, già calcolata sopra) - coerente perché ora è anche l'Operazione
			-- propria di IdParent, stesso schema di uspRifiutiRegistrazioni_ins_Relazione (Operazione =
			-- Operazione del padre).
			-- Il padre (qui il nuovo carico, non l'origine) resta comunque a Lock=0: è la registrazione
			-- appena creata in questa stessa transazione, non passa mai da "da confermare".
			INSERT dbo.tblRifiutiRegistrazioniRelazioni (Id, IdParent, Operazione, Quantita, Pos)
			VALUES (@IdRegistrazioneOrigine, @returnId, @operazioneGruppo, @Quantita, @pos);

			INSERT dbo.tblRifiutiRegistrazioniEtichette (Id, IdEtichetta)
			SELECT @returnId, IdEtichetta
			FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette
			WHERE Id = @IdRegistrazioneAuto;

			UPDATE dbo.tblRifiutiRegistrazioni
			SET Etichette = dbo.ufnRifiutiRegistrazioni_get_Etichette(Id)
			WHERE Id = @returnId;

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
