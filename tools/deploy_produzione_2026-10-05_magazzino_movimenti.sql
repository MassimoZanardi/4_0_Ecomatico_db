/*
Deploy produzione 2026-10-05 - Magazzino > Movimenti (ricerca, anagrafiche del DDT, controlli, carichi per riga)
e Giacenze (viste Articolo, Lotto, Carichi; sempre la sede del contesto); EoW e Magazzino: nuova funzione Configurazione

Stored procedure (CREATE OR ALTER) e registrazione di due nuove funzioni (punto 0). Nessuna modifica alla
struttura delle tabelle. Rieseguibile.

0. EoW - nuova funzione EWC "Configurazione" (tblFunzioni, tblModuliFunzioni) che governa i permessi
   su Lotti, Magazzini e Allocazioni: le tre pagine (tblPagine EWL, EWM, EWA) passano da EOW a EWC.
   NESSUN travaso dei permessi: dopo il deploy gli utenti non amministratori che avevano EOW non vedono
   Lotti, Magazzini e Allocazioni finche' non gli si assegna EWC in Impostazioni > Utenti.
   Magazzino - nuova funzione MGC "Configurazione" che governa i permessi su Articoli e Lotti: le due
   pagine (tblPagine MGA, MGL) passano da MAG a MGC. Anche qui NESSUN travaso: chi aveva MAG non vede
   Articoli e Lotti finche' non gli si assegna MGC.
   Le due funzioni esistenti EOW e MAG vengono rinominate in "Gestione" (tblFunzioni) e i due moduli in
   "EoW" e "Magazzino" (tblModuli). Il messaggio di uspMagazziniMovimentiRigheEoW_ins diventa "Il modulo
   EoW non e' attivo sul dominio".

1. uspMagazziniMovimenti_get_List
   - Ricerca: i filtri mittente, destinatario e trasportatore sono ora testo libero ("contiene" su
     nome + indirizzo dell'anagrafica, anche se disabilitata). I parametri @DdtIdMittente,
     @DdtIdDestinatario e @DdtIdTrasportatore sono sostituiti da @DdtMittente, @DdtDestinatario e
     @DdtTrasportatore (VARCHAR(50)).
   - Colonna DdtSedeNome: nome + indirizzo della sede del DDT.
2. uspMagazziniMovimenti_get_SediInterneSelectList: testo e ricerca su nome + indirizzo
   (select Sede della modale "Nuovo movimento").
3. uspMagazziniDdt_get: SedeNome, MittenteNome, DestinatarioNome e TrasportatoreNome con nome + indirizzo.
4. uspMagazziniMovimenti_upd: il controllo unico "Completare il DDT: causale, data e destinatario"
   diventa tre controlli separati ("Selezionare la causale del DDT", "Indicare la data del DDT",
   "Selezionare il destinatario del DDT"). Stessa cosa per il controllo alla conferma sul criterio
   di scarico delle righe: "Completare il criterio di scarico della riga..." diventa un controllo per
   condizione (criterio mancante, criterio non valido per le righe EoW, criterio Manuale senza lotto).
5. uspMagazziniLotti_upd: messaggio "Indicare la data di apertura" (era "Il parametro @DataApertura
   non può essere vuoto").
6. uspMagazziniMovimentiRighe_get_List: nuova colonna CarichiNumero (carichi da cui la riga ha scaricato).
7. uspMagazziniMovimentiRigheEoW_get_List: nuova colonna LottiNumero (lotti EoW da cui la riga ha scaricato).
8. uspMagazziniGiacenze_get_List: riscritta sullo schema di uspEoWGiacenze_get_List. Nuovi parametri
   @PageNumber, @RowsPerPage, @Vista (A = Articolo, L = Lotto), @Search; tolto @IdArticolo. Restituisce
   giacenza, giorni e numero di carichi per articolo o per lotto. Senza sede nel contesto nessuna riga
   (prima mostrava le giacenze di tutte le sedi interne).
9. uspMagazziniGiacenze_get_Carichi_List (NUOVA): carichi con residuo della sede del contesto, tutti
   oppure di un articolo o di un lotto.
10. uspEoWGiacenze_get_Carichi_List: sempre e solo la sede del contesto, anche partendo da un lotto o
    da un magazzino; senza sede nel contesto nessuna riga (prima "Tutti" mostrava tutte le sedi interne).
11. EoW - le 23 SP di Lotti, Magazzini e Allocazioni controllano il permesso EWC al posto di EOW:
    uspEoWLotti_ins, _upd, _get, _get_List, _del, _get_MagazziniSelectList, _get_RegistrazioniList,
    _get_AllocazioniList; uspEoWMagazzini_ins, _upd, _get, _get_List, _del; uspEoWAllocazioni_ins, _upd,
    _get, _get_List, _del, _get_LottiList, _get_LottiSelectList, _ins_Lotto, _del_Lotto;
    uspEoWAllocazioniTipi_get_SelectList. Restano su EOW Registrazioni, Giacenze e l'uso dei lotti nelle
    registrazioni rifiuti (uspEoWLotti_get_LottiSelectList, uspEoWAllocazioni_get_ApplicabiliSelectList,
    uspEoWAllocazioni_esegui, uspEoWLottiRifiutiRegistrazioni_*).
12. Magazzino - le 10 SP di Articoli e Lotti controllano il permesso MGC al posto di MAG:
    uspMagazziniArticoli_ins, _upd, _get_List, _del; uspMagazziniLotti_ins, _upd, _get, _get_List, _del,
    _get_ArticoliSelectList. uspMagazziniArticoli_get accetta MGC oppure MAG (i movimenti leggono la
    scheda articolo). Restano su MAG Movimenti, Giacenze e le select di articoli e lotti delle righe
    (uspMagazziniMovimentiRighe_get_ArticoliSelectList, uspMagazziniLotti_get_SelectList).

ATTENZIONE: va deployato insieme all'app, senza lasciare passare tempo tra script e app. L'app passa
sempre i tre parametri di ricerca a uspMagazziniMovimenti_get_List, anche vuoti: con app e SP non
allineate (app vecchia e SP nuove, o viceversa) l'elenco Magazzino > Movimenti darebbe errore a ogni
apertura; lo stesso vale per Magazzino > Giacenze (uspMagazziniGiacenze_get_List ha parametri diversi).
Con l'app nuova e le SP vecchie, inoltre, la colonna Carichi mostrerebbe sempre "Nessuno".

Dopo il deploy eseguire tools\verifica_crlf_accenti.sql: deve dare 0 righe.
*/

PRINT 'Registrazione funzione: eow_configurazione_funzione';
GO
SET NOCOUNT ON;

-- Modulo EoW: nuova funzione EWC "Configurazione" che governa i permessi su Lotti, Magazzini e
-- Allocazioni (elenco, dettaglio, inserimento, modifica, cancellazione). La funzione EOW resta per
-- Registrazioni, Giacenze e per l'uso dei lotti nelle registrazioni rifiuti (select dei lotti,
-- allocazione, esecuzione di una regola di allocazione).
-- Rieseguibile. Nessun travaso dei permessi: chi aveva EOW non riceve EWC in automatico, il permesso
-- va assegnato in Impostazioni > Utenti (gli amministratori lo hanno già, come per ogni funzione dei
-- moduli attivi del dominio).

IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'EWC')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('EWC', 'Configurazione', 0, 0, 1);
ELSE
	UPDATE dbo.tblFunzioni SET Nome = 'Configurazione' WHERE Id = 'EWC' AND Nome <> 'Configurazione';

-- La funzione esistente si chiama solo "Gestione" (il modulo si legge nella colonna Moduli)
UPDATE dbo.tblFunzioni SET Nome = 'Gestione' WHERE Id = 'EOW' AND Nome <> 'Gestione';

-- Anche il modulo perde "Gestione": si chiama solo "EoW"
UPDATE dbo.tblModuli SET Nome = 'EoW' WHERE Id = 'EOW' AND Nome <> 'EoW';

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'EOW' AND IdFunzione = 'EWC')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('EOW', 'EWC');

-- Le voci di menu Lotti, Magazzini e Allocazioni seguono la funzione della pagina
UPDATE dbo.tblPagine SET IdFunzione = 'EWC' WHERE Id IN ('EWL', 'EWM', 'EWA') AND IdFunzione <> 'EWC';

SELECT Id, IdFunzione, Nome FROM dbo.tblPagine WHERE Id LIKE 'EW%' ORDER BY Id;
GO

PRINT 'Registrazione funzione: magazzino_configurazione_funzione';
GO
SET NOCOUNT ON;

-- Modulo Magazzino: nuova funzione MGC "Configurazione" che governa i permessi su Articoli e Lotti
-- (elenco, dettaglio, inserimento, modifica, cancellazione). La funzione MAG resta per Movimenti,
-- Giacenze e per l'uso di articoli e lotti nelle righe dei movimenti (select di articoli e lotti,
-- lettura della scheda articolo).
-- Rieseguibile. Nessun travaso dei permessi: chi aveva MAG non riceve MGC in automatico, il permesso
-- va assegnato in Impostazioni > Utenti (gli amministratori lo hanno già, come per ogni funzione dei
-- moduli attivi del dominio).

IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'MGC')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('MGC', 'Configurazione', 0, 0, 1);
ELSE
	UPDATE dbo.tblFunzioni SET Nome = 'Configurazione' WHERE Id = 'MGC' AND Nome <> 'Configurazione';

-- La funzione esistente si chiama solo "Gestione" (il modulo si legge nella colonna Moduli)
UPDATE dbo.tblFunzioni SET Nome = 'Gestione' WHERE Id = 'MAG' AND Nome <> 'Gestione';

-- Anche il modulo perde "Gestione": si chiama solo "Magazzino"
UPDATE dbo.tblModuli SET Nome = 'Magazzino' WHERE Id = 'MAG' AND Nome <> 'Magazzino';

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'MAG' AND IdFunzione = 'MGC')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('MAG', 'MGC');

-- Le voci di menu Articoli e Lotti seguono la funzione della pagina
UPDATE dbo.tblPagine SET IdFunzione = 'MGC' WHERE Id IN ('MGA', 'MGL') AND IdFunzione <> 'MGC';

SELECT Id, IdFunzione, Nome FROM dbo.tblPagine WHERE Id LIKE 'MG%' ORDER BY Id;
GO

PRINT 'uspMagazziniMovimenti_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimenti_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@ConDdt BIT = 0,
	@DdtNumero INT = NULL,
	@DdtNumeroFornitore VARCHAR(20) = NULL,
	@DdtMittente VARCHAR(50) = NULL,
	@DdtDestinatario VARCHAR(50) = NULL,
	@DdtTrasportatore VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');
		-- Ricerca sul DDT: "Con DDT" limita ai movimenti che hanno un DDT e abilita gli altri filtri
		-- sul DDT, che senza di esso vengono ignorati. Mittente, destinatario e trasportatore sono
		-- testo libero cercato ("contiene") in nome + indirizzo dell'anagrafica, come nelle select del DDT.
		SET @ConDdt = ISNULL(@ConDdt, 0);
		SET @DdtNumeroFornitore = NULLIF(LTRIM(RTRIM(@DdtNumeroFornitore)), '');
		SET @DdtMittente = NULLIF(LTRIM(RTRIM(@DdtMittente)), '');
		SET @DdtDestinatario = NULLIF(LTRIM(RTRIM(@DdtDestinatario)), '');
		SET @DdtTrasportatore = NULLIF(LTRIM(RTRIM(@DdtTrasportatore)), '');
		IF @ConDdt = 0
		BEGIN
			SET @DdtNumero = NULL;
			SET @DdtNumeroFornitore = NULL;
			SET @DdtMittente = NULL;
			SET @DdtDestinatario = NULL;
			SET @DdtTrasportatore = NULL;
		END

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			m.Id,
			StatoValore = 0,
			StatoDescrizione = 'OK',
			OperazioneNome = o.Nome,
			m.Data,
			m.Numero,
			RigheCount = ISNULL(r.RigheCount, 0) + ISNULL(re.RigheCount, 0),
			-- DDT del movimento (al massimo uno, garantito in SP: nessun vincolo UNIQUE); NULL se non c'è
			DdtNumero = d.Numero,
			DdtSezionale = d.Sezionale,
			DdtData = d.[Data],
			DdtSedeNome = d.SedeNome,
			m.Lock,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblMagazziniMovimenti m
			INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblMagazziniOperazioni o ON m.IdOperazione = o.Id
			OUTER APPLY (SELECT RigheCount = COUNT(*) FROM dbo.tblMagazziniMovimentiRighe WHERE IdMovimento = m.Id) r
			OUTER APPLY (SELECT RigheCount = COUNT(*) FROM dbo.tblMagazziniMovimentiRigheEoW WHERE IdMovimento = m.Id) re
			OUTER APPLY (
				SELECT TOP (1)
					dd.Id,
					dd.Numero,
					dd.NumeroFornitore,
					dd.Sezionale,
					dd.[Data],
					dd.IdMittente,
					dd.IdDestinatario,
					dd.IdTrasportatore,
					SedeNome = sd.NomeCompleto + ISNULL(' ' + sd.IndirizzoCompleto, '')
				FROM
					dbo.tblMagazziniDdt dd
					LEFT JOIN dbo.tblSedi sd ON dd.IdSede = sd.Id
				WHERE dd.IdMovimento = m.Id
				ORDER BY dd.Id
			) d
		WHERE
			e.Id = @IdSessione
			AND m.Lock = 0
			AND (@IdOperazione IS NULL OR m.IdOperazione = @IdOperazione)
			AND (@DallaData IS NULL OR m.[Data] >= @DallaData)
			AND (@AllaData IS NULL OR m.[Data] <= @AllaData)
			AND (@ConDdt = 0 OR d.Id IS NOT NULL)
			AND (@DdtNumero IS NULL OR d.Numero = @DdtNumero)
			AND (@DdtNumeroFornitore IS NULL OR d.NumeroFornitore LIKE '%' + @DdtNumeroFornitore + '%')
			AND (@DdtMittente IS NULL OR EXISTS (SELECT 1 FROM dbo.tblSedi sm WHERE sm.Id = d.IdMittente AND sm.NomeCompleto + ISNULL(' ' + sm.IndirizzoCompleto, '') LIKE '%' + @DdtMittente + '%'))
			AND (@DdtDestinatario IS NULL OR EXISTS (SELECT 1 FROM dbo.tblSedi sn WHERE sn.Id = d.IdDestinatario AND sn.NomeCompleto + ISNULL(' ' + sn.IndirizzoCompleto, '') LIKE '%' + @DdtDestinatario + '%'))
			AND (@DdtTrasportatore IS NULL OR EXISTS (SELECT 1 FROM dbo.tblSedi st WHERE st.Id = d.IdTrasportatore AND st.NomeCompleto + ISNULL(' ' + st.IndirizzoCompleto, '') LIKE '%' + @DdtTrasportatore + '%'))
		ORDER BY m.Data DESC, m.Numero DESC
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspMagazziniMovimenti_get_SediInterneSelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimenti_get_SediInterneSelectList
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Sedi della stessa azienda interna della sessione (l'azienda stessa e le sue sedi
		-- figlie): usata per scegliere la Sede interna del DDT prima che il Movimento esista,
		-- pertanto non richiede @IdMovimento a differenza di uspMagazziniMovimentiRighe_get_SediSelectList
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda FROM dbo.tblSessioni WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SELECT TOP (0) Id = CAST(NULL AS CHAR(16)), [Text] = CAST(NULL AS VARCHAR(401)), Selected = CAST(0 AS BIT);
			GOTO BRANCH_END;
		END

		SELECT TOP (50)
			s.Id,
			[Text] = s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, ''),
			Selected = CAST(IIF(s.Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblSedi s
		WHERE
			(s.Id = @idAzienda OR s.IdParent = @idAzienda)
			AND ISNULL(s.Disabilitata, 0) = 0
			AND (@Search IS NULL OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%')
		ORDER BY s.NomeCompleto
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
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspMagazziniDdt_get';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniDdt_get
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMovimento non può essere vuoto';
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
			@IdFunzione = 'MAG',
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
				dbo.tblMagazziniMovimenti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @IdMovimento
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			d.Id,
			d.IdMovimento,
			d.IdSede,
			-- Nome + indirizzo, come nelle select delle anagrafiche (uspMagazziniDdt_get_SediSelectList)
			SedeNome = si.NomeCompleto + ISNULL(' ' + si.IndirizzoCompleto, ''),
			d.IdCausale,
			CausaleNome = c.Nome,
			d.Numero,
			d.NumeroFornitore,
			d.Sezionale,
			d.Data,
			d.IdMittente,
			MittenteNome = sm.NomeCompleto + ISNULL(' ' + sm.IndirizzoCompleto, ''),
			d.IdDestinatario,
			DestinatarioNome = sd.NomeCompleto + ISNULL(' ' + sd.IndirizzoCompleto, ''),
			d.IdTrasportatore,
			TrasportatoreNome = st.NomeCompleto + ISNULL(' ' + st.IndirizzoCompleto, ''),
			d.DataInizioTrasporto,
			d.Peso,
			d.Lock
		FROM
			dbo.tblMagazziniDdt d
			LEFT JOIN dbo.tblSedi si ON d.IdSede = si.Id
			LEFT JOIN dbo.tblMagazziniCausali c ON d.IdCausale = c.Id
			LEFT JOIN dbo.tblSedi sm ON d.IdMittente = sm.Id
			LEFT JOIN dbo.tblSedi sd ON d.IdDestinatario = sd.Id
			LEFT JOIN dbo.tblSedi st ON d.IdTrasportatore = st.Id
		WHERE
			d.IdMovimento = @IdMovimento
			AND d.Lock <= 2;

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

PRINT 'uspMagazziniMovimenti_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimenti_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Data DATE = NULL,
	@Numero INT = NULL,
	@DdtIdCausale CHAR(1) = NULL,
	@DdtNumeroFornitore VARCHAR(20) = NULL,
	@DdtSezionale CHAR(1) = NULL,
	@DdtData DATE = NULL,
	@DdtIdMittente CHAR(16) = NULL,
	@DdtIdDestinatario CHAR(16) = NULL,
	@DdtIdTrasportatore CHAR(16) = NULL,
	@DdtDataInizioTrasporto SMALLDATETIME = NULL,
	@DdtPeso DECIMAL(18, 2) = NULL,
	@DdtNumero INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @confermato BIT = 0;

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
		IF @Numero IS NOT NULL AND @Numero <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione.
		-- Come le Registrazioni Rifiuti (uspRifiutiRegistrazioni_upd): "Salva" conferma sempre
		-- il movimento (Lock 2->0) oppure si blocca con un errore, e un movimento già
		-- confermato (Lock = 0) si può risalvare modificando anche data e numero (l'operazione
		-- resta quella fissata alla creazione), con i controlli cronologici sulle relazioni.
		DECLARE @idAzienda CHAR(16), @idOperazione CHAR(1), @lockMovimento INT, @dataPrecedente DATE, @numeroPrecedente INT;
		SELECT
			@idAzienda = c.IdSede,
			@idOperazione = c.IdOperazione,
			@lockMovimento = c.Lock,
			@dataPrecedente = c.[Data],
			@numeroPrecedente = c.Numero
		FROM
			dbo.tblMagazziniMovimenti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF @lockMovimento NOT IN (0, 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Movimento non trovato o già eliminato';
			GOTO BRANCH_END;
		END
		IF @Data IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data del movimento';
			GOTO BRANCH_END;
		END
		-- Le righe descrittive del DDT (senza articolo) non bastano: serve almeno una riga di merce
		IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE IdMovimento = @Id AND IdArticolo IS NOT NULL)
			AND NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheEoW WHERE IdMovimento = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Aggiungere almeno una riga';
			GOTO BRANCH_END;
		END

		-- Movimento già confermato con data o numero modificati: le relazioni carico/scarico
		-- vanno ricontrollate/ricostruite rispetto alla nuova posizione cronologica
		DECLARE @dataNumeroModificati BIT = IIF(
			@lockMovimento = 0
			AND (@Data <> @dataPrecedente OR ISNULL(@Numero, -1) <> ISNULL(@numeroPrecedente, -1)), 1, 0);

		BEGIN TRANSACTION;

			-- Data/Numero: il numero digitato dall'utente viene validato/rinumerato più sotto,
			-- dopo le relazioni. IdOperazione è fissato alla creazione
			-- (uspMagazziniMovimenti_ins) e non è più modificabile.
			UPDATE dbo.tblMagazziniMovimenti
			SET
				Data = @Data,
				Numero = @Numero
			WHERE
				Id = @Id
				AND Lock IN (0, 2);

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Movimento non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			-- DDT: se presente e ancora in bozza, viene confermato insieme al movimento (Lock
			-- 2->0, Numero assegnato) nello stesso click e nella stessa SP; se i campi
			-- obbligatori (Causale, Data, Destinatario) non sono completi il salvataggio si
			-- blocca con un errore (come le Registrazioni Rifiuti). Un DDT già confermato
			-- (Lock = 0) resta modificabile con gli stessi controlli, e in più se ne può
			-- cambiare il numero (@DdtNumero); la sede interna resta immutabile.
			DECLARE @idDdt CHAR(16), @idSedeDdt CHAR(16), @lockDdt INT;
			SELECT @idDdt = Id, @idSedeDdt = IdSede, @lockDdt = Lock
			FROM dbo.tblMagazziniDdt
			WHERE IdMovimento = @Id;

			IF @idDdt IS NOT NULL AND @lockDdt IN (0, 2)
			BEGIN
				SET @DdtIdCausale = NULLIF(LTRIM(RTRIM(@DdtIdCausale)), '');
				SET @DdtNumeroFornitore = dbo.ufnStringhe_get_SenzaSpazi(@DdtNumeroFornitore, 0, 1);
				SET @DdtSezionale = NULLIF(LTRIM(RTRIM(@DdtSezionale)), '');
				SET @DdtIdMittente = NULLIF(LTRIM(RTRIM(@DdtIdMittente)), '');
				SET @DdtIdDestinatario = NULLIF(LTRIM(RTRIM(@DdtIdDestinatario)), '');
				SET @DdtIdTrasportatore = NULLIF(LTRIM(RTRIM(@DdtIdTrasportatore)), '');

				-- DDT ricevuto (emesso da un fornitore esterno) = sezionale R, riservato: ammesso
				-- solo sui movimenti di carico e sempre con il numero del documento del fornitore;
				-- viceversa il numero fornitore esiste solo per i DDT ricevuti. Nessun controllo
				-- di univocità sul numero fornitore (scelta esplicita).
				IF @DdtSezionale = 'R'
					AND NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimenti WHERE Id = @Id AND IdOperazione = 'C')
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il sezionale R è riservato ai DDT ricevuti, ammessi solo sui movimenti di carico';
					GOTO BRANCH_END;
				END
				IF @DdtSezionale = 'R' AND @DdtNumeroFornitore IS NULL
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Indicare il numero fornitore del DDT ricevuto';
					GOTO BRANCH_END;
				END
				IF @DdtNumeroFornitore IS NOT NULL AND ISNULL(@DdtSezionale, '') <> 'R'
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il numero fornitore si indica solo per i DDT ricevuti';
					GOTO BRANCH_END;
				END

				IF @DdtIdCausale IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniCausali WHERE Id = @DdtIdCausale)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Causale del DDT non valida';
					GOTO BRANCH_END;
				END
				IF @DdtPeso IS NOT NULL AND @DdtPeso <= 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il peso del DDT deve essere maggiore di zero';
					GOTO BRANCH_END;
				END
				-- IdMittente è un campo libero della testata (valore stampato sul documento,
				-- l'utente lo compila a piacimento): nessuna relazione con la sede interna
				IF @DdtIdMittente IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @DdtIdMittente)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il mittente del DDT indicato non esiste';
					GOTO BRANCH_END;
				END
				IF @DdtIdDestinatario IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @DdtIdDestinatario)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il destinatario del DDT indicato non esiste';
					GOTO BRANCH_END;
				END
				IF @DdtIdTrasportatore IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @DdtIdTrasportatore)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il trasportatore del DDT indicato non esiste';
					GOTO BRANCH_END;
				END

				IF @DdtIdCausale IS NULL
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Selezionare la causale del DDT';
					GOTO BRANCH_END;
				END
				IF @DdtData IS NULL
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Indicare la data del DDT';
					GOTO BRANCH_END;
				END
				IF @DdtIdDestinatario IS NULL
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Selezionare il destinatario del DDT';
					GOTO BRANCH_END;
				END

				-- Numerazione indipendente per sede interna + sezionale, calcolata dentro
				-- la transazione con lock di riga per evitare duplicati in caso di
				-- richieste concorrenti sulla stessa sede/sezionale
				DECLARE @numeroDdt INT;
				IF @lockDdt = 2
				BEGIN
					-- DDT in bozza: numero assegnato qui, progressivo della serie
					SELECT @numeroDdt = ISNULL(MAX(Numero), 0) + 1
					FROM dbo.tblMagazziniDdt WITH (UPDLOCK, HOLDLOCK)
					WHERE
						IdSede = @idSedeDdt
						AND (Sezionale = @DdtSezionale OR (Sezionale IS NULL AND @DdtSezionale IS NULL))
						AND Id <> @idDdt;
				END
				ELSE
				BEGIN
					-- DDT già confermato: numero indicato dall'utente, unico nella serie (sede
					-- interna + sezionale) tra i DDT confermati. Nessuna rinumerazione automatica
					-- degli altri DDT: sono documenti già emessi.
					IF @DdtNumero IS NULL OR @DdtNumero < 1
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Indicare il numero del DDT';
						GOTO BRANCH_END;
					END
					IF EXISTS (
						SELECT 1
						FROM dbo.tblMagazziniDdt WITH (UPDLOCK, HOLDLOCK)
						WHERE
							IdSede = @idSedeDdt
							AND (Sezionale = @DdtSezionale OR (Sezionale IS NULL AND @DdtSezionale IS NULL))
							AND Numero = @DdtNumero
							AND Lock = 0
							AND Id <> @idDdt
					)
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Un altro DDT della stessa sede e dello stesso sezionale ha già il numero ' + CAST(@DdtNumero AS VARCHAR(10));
						GOTO BRANCH_END;
					END
					SET @numeroDdt = @DdtNumero;
				END

				UPDATE dbo.tblMagazziniDdt
				SET
					Lock = 0,
					IdCausale = @DdtIdCausale,
					Numero = @numeroDdt,
					NumeroFornitore = @DdtNumeroFornitore,
					Sezionale = @DdtSezionale,
					Data = @DdtData,
					IdMittente = @DdtIdMittente,
					IdDestinatario = @DdtIdDestinatario,
					IdTrasportatore = @DdtIdTrasportatore,
					DataInizioTrasporto = @DdtDataInizioTrasporto,
					Peso = @DdtPeso
				WHERE Id = @idDdt;
			END

			-- Relazioni carico/scarico delle righe tradizionali (stessa logica di
			-- uspRifiutiRegistrazioni_upd): la riga di carico è essa stessa la giacenza, la
			-- riga di scarico si relaziona alle righe di carico che consuma. L'unica variante
			-- è l'ordine di consumo, dato dal criterio di scarico della riga:
			--   M (Manuale) solo i carichi del lotto scelto sulla riga, dal più vecchio;
			--   F (FIFO per lotto) lotti per data di apertura crescente, poi carichi dal più vecchio;
			--   L (LIFO per lotto) lotti per data di apertura decrescente, poi carichi dal più recente;
			--   E (FEFO) lotti per scadenza (DataChiusura) crescente, poi carichi dal più vecchio;
			--   V (FIFO per carico) carichi per data/numero crescenti;
			--   R (LIFO per carico) carichi per data/numero decrescenti.
			-- Carichi candidati: stessa Sede+Articolo, movimento di carico confermato,
			-- cronologicamente precedente allo scarico (a parità di data, numero inferiore;
			-- scarico non ancora numerato = dopo tutti i confermati), residuo > 0. Il residuo
			-- di un carico è la sua quantità meno le relazioni di scarichi non eliminati.
			-- Si ricostruiscono tutte le righe in bozza o se sono cambiati data/numero di un
			-- movimento confermato; altrimenti, sul confermato, solo le righe non ancora
			-- completamente relazionate (le altre sono storia consolidata).
			IF @idOperazione = 'S'
			BEGIN
				DECLARE
					@idRiga CHAR(16),
					@idSedeRiga CHAR(16),
					@idArticoloRiga CHAR(16),
					@idCriterioRiga CHAR(1),
					@idLottoRiga CHAR(16),
					@quantitaRiga DECIMAL(18, 2),
					@articoloNome VARCHAR(50),
					@lottoNome VARCHAR(50),
					@isNumero BIT,
					@daRelazionare DECIMAL(18, 2),
					@idCarico CHAR(16),
					@residuoCarico DECIMAL(18, 2),
					@quotaCarico DECIMAL(18, 2),
					@rowNum INT,
					@maxRow INT;

				CREATE TABLE #Candidati (
					RowNum INT IDENTITY(1, 1) PRIMARY KEY,
					IdCarico CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
					Residuo DECIMAL(18, 2) NOT NULL
				);

				DECLARE cRighe CURSOR LOCAL FAST_FORWARD FOR
					SELECT
						r.Id,
						r.IdSede,
						r.IdArticolo,
						r.IdCriterio,
						r.IdLotto,
						r.Quantita,
						a.Nome,
						lr.Nome,
						CAST(IIF(a.IdUnitaMisura = 'NR', 1, 0) AS BIT)
					FROM
						dbo.tblMagazziniMovimentiRighe r
						LEFT JOIN dbo.tblMagazziniArticoli a ON r.IdArticolo = a.Id
						LEFT JOIN dbo.tblMagazziniLotti lr ON r.IdLotto = lr.Id
						OUTER APPLY (SELECT Relazionata = SUM(rel.Quantita) FROM dbo.tblMagazziniMovimentiRigheRelazioni rel WHERE rel.IdParent = r.Id) q
					WHERE
						r.IdMovimento = @Id
						-- Le righe descrittive del DDT (senza articolo) non scaricano nulla
						AND r.IdArticolo IS NOT NULL
						AND (@lockMovimento = 2 OR @dataNumeroModificati = 1 OR ISNULL(q.Relazionata, 0) <> r.Quantita)
					ORDER BY r.Id;

				OPEN cRighe;
				FETCH cRighe INTO @idRiga, @idSedeRiga, @idArticoloRiga, @idCriterioRiga, @idLottoRiga, @quantitaRiga, @articoloNome, @lottoNome, @isNumero;

				WHILE @@FETCH_STATUS = 0
				BEGIN
					IF @idCriterioRiga IS NULL
					BEGIN
						CLOSE cRighe;
						DEALLOCATE cRighe;
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Selezionare il criterio di scarico della riga dell''articolo ' + ISNULL(@articoloNome, '');
						GOTO BRANCH_END;
					END
					IF @idCriterioRiga = 'M' AND @idLottoRiga IS NULL
					BEGIN
						CLOSE cRighe;
						DEALLOCATE cRighe;
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Selezionare il lotto da cui scaricare la riga dell''articolo ' + ISNULL(@articoloNome, '');
						GOTO BRANCH_END;
					END

					-- Relazioni ricostruite da zero nell'ordine del criterio. Lock di riga
					-- (UPDLOCK/HOLDLOCK) sulle relazioni dei carichi candidati, per serializzare
					-- scarichi concorrenti sugli stessi carichi.
					TRUNCATE TABLE #Candidati;

					DELETE dbo.tblMagazziniMovimentiRigheRelazioni
					WHERE IdParent = @idRiga;

					INSERT INTO #Candidati (IdCarico, Residuo)
					SELECT
						rc.Id,
						rc.Quantita - ISNULL(c.Consumata, 0)
					FROM
						dbo.tblMagazziniMovimentiRighe rc
						INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
						LEFT JOIN dbo.tblMagazziniLotti l ON rc.IdLotto = l.Id
						OUTER APPLY (
							SELECT Consumata = SUM(rel.Quantita)
							FROM
								dbo.tblMagazziniMovimentiRigheRelazioni rel WITH (UPDLOCK, HOLDLOCK)
								INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
								INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
							WHERE
								rel.Id = rc.Id
								AND mp.Lock IN (0, 2)
						) c
					WHERE
						mc.IdOperazione = 'C'
						AND mc.Lock = 0
						AND rc.Lock = 0
						AND rc.IdSede = @idSedeRiga
						AND rc.IdArticolo = @idArticoloRiga
						AND (@idCriterioRiga <> 'M' OR rc.IdLotto = @idLottoRiga)
						AND (
							mc.[Data] < @Data
							OR (mc.[Data] = @Data AND (@Numero IS NULL OR mc.Numero < @Numero))
						)
						AND rc.Quantita - ISNULL(c.Consumata, 0) > 0
					ORDER BY
						CASE WHEN @idCriterioRiga = 'F' THEN l.DataApertura END ASC,
						CASE WHEN @idCriterioRiga = 'L' THEN l.DataApertura END DESC,
						CASE WHEN @idCriterioRiga = 'E' THEN ISNULL(l.DataChiusura, '9999-12-31') END ASC,
						CASE WHEN @idCriterioRiga IN ('L', 'R') THEN mc.[Data] END DESC,
						CASE WHEN @idCriterioRiga IN ('L', 'R') THEN mc.Numero END DESC,
						mc.[Data] ASC,
						mc.Numero ASC,
						rc.Id;

					-- Distribuzione greedy, carico per carico, fino al residuo di ciascuno
					SET @daRelazionare = @quantitaRiga;
					SET @rowNum = 1;
					SET @maxRow = ISNULL((SELECT MAX(RowNum) FROM #Candidati), 0);

					WHILE @daRelazionare > 0 AND @rowNum <= @maxRow
					BEGIN
						SELECT @idCarico = IdCarico, @residuoCarico = Residuo FROM #Candidati WHERE RowNum = @rowNum;
						SET @quotaCarico = IIF(@residuoCarico < @daRelazionare, @residuoCarico, @daRelazionare);

						IF @quotaCarico > 0
						BEGIN
							INSERT dbo.tblMagazziniMovimentiRigheRelazioni (Id, IdParent, Quantita, Pos)
							VALUES (@idCarico, @idRiga, @quotaCarico, @rowNum - 1);

							SET @daRelazionare = @daRelazionare - @quotaCarico;
						END

						SET @rowNum = @rowNum + 1;
					END

					IF @daRelazionare > 0
					BEGIN
						CLOSE cRighe;
						DEALLOCATE cRighe;
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage =
							'Giacenza insufficiente '
							+ IIF(@idCriterioRiga = 'M', 'nel lotto ' + ISNULL(@lottoNome, '') + ' ', '')
							+ 'per l''articolo ' + ISNULL(@articoloNome, '')
							+ ' (mancano ' + FORMAT(@daRelazionare, IIF(@isNumero = 1, 'N0', 'N2'), 'it-IT') + ')';
						GOTO BRANCH_END;
					END

					FETCH cRighe INTO @idRiga, @idSedeRiga, @idArticoloRiga, @idCriterioRiga, @idLottoRiga, @quantitaRiga, @articoloNome, @lottoNome, @isNumero;
				END

				CLOSE cRighe;
				DEALLOCATE cRighe;
			END

			-- Relazioni delle righe EoW (stessa logica delle righe tradizionali): per l'EoW il
			-- "carico" è il lotto EoW, alimentato dalle quote delle registrazioni rifiuti M
			-- (tblEoWLottiRifiutiRegistrazioni); la riga EoW di scarico si relaziona ai lotti EoW
			-- che consuma (tblMagazziniMovimentiRigheEoWLotti). Ordine di consumo dal criterio:
			--   M (Manuale) solo il lotto EoW scelto sulla riga;
			--   F (FIFO) lotti per data di apertura crescente; L (LIFO) decrescente;
			--   E (FEFO) lotti per scadenza (DataChiusura) crescente.
			-- Lotti candidati: stessa Sede+Materiale, attivi, non disabilitati. Disponibile alla
			-- data dello scarico = quote di registrazioni M attive con data <= data dello scarico
			-- (non si scarica materiale non ancora prodotto a quella data) meno quanto già
			-- scaricato dal lotto da scarichi non eliminati.
			DECLARE
				@idRigaEoW CHAR(16),
				@idSedeRigaEoW CHAR(16),
				@idMaterialeRigaEoW CHAR(2),
				@idCriterioRigaEoW CHAR(1),
				@idLottoRigaEoW CHAR(16),
				@quantitaRigaEoW DECIMAL(18, 2),
				@materialeNome VARCHAR(100),
				@lottoEoWNome VARCHAR(50),
				@daRelazionareEoW DECIMAL(18, 2),
				@idLottoEoW CHAR(16),
				@residuoLottoEoW DECIMAL(18, 2),
				@quotaLottoEoW DECIMAL(18, 2),
				@rowNumEoW INT,
				@maxRowEoW INT;

			CREATE TABLE #CandidatiEoW (
				RowNum INT IDENTITY(1, 1) PRIMARY KEY,
				IdLotto CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
				Residuo DECIMAL(18, 2) NOT NULL
			);

			DECLARE cRigheEoW CURSOR LOCAL FAST_FORWARD FOR
				SELECT
					r.Id,
					r.IdSede,
					r.IdMateriale,
					r.IdCriterio,
					r.IdLotto,
					r.Quantita,
					m.Nome,
					lr.Nome
				FROM
					dbo.tblMagazziniMovimentiRigheEoW r
					LEFT JOIN dbo.tblRifiutiMateriali m ON r.IdMateriale = m.Id
					LEFT JOIN dbo.tblEoWLotti lr ON r.IdLotto = lr.Id
					OUTER APPLY (SELECT Relazionata = SUM(rl.Quantita) FROM dbo.tblMagazziniMovimentiRigheEoWLotti rl WHERE rl.Id = r.Id) q
				WHERE
					r.IdMovimento = @Id
					AND (@lockMovimento = 2 OR @dataNumeroModificati = 1 OR ISNULL(q.Relazionata, 0) <> r.Quantita)
				ORDER BY r.Id;

			OPEN cRigheEoW;
			FETCH cRigheEoW INTO @idRigaEoW, @idSedeRigaEoW, @idMaterialeRigaEoW, @idCriterioRigaEoW, @idLottoRigaEoW, @quantitaRigaEoW, @materialeNome, @lottoEoWNome;

			WHILE @@FETCH_STATUS = 0
			BEGIN
				IF @idCriterioRigaEoW IS NULL
				BEGIN
					CLOSE cRigheEoW;
					DEALLOCATE cRigheEoW;
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Selezionare il criterio di scarico della riga del materiale ' + ISNULL(@materialeNome, '');
					GOTO BRANCH_END;
				END
				IF @idCriterioRigaEoW NOT IN ('M', 'F', 'L', 'E')
				BEGIN
					CLOSE cRigheEoW;
					DEALLOCATE cRigheEoW;
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Criterio di scarico non valido per la riga del materiale ' + ISNULL(@materialeNome, '');
					GOTO BRANCH_END;
				END
				IF @idCriterioRigaEoW = 'M' AND @idLottoRigaEoW IS NULL
				BEGIN
					CLOSE cRigheEoW;
					DEALLOCATE cRigheEoW;
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Selezionare il lotto EoW da cui scaricare la riga del materiale ' + ISNULL(@materialeNome, '');
					GOTO BRANCH_END;
				END

				-- Relazioni ricostruite da zero nell'ordine del criterio. Lock di riga
				-- (UPDLOCK/HOLDLOCK) sulle relazioni dei lotti candidati, per serializzare
				-- scarichi concorrenti sugli stessi lotti EoW.
				TRUNCATE TABLE #CandidatiEoW;

				DELETE dbo.tblMagazziniMovimentiRigheEoWLotti
				WHERE Id = @idRigaEoW;

				INSERT INTO #CandidatiEoW (IdLotto, Residuo)
				SELECT
					l.Id,
					ISNULL(p.Prodotta, 0) - ISNULL(sc.Scaricata, 0)
				FROM
					dbo.tblEoWLotti l
					OUTER APPLY (
						SELECT Prodotta = SUM(qp.Quantita)
						FROM
							dbo.tblEoWLottiRifiutiRegistrazioni qp
							INNER JOIN dbo.tblRifiutiRegistrazioni rr ON qp.IdRegistrazione = rr.Id
						WHERE
							qp.IdLotto = l.Id
							AND rr.Lock < 2
							AND rr.[Data] <= @Data
					) p
					OUTER APPLY (
						SELECT Scaricata = SUM(rs.Quantita)
						FROM
							dbo.tblMagazziniMovimentiRigheEoWLotti rs WITH (UPDLOCK, HOLDLOCK)
							INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rp ON rs.Id = rp.Id
							INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
						WHERE
							rs.IdLotto = l.Id
							AND mp.Lock IN (0, 2)
					) sc
				WHERE
					l.IdSede = @idSedeRigaEoW
					AND l.IdMateriale = @idMaterialeRigaEoW
					AND l.Lock = 0
					AND ISNULL(l.Disabilitato, 0) = 0
					AND (@idCriterioRigaEoW <> 'M' OR l.Id = @idLottoRigaEoW)
					AND ISNULL(p.Prodotta, 0) - ISNULL(sc.Scaricata, 0) > 0
				ORDER BY
					CASE WHEN @idCriterioRigaEoW = 'L' THEN l.DataApertura END DESC,
					CASE WHEN @idCriterioRigaEoW = 'E' THEN ISNULL(l.DataChiusura, '9999-12-31') END ASC,
					l.DataApertura ASC,
					l.Id;

				-- Distribuzione greedy, lotto per lotto, fino al disponibile di ciascuno
				SET @daRelazionareEoW = @quantitaRigaEoW;
				SET @rowNumEoW = 1;
				SET @maxRowEoW = ISNULL((SELECT MAX(RowNum) FROM #CandidatiEoW), 0);

				WHILE @daRelazionareEoW > 0 AND @rowNumEoW <= @maxRowEoW
				BEGIN
					SELECT @idLottoEoW = IdLotto, @residuoLottoEoW = Residuo FROM #CandidatiEoW WHERE RowNum = @rowNumEoW;
					SET @quotaLottoEoW = IIF(@residuoLottoEoW < @daRelazionareEoW, @residuoLottoEoW, @daRelazionareEoW);

					IF @quotaLottoEoW > 0
					BEGIN
						INSERT dbo.tblMagazziniMovimentiRigheEoWLotti (Id, IdLotto, Quantita, Pos)
						VALUES (@idRigaEoW, @idLottoEoW, @quotaLottoEoW, @rowNumEoW - 1);

						SET @daRelazionareEoW = @daRelazionareEoW - @quotaLottoEoW;
					END

					SET @rowNumEoW = @rowNumEoW + 1;
				END

				IF @daRelazionareEoW > 0
				BEGIN
					CLOSE cRigheEoW;
					DEALLOCATE cRigheEoW;
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage =
						'Giacenza insufficiente '
						+ IIF(@idCriterioRigaEoW = 'M', 'nel lotto EoW ' + ISNULL(@lottoEoWNome, '') + ' ', '')
						+ 'per il materiale ' + ISNULL(@materialeNome, '')
						+ ' (mancano ' + FORMAT(@daRelazionareEoW, 'N2', 'it-IT') + ')';
					GOTO BRANCH_END;
				END

				FETCH cRigheEoW INTO @idRigaEoW, @idSedeRigaEoW, @idMaterialeRigaEoW, @idCriterioRigaEoW, @idLottoRigaEoW, @quantitaRigaEoW, @materialeNome, @lottoEoWNome;
			END

			CLOSE cRigheEoW;
			DEALLOCATE cRigheEoW;

			-- Conferma (o riconferma) del movimento: "Salva" conferma sempre, come le
			-- Registrazioni Rifiuti; ogni condizione non soddisfatta ha già bloccato sopra
			BEGIN
				-- Numerazione: progressivo annuale per Azienda + anno di Data, tra i soli
				-- movimenti già confermati (Lock = 0). UPDLOCK/HOLDLOCK per serializzare
				-- conferme concorrenti nello stesso anno/azienda.
				DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@Data), 1, 1);
				DECLARE @annoFine DATE = DATEADD(YEAR, 1, @annoInizio);

				IF @Numero IS NULL
				BEGIN
					SELECT @Numero = ISNULL(MAX(Numero), 0) + 1
					FROM dbo.tblMagazziniMovimenti WITH (UPDLOCK, HOLDLOCK)
					WHERE
						IdSede = @idAzienda
						AND Lock = 0
						AND Data >= @annoInizio
						AND Data < @annoFine;
				END
				ELSE
				BEGIN
					-- Collisione esatta con un altro movimento già confermato: rinumera (+1)
					-- tutti i movimenti con Numero >= quello scelto, nello stesso anno/azienda,
					-- per fare spazio - permette di riusare un "buco" lasciato da una
					-- cancellazione senza doverli spostare manualmente uno per uno.
					IF EXISTS (
						SELECT 1
						FROM dbo.tblMagazziniMovimenti WITH (UPDLOCK, HOLDLOCK)
						WHERE
							Id <> @Id
							AND IdSede = @idAzienda
							AND Lock = 0
							AND Data >= @annoInizio
							AND Data < @annoFine
							AND Numero = @Numero
					)
					BEGIN
						UPDATE dbo.tblMagazziniMovimenti
						SET Numero = Numero + 1
						WHERE
							Id <> @Id
							AND IdSede = @idAzienda
							AND Lock = 0
							AND Data >= @annoInizio
							AND Data < @annoFine
							AND Numero >= @Numero;
					END

					-- Coerenza cronologica: un movimento con Data precedente non può avere un
					-- numero maggiore o uguale, uno con Data successiva non può averne uno
					-- minore o uguale, nello stesso anno/azienda. Qui si blocca con un errore
					-- invece di tentare un riordino automatico più ampio, per non correggere
					-- inavvertitamente dati che potrebbero già essere corretti per altri motivi.
					IF EXISTS (
						SELECT 1
						FROM dbo.tblMagazziniMovimenti
						WHERE
							Id <> @Id
							AND IdSede = @idAzienda
							AND Lock = 0
							AND Data >= @annoInizio
							AND Data < @annoFine
							AND (
								(Data < @Data AND Numero >= @Numero)
								OR (Data > @Data AND Numero <= @Numero)
							)
					)
					BEGIN
						ROLLBACK TRANSACTION;
						SET @returnValue = -1;
						SET @returnMessage = 'Il numero indicato non è coerente con la data rispetto ad altri movimenti dello stesso anno';
						GOTO BRANCH_END;
					END
				END

				-- Carico già confermato spostato di data/numero: non può finire dopo gli scarichi
				-- (non eliminati) che ne consumano le righe (come il "Controllo data relazioni"
				-- delle Registrazioni Rifiuti)
				IF @idOperazione = 'C' AND @dataNumeroModificati = 1 AND EXISTS (
					SELECT 1
					FROM
						dbo.tblMagazziniMovimentiRighe rc
						INNER JOIN dbo.tblMagazziniMovimentiRigheRelazioni rel ON rel.Id = rc.Id
						INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
						INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
					WHERE
						rc.IdMovimento = @Id
						AND mp.Lock IN (0, 2)
						AND (
							mp.[Data] < @Data
							OR (mp.[Data] = @Data AND mp.Numero IS NOT NULL AND mp.Numero <= @Numero)
						)
				)
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Il carico è già utilizzato da scarichi con data e/o numero precedenti';
					GOTO BRANCH_END;
				END

				UPDATE dbo.tblMagazziniMovimenti
				SET
					Lock = 0,
					Numero = @Numero
				WHERE
					Id = @Id
					AND Lock IN (0, 2);

				UPDATE dbo.tblMagazziniMovimentiRighe
				SET Lock = 0
				WHERE IdMovimento = @Id;

				UPDATE dbo.tblMagazziniMovimentiRigheEoW
				SET Lock = 0
				WHERE IdMovimento = @Id;

				SET @confermato = IIF(@lockMovimento = 2, 1, 0);
			END

		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';
		IF @idDdt IS NOT NULL
			EXEC dbo.uspId_upd @Id = @idDdt, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue, Confermato = @confermato, Numero = @Numero;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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

PRINT 'uspMagazziniLotti_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniLotti_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdArticolo CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@DataApertura DATE = NULL,
	@DataChiusura DATE = NULL,
	@QuantitaMax DECIMAL(18, 2) = NULL,
	@Disabilitato BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdArticolo = NULLIF(LTRIM(RTRIM(@IdArticolo)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Disabilitato = ISNULL(@Disabilitato, 0);

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
		IF @IdArticolo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''articolo';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il nome';
			GOTO BRANCH_END;
		END
		IF @DataApertura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data di apertura';
			GOTO BRANCH_END;
		END
		IF @DataChiusura IS NOT NULL AND @DataChiusura < @DataApertura
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di chiusura non può essere precedente alla data di apertura';
			GOTO BRANCH_END;
		END
		IF @QuantitaMax IS NOT NULL AND @QuantitaMax <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità massima deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MGC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede reale del lotto
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblMagazziniLotti c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'articolo deve esistere, essere attivo, e appartenere alla stessa azienda della
		-- sede del lotto (Sede = Azienda stessa, oppure Sede.IdParent = Azienda dell'articolo)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniArticoli art
				INNER JOIN dbo.tblSedi s ON s.Id = @idSede
			WHERE
				art.Id = @IdArticolo
				AND art.Lock = 0
				AND (art.IdSede = @idSede OR art.IdSede = s.IdParent)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''articolo selezionato non appartiene all''azienda della sede del lotto';
			GOTO BRANCH_END;
		END

		-- Non è possibile cambiare l'articolo se il lotto ha già ripartizioni associate
		IF EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniLotti
			WHERE
				Id = @Id
				AND Lock = 0
				AND IdArticolo <> @IdArticolo
				AND EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE IdLotto = @Id)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare l''articolo di un lotto con movimenti associati';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro lotto attivo con lo stesso nome nella stessa sede
		IF EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniLotti
			WHERE
				Id <> @Id
				AND IdSede = @idSede
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro lotto con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblMagazziniLotti
			SET
				Lock = 0,
				IdArticolo = @IdArticolo,
				Nome = @Nome,
				DataApertura = @DataApertura,
				DataChiusura = @DataChiusura,
				QuantitaMax = @QuantitaMax,
				Disabilitato = @Disabilitato
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Lotto non trovato o già eliminato';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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

PRINT 'uspMagazziniMovimentiRighe_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRighe_get_List
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMovimento non può essere vuoto';
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
			@IdFunzione = 'MAG',
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
				dbo.tblMagazziniMovimenti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @IdMovimento
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			r.Id,
			r.IdSede,
			SedeNome = s.Nome,
			r.IdArticolo,
			ArticoloNome = a.Nome,
			UnitaMisuraNome = u.Nome,
			r.IdCriterio,
			CriterioNome = cr.Nome,
			r.Quantita,
			-- Riga di scarico: quantità già relazionata alle righe di carico consumate
			-- (le righe di carico non hanno relazioni proprie, sono esse stesse la giacenza)
			Relazionata = ISNULL(q.Relazionata, 0),
			-- Numero di carichi (righe di carico) da cui la riga ha scaricato: le righe della modale "Carichi"
			CarichiNumero = ISNULL(q.CarichiNumero, 0),
			r.IdLotto,
			LottoNome = l.Nome,
			IsNumero = CAST(IIF(a.IdUnitaMisura = 'NR', 1, 0) AS BIT),
			-- Riga di scarico di un movimento confermato: quantità residua (giacenza attuale)
			-- del lotto da cui la riga ha scaricato; se i carichi consumati appartengono a più
			-- lotti, somma dei residui con il dettaglio per lotto. NULL su movimento in bozza
			-- (residuo non ancora noto) e sulle righe di carico.
			ResiduoLotti = IIF(m.Lock = 0, z.ResiduoLotti, NULL),
			ResiduoLottiDettaglio = IIF(m.Lock = 0, z.ResiduoLottiDettaglio, NULL),
			r.IdImballo,
			ImballoNome = im.Nome,
			r.Colli,
			AllaRinfusa = ISNULL(r.AllaRinfusa, 0),
			-- Riga descrittiva del DDT: solo Descrizione, senza articolo, lotto, criterio e quantità
			r.Descrizione,
			r.Pos,
			r.Lock
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblMagazziniMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id
			LEFT JOIN dbo.tblMagazziniArticoli a ON r.IdArticolo = a.Id
			LEFT JOIN dbo.tblUnitaMisura u ON a.IdUnitaMisura = u.Id
			LEFT JOIN dbo.tblMagazziniCriteriScarichiLotti cr ON r.IdCriterio = cr.Id
			LEFT JOIN dbo.tblMagazziniLotti l ON r.IdLotto = l.Id
			LEFT JOIN dbo.tblImballi im ON r.IdImballo = im.Id
			OUTER APPLY (SELECT Relazionata = SUM(rel.Quantita), CarichiNumero = COUNT(*) FROM dbo.tblMagazziniMovimentiRigheRelazioni rel WHERE rel.IdParent = r.Id) q
			OUTER APPLY (
				SELECT
					ResiduoLotti = SUM(g.Giacenza),
					ResiduoLottiDettaglio = STRING_AGG(t.Testo, N' – ') WITHIN GROUP (ORDER BY g.Nome)
				FROM
					(
						SELECT DISTINCT rc.IdLotto
						FROM
							dbo.tblMagazziniMovimentiRigheRelazioni rel
							INNER JOIN dbo.tblMagazziniMovimentiRighe rc ON rel.Id = rc.Id
						WHERE rel.IdParent = r.Id
					) lu
					INNER JOIN dbo.tblMagazziniLotti lg ON lu.IdLotto = lg.Id
					-- Giacenza del lotto: righe di carico confermate meno relazioni di scarichi
					-- confermati (stesso calcolo di uspMagazziniLotti_get_List)
					CROSS APPLY (
						SELECT
							lg.Nome,
							Giacenza = ISNULL((
								SELECT SUM(rc2.Quantita)
								FROM
									dbo.tblMagazziniMovimentiRighe rc2
									INNER JOIN dbo.tblMagazziniMovimenti mc2 ON rc2.IdMovimento = mc2.Id
								WHERE
									rc2.IdLotto = lg.Id
									AND mc2.IdOperazione = 'C'
									AND rc2.Lock = 0
									AND mc2.Lock = 0
							), 0) - ISNULL((
								SELECT SUM(rel2.Quantita)
								FROM
									dbo.tblMagazziniMovimentiRigheRelazioni rel2
									INNER JOIN dbo.tblMagazziniMovimentiRighe rc3 ON rel2.Id = rc3.Id
									INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel2.IdParent = rp.Id
									INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
								WHERE
									rc3.IdLotto = lg.Id
									AND rp.Lock = 0
									AND mp.Lock = 0
							), 0)
					) g
					CROSS APPLY (SELECT Testo = CAST(g.Nome + ': ' + FORMAT(g.Giacenza, IIF(a.IdUnitaMisura = 'NR', 'N0', 'N2'), 'it-IT') AS NVARCHAR(MAX))) t
			) z
		WHERE r.IdMovimento = @IdMovimento
		-- Pos NULL (righe precedenti all'introduzione di Pos) per prime, in ordine di Id
		ORDER BY ISNULL(r.Pos, 0), r.Id
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspMagazziniMovimentiRigheEoW_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheEoW_get_List
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMovimento non può essere vuoto';
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
			@IdFunzione = 'MAG',
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
				dbo.tblMagazziniMovimenti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @IdMovimento
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			r.Id,
			r.IdSede,
			SedeNome = s.Nome,
			r.IdMateriale,
			MaterialeNome = m.Nome,
			r.IdCriterio,
			CriterioNome = cr.Nome,
			r.Quantita,
			-- Quantità già relazionata ai lotti EoW consumati (costruita in uspMagazziniMovimenti_upd)
			Relazionata = ISNULL(q.Relazionata, 0),
			-- Numero di lotti EoW da cui la riga ha scaricato: le righe della modale "Carichi"
			LottiNumero = ISNULL(q.LottiNumero, 0),
			r.IdLotto,
			LottoNome = lr.Nome,
			-- Movimento confermato: quantità residua (giacenza attuale) del lotto EoW da cui la
			-- riga ha scaricato; su più lotti somma dei residui con il dettaglio per lotto.
			-- NULL su movimento in bozza (residuo non ancora noto).
			ResiduoLotti = IIF(mv.Lock = 0, z.ResiduoLotti, NULL),
			ResiduoLottiDettaglio = IIF(mv.Lock = 0, z.ResiduoLottiDettaglio, NULL),
			-- Anomalia "Scaricato più del prodotto": almeno un lotto EoW da cui la riga ha scaricato ha
			-- giacenza negativa (il registro operativo gli attribuisce meno di quanto già scaricato; il
			-- magazzino EoW prevale, i movimenti non vengono corretti in automatico)
			IsScaricatoPiuDelProdotto = CAST(IIF(mv.Lock = 0 AND ISNULL(z.LottiAnomali, 0) > 0, 1, 0) AS BIT),
			r.IdImballo,
			ImballoNome = im.Nome,
			r.Colli,
			AllaRinfusa = ISNULL(r.AllaRinfusa, 0),
			r.Pos,
			r.Lock
		FROM
			dbo.tblMagazziniMovimentiRigheEoW r
			INNER JOIN dbo.tblMagazziniMovimenti mv ON r.IdMovimento = mv.Id
			INNER JOIN dbo.tblSedi s ON r.IdSede = s.Id
			LEFT JOIN dbo.tblRifiutiMateriali m ON r.IdMateriale = m.Id
			LEFT JOIN dbo.tblMagazziniCriteriScarichiLotti cr ON r.IdCriterio = cr.Id
			LEFT JOIN dbo.tblEoWLotti lr ON r.IdLotto = lr.Id
			LEFT JOIN dbo.tblImballi im ON r.IdImballo = im.Id
			OUTER APPLY (SELECT Relazionata = SUM(rl.Quantita), LottiNumero = COUNT(*)
			FROM dbo.tblMagazziniMovimentiRigheEoWLotti rl
			WHERE rl.Id = r.Id) q
			OUTER APPLY (
				SELECT
					ResiduoLotti = SUM(g.Giacenza),
					LottiAnomali = SUM(IIF(g.Giacenza < 0, 1, 0)),
					ResiduoLottiDettaglio = STRING_AGG(t.Testo, N' – ') WITHIN GROUP (ORDER BY g.Nome)
				FROM
					dbo.tblMagazziniMovimentiRigheEoWLotti rl
					INNER JOIN dbo.tblEoWLotti lg ON rl.IdLotto = lg.Id
					-- Giacenza del lotto EoW: quote di registrazioni M attive meno scarichi
					-- confermati di questo modulo
					CROSS APPLY (
						SELECT
							lg.Nome,
							Giacenza = ISNULL((
								SELECT SUM(qp.Quantita)
								FROM
									dbo.tblEoWLottiRifiutiRegistrazioni qp
									INNER JOIN dbo.tblRifiutiRegistrazioni rr ON qp.IdRegistrazione = rr.Id
								WHERE
									qp.IdLotto = lg.Id
									AND rr.Lock < 2
							), 0) - ISNULL((
								SELECT SUM(rs.Quantita)
								FROM
									dbo.tblMagazziniMovimentiRigheEoWLotti rs
									INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rp ON rs.Id = rp.Id
									INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
								WHERE
									rs.IdLotto = lg.Id
									AND rp.Lock = 0
									AND mp.Lock = 0
							), 0)
					) g
									CROSS APPLY (SELECT Testo = CAST(g.Nome + ': ' + FORMAT(g.Giacenza, 'N2', 'it-IT') AS NVARCHAR(MAX))) t
				WHERE rl.Id = r.Id) z
		WHERE r.IdMovimento = @IdMovimento
		-- Pos NULL (righe precedenti all'introduzione di Pos) per prime, in ordine di Id
		ORDER BY ISNULL(r.Pos, 0), r.Id
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspMagazziniMovimentiRigheEoW_ins';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheEoW_ins
	@IdMovimento CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@IdCriterio CHAR(1) = NULL,
	@Quantita DECIMAL(18, 2) = NULL,
	@IdLotto CHAR(16) = NULL,
	@IdImballo CHAR(2) = NULL,
	@Colli INT = NULL,
	@AllaRinfusa BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdMovimento = NULLIF(LTRIM(RTRIM(@IdMovimento)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @IdCriterio = NULLIF(LTRIM(RTRIM(@IdCriterio)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		-- Imballo: '00' è il segnaposto "(Selezionare)" di uspImballi_get_SelectList; alla
		-- rinfusa non c'è imballo (come nei Formulari)
		SET @IdImballo = NULLIF(NULLIF(LTRIM(RTRIM(@IdImballo)), ''), '00');
		SET @AllaRinfusa = ISNULL(@AllaRinfusa, 0);
		IF @AllaRinfusa = 1 SET @IdImballo = NULL;

		IF @IdMovimento IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMovimento non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la sede';
			GOTO BRANCH_END;
		END
		IF @IdMateriale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il materiale';
			GOTO BRANCH_END;
		END
		IF @Quantita IS NULL OR @Quantita <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare una quantità maggiore di zero';
			GOTO BRANCH_END;
		END
		IF @Colli < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero di colli non può essere negativo';
			GOTO BRANCH_END;
		END
		IF @IdImballo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblImballi WHERE Id = @IdImballo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''imballo indicato non esiste';
			GOTO BRANCH_END;
		END
		-- Criterio obbligatorio: M (Manuale, lotto EoW scelto sulla riga), F/L (data di apertura
		-- del lotto EoW), E (scadenza del lotto EoW). V/R (per singolo carico) non si applicano
		-- all'EoW: il "carico" è il lotto EoW stesso.
		IF @IdCriterio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il criterio di scarico';
			GOTO BRANCH_END;
		END
		IF @IdCriterio NOT IN ('M', 'F', 'L', 'E')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Criterio di scarico non valido per un materiale EoW';
			GOTO BRANCH_END;
		END
		IF @IdCriterio = 'M' AND @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con il criterio Manuale selezionare il lotto EoW da cui scaricare';
			GOTO BRANCH_END;
		END
		IF @IdCriterio <> 'M' AND @IdLotto IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto EoW si indica solo con il criterio Manuale';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- I moduli sono opzionali per dominio: righe di materiale EoW solo con il modulo
		-- Gestione EoW attivo
		IF dbo.ufnModuli_get_IsAttivoBySessione('EOW', @IdSessione) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il modulo EoW non è attivo sul dominio';
			GOTO BRANCH_END;
		END

		-- Il movimento deve esistere (bozza o già confermato, non eliminato) e
		-- appartenere all'azienda interna corrente della sessione. IdMovimento non
		-- ha FK verso tblMagazziniMovimenti sullo schema reale: la relazione va
		-- validata qui. La riga eredita il Lock del movimento (vedi Righe_ins).
		DECLARE @idAzienda CHAR(16), @idOperazione CHAR(1), @lockMovimento INT;
		SELECT
			@idAzienda = c.IdSede,
			@idOperazione = c.IdOperazione,
			@lockMovimento = c.Lock
		FROM
			dbo.tblMagazziniMovimenti c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @IdMovimento
			AND e.Id = @IdSessione
			AND c.Lock IN (0, 2);

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il movimento non esiste';
			GOTO BRANCH_END;
		END

		-- Il magazzino EoW si carica solo dal registro rifiuti (operazione M delle
		-- Registrazioni): un movimento di carico di magazzino non può avere righe EoW
		IF @idOperazione = 'C'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il magazzino EoW si carica solo dal registro rifiuti (operazione M)';
			GOTO BRANCH_END;
		END

		-- La sede della riga deve appartenere alla stessa azienda del movimento
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblSedi
			WHERE
				Id = @IdSede
				AND (Id = @idAzienda OR IdParent = @idAzienda)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede indicata non appartiene all''azienda del movimento';
			GOTO BRANCH_END;
		END

		-- Se il movimento ha un DDT associato, tutte le righe devono appartenere alla
		-- sola sede interna del DDT (IdSede, non IdMittente: quest'ultimo è un
		-- campo libero della testata, senza relazione con la sede operativa)
		IF EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniDdt
			WHERE
				IdMovimento = @IdMovimento
				AND IdSede <> @IdSede
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con un DDT associato, la riga deve appartenere alla sede interna del DDT';
			GOTO BRANCH_END;
		END

		-- Il materiale deve esistere in anagrafica (tblRifiutiMateriali, nessuna anagrafica
		-- EoW parallela - stessa convenzione già usata dal modulo EoW esistente)
		IF NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiMateriali WHERE Id = @IdMateriale)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il materiale indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Lotto EoW del criterio Manuale: stessa Sede+Materiale della riga, attivo, non
		-- disabilitato (anche se scaduto: si scarica da ciò che resta)
		IF @IdLotto IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti
			WHERE
				Id = @IdLotto
				AND IdSede = @IdSede
				AND IdMateriale = @IdMateriale
				AND Lock = 0
				AND ISNULL(Disabilitato, 0) = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto EoW selezionato non è valido per questa riga';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			-- Posizione: in coda alle righe del movimento, unica tra righe articolo/descrizione e righe EoW
			DECLARE @pos INT;
			SELECT @pos = ISNULL(MAX(x.Pos), 0) + 1
			FROM
				(
					SELECT Pos
					FROM dbo.tblMagazziniMovimentiRighe
					WHERE IdMovimento = @IdMovimento

					UNION ALL

					SELECT Pos
					FROM dbo.tblMagazziniMovimentiRigheEoW
					WHERE IdMovimento = @IdMovimento
				) x;

			INSERT dbo.tblMagazziniMovimentiRigheEoW (Id, IdMovimento, IdSede, IdMateriale, IdCriterio, Quantita, Lock, IdLotto, IdImballo, Colli, AllaRinfusa, Pos)
			VALUES (@returnId, @IdMovimento, @IdSede, @IdMateriale, @IdCriterio, @Quantita, @lockMovimento, @IdLotto, @IdImballo, @Colli, @AllaRinfusa, @pos);
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

PRINT 'uspMagazziniGiacenze_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniGiacenze_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF ISNULL(@Vista, '') NOT IN ('A', 'L')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve essere A (Articolo) o L (Lotto)';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Giacenza (coerente con Rifiuti/Giacenze ed EoW/Giacenze): mai memorizzata, sempre calcolata
		-- carico per carico come quantità della riga di carico confermata meno le relazioni degli
		-- scarichi confermati su quella riga (Movimento.Lock = 0). Quantita = somma dei residui;
		-- CarichiNumero = carichi con un residuo, cioè quelli che compongono la giacenza;
		-- GiacenzaGiorni = giorni dal più vecchio di quei carichi. In elenco solo le giacenze diverse da 0.
		-- La disponibilità del lotto (CapacitaResidua) resta riferita al caricato: quantità massima
		-- meno caricata, gli scarichi non la fanno risalire.
		SELECT
			c.Id,
			c.IdArticolo,
			c.IdLotto,
			c.[Data],
			c.Quantita,
			Residuo = c.Quantita - ISNULL(x.Scaricata, 0)
		INTO #Carichi
		FROM
			(
				SELECT
					rc.Id,
					rc.IdArticolo,
					rc.IdLotto,
					mc.[Data],
					rc.Quantita
				FROM
					dbo.tblMagazziniMovimentiRighe rc
					INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
					INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON rc.IdSede = i.Id
				WHERE
					rc.IdSede = @idSede
					AND mc.IdOperazione = 'C'
					-- Le righe descrittive del DDT (senza articolo) non sono carichi
					AND rc.IdArticolo IS NOT NULL
					AND rc.Lock = 0
					AND mc.Lock = 0
			) c
			OUTER APPLY (
				SELECT Scaricata = SUM(rel.Quantita)
				FROM
					dbo.tblMagazziniMovimentiRigheRelazioni rel
					INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
					INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					rel.Id = c.Id
					AND rp.Lock = 0
					AND mp.Lock = 0
			) x
		OPTION (RECOMPILE);

		IF @Vista = 'A'
		BEGIN
			SELECT
				art.Id,
				StatoValore = 0,
				StatoDescrizione = 'OK',
				art.Nome,
				ArticoloNome = CAST(NULL AS VARCHAR(100)),
				UnitaMisuraNome = u.Nome,
				IsNumero = CAST(IIF(art.IdUnitaMisura = 'NR', 1, 0) AS BIT),
				QuantitaMax = CAST(NULL AS DECIMAL(18, 2)),
				g.Quantita,
				GiacenzaGiorni = DATEDIFF(DAY, g.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CAST(NULL AS DECIMAL(18, 2)),
				g.CarichiNumero,
				RowsCount = COUNT(*) OVER ()
			FROM
				(
					SELECT
						IdArticolo,
						Quantita = SUM(Residuo),
						CarichiNumero = SUM(IIF(Residuo <> 0, 1, 0)),
						PrimaData = MIN(IIF(Residuo <> 0, [Data], NULL))
					FROM #Carichi
					GROUP BY IdArticolo
				) g
				INNER JOIN dbo.tblMagazziniArticoli art ON g.IdArticolo = art.Id
				LEFT JOIN dbo.tblUnitaMisura u ON art.IdUnitaMisura = u.Id
			WHERE
				g.Quantita <> 0
				AND (@Search IS NULL OR art.Nome LIKE '%' + @Search + '%' OR art.Codice LIKE '%' + @Search + '%')
			ORDER BY art.Nome
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
			OPTION (RECOMPILE);
		END
		ELSE
		BEGIN
			SELECT
				l.Id,
				StatoValore = 0,
				StatoDescrizione = 'OK',
				l.Nome,
				ArticoloNome = art.Nome,
				UnitaMisuraNome = u.Nome,
				IsNumero = CAST(IIF(art.IdUnitaMisura = 'NR', 1, 0) AS BIT),
				l.QuantitaMax,
				g.Quantita,
				GiacenzaGiorni = DATEDIFF(DAY, g.PrimaData, CAST(GETDATE() AS DATE)),
				CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - g.Caricata END,
				g.CarichiNumero,
				RowsCount = COUNT(*) OVER ()
			FROM
				(
					SELECT
						IdLotto,
						Caricata = SUM(Quantita),
						Quantita = SUM(Residuo),
						CarichiNumero = SUM(IIF(Residuo <> 0, 1, 0)),
						PrimaData = MIN(IIF(Residuo <> 0, [Data], NULL))
					FROM #Carichi
					GROUP BY IdLotto
				) g
				INNER JOIN dbo.tblMagazziniLotti l ON g.IdLotto = l.Id
				LEFT JOIN dbo.tblMagazziniArticoli art ON l.IdArticolo = art.Id
				LEFT JOIN dbo.tblUnitaMisura u ON art.IdUnitaMisura = u.Id
			WHERE
				g.Quantita <> 0
				AND (@Search IS NULL OR l.Nome LIKE '%' + @Search + '%')
			ORDER BY l.Nome
			OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
			FETCH NEXT @RowsPerPage ROWS ONLY
			OPTION (RECOMPILE);
		END

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

PRINT 'uspMagazziniGiacenze_get_Carichi_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniGiacenze_get_Carichi_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Id CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- Senza @Id: tutti i carichi in giacenza della sede del contesto; con @Id: quelli
		-- dell'articolo (@Vista = A) o del lotto (@Vista = L) indicato, sempre nella sede del contesto
		IF @Id IS NOT NULL AND ISNULL(@Vista, '') NOT IN ('A', 'L')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve essere A (Articolo) o L (Lotto)';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Carichi che compongono la giacenza: righe di carico di movimenti confermati con un residuo,
		-- cioè quantità caricata meno relazioni degli scarichi confermati su quella riga
		SELECT
			rc.Id,
			rc.IdMovimento,
			mc.Numero,
			mc.[Data],
			ArticoloNome = art.Nome,
			LottoNome = l.Nome,
			UnitaMisuraNome = u.Nome,
			IsNumero = CAST(IIF(art.IdUnitaMisura = 'NR', 1, 0) AS BIT),
			rc.Quantita,
			Scaricata = ISNULL(x.Scaricata, 0),
			Residuo = rc.Quantita - ISNULL(x.Scaricata, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblMagazziniMovimentiRighe rc
			INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON rc.IdSede = i.Id
			INNER JOIN dbo.tblMagazziniArticoli art ON rc.IdArticolo = art.Id
			LEFT JOIN dbo.tblUnitaMisura u ON art.IdUnitaMisura = u.Id
			LEFT JOIN dbo.tblMagazziniLotti l ON rc.IdLotto = l.Id
			OUTER APPLY (
				SELECT Scaricata = SUM(rel.Quantita)
				FROM
					dbo.tblMagazziniMovimentiRigheRelazioni rel
					INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
					INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
				WHERE
					rel.Id = rc.Id
					AND rp.Lock = 0
					AND mp.Lock = 0
			) x
		WHERE
			rc.IdSede = @idSede
			AND mc.IdOperazione = 'C'
			AND rc.Lock = 0
			AND mc.Lock = 0
			AND rc.Quantita - ISNULL(x.Scaricata, 0) <> 0
			AND (
				@Id IS NULL
				OR (@Vista = 'A' AND rc.IdArticolo = @Id)
				OR (@Vista = 'L' AND rc.IdLotto = @Id)
			)
			AND (
				@Search IS NULL
				OR mc.Numero = TRY_CAST(@Search AS INT)
				OR art.Nome LIKE '%' + @Search + '%'
				OR l.Nome LIKE '%' + @Search + '%'
			)
		ORDER BY mc.[Data] DESC, mc.Numero DESC, rc.Pos, rc.Id
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspEoWGiacenze_get_Carichi_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWGiacenze_get_Carichi_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Id CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		-- Senza @Id: tutti i carichi EoW della sede del contesto; con @Id: i carichi del lotto
		-- (@Vista = L) o del magazzino EoW (@Vista = M) indicato, sempre nella sede del contesto
		IF @Id IS NOT NULL AND ISNULL(@Vista, '') NOT IN ('L', 'M')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Vista deve essere L (Lotto) o M (Magazzino)';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EOW',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Titolarità sul Lotto/Magazzino indicato
		IF @Id IS NOT NULL AND @Vista = 'L' AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti l INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			WHERE l.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF @Id IS NOT NULL AND @Vista = 'M' AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWMagazzini g INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE g.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			lr.IdRegistrazione AS Id,
			-- Registro della registrazione: la sede interna può averne più di uno
			RegistroNome = g.Nome,
			r.Numero,
			r.Data,
			MaterialeNome = ISNULL(r.MaterialeDescrizione, mat.Nome),
			LottoNome = l.Nome,
			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			QuantitaComplessiva = vo.Quantita,
			QuantitaAllocata = lr.Quantita,
			-- Residuo attuale del lotto EoW della quota (gli scarichi di magazzino prelevano dal
			-- lotto, non dalla singola registrazione): quote di registrazioni attive meno gli
			-- scarichi dei movimenti di magazzino confermati
			ResiduoLotto = ISNULL(pl.Prodotta, 0) - ISNULL(sl.Scaricata, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblEoWLottiRifiutiRegistrazioni lr
			INNER JOIN dbo.tblEoWLotti l ON lr.IdLotto = l.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON lr.IdRegistrazione = r.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vo ON r.Id = vo.Id
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			LEFT JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON r.IdMateriale = mat.Id
			OUTER APPLY (
				SELECT Prodotta = SUM(qp.Quantita)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni qp
					INNER JOIN dbo.tblRifiutiRegistrazioni rp ON qp.IdRegistrazione = rp.Id
				WHERE
					qp.IdLotto = l.Id
					AND rp.Lock < 2
			) pl
			OUTER APPLY (
				SELECT Scaricata = SUM(rs.Quantita)
				FROM
					dbo.tblMagazziniMovimentiRigheEoWLotti rs
					INNER JOIN dbo.tblMagazziniMovimentiRigheEoW rg ON rs.Id = rg.Id
					INNER JOIN dbo.tblMagazziniMovimenti ms ON rg.IdMovimento = ms.Id
				WHERE
					rs.IdLotto = l.Id
					AND rg.Lock = 0
					AND ms.Lock = 0
			) sl
		-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
		-- mantiene le sue quote per un eventuale ripristino, ma non conta più
		WHERE
			r.Lock < 2
			AND l.IdSede = @idSede
			AND (
				@Id IS NULL
				OR (@Vista = 'L' AND l.Id = @Id)
				OR (@Vista = 'M' AND l.IdMagazzino = @Id)
			)
			AND (@Search IS NULL OR r.Numero = TRY_CAST(@Search AS INT) OR l.Nome LIKE '%' + @Search + '%')
		ORDER BY r.Data DESC, r.Numero DESC
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspEoWLotti_ins';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_ins
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idSede CHAR(16);
		SELECT @idSede = IdSede
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la sede';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblEoWLotti (Id, IdSede, Lock)
			VALUES (@returnId, @idSede, 2);
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

PRINT 'uspEoWLotti_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdMagazzino CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@Nome VARCHAR(50) = NULL,
	@DataApertura DATE = NULL,
	@DataChiusura DATE = NULL,
	@QuantitaMax DECIMAL(18, 2) = NULL,
	@Disabilitato BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdMagazzino = NULLIF(LTRIM(RTRIM(@IdMagazzino)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Disabilitato = ISNULL(@Disabilitato, 0);

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
		IF @IdMateriale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdMateriale non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataApertura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @DataApertura non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataChiusura IS NOT NULL AND @DataChiusura < @DataApertura
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di chiusura non può essere precedente alla data di apertura';
			GOTO BRANCH_END;
		END
		IF @QuantitaMax IS NOT NULL AND @QuantitaMax <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità massima deve essere maggiore di zero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede reale del lotto
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblEoWLotti c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il materiale deve esistere in anagrafica (tblRifiutiMateriali, nessuna anagrafica EoW parallela)
		IF NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiMateriali WHERE Id = @IdMateriale)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il materiale indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Il magazzino, se indicato, deve appartenere alla stessa sede del lotto
		IF @IdMagazzino IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblEoWMagazzini
			WHERE
				Id = @IdMagazzino
				AND IdSede = @idSede
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il magazzino selezionato non appartiene alla sede del lotto';
			GOTO BRANCH_END;
		END

		-- Non è possibile cambiare il materiale se il lotto ha già registrazioni M associate
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti
			WHERE
				Id = @Id
				AND Lock = 0
				AND IdMateriale <> @IdMateriale
				AND EXISTS (SELECT 1 FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdLotto = @Id)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare il materiale di un lotto con registrazioni associate';
			GOTO BRANCH_END;
		END

		-- La quantità massima non può scendere sotto la produzione già allocata al lotto (quote
		-- di registrazioni M attive): il lotto EoW è una partita di produzione. Aumentarla è
		-- sempre possibile (riapre capienza, se il lotto non è chiuso).
		DECLARE @quantitaAllocata DECIMAL(18, 2) = ISNULL((
			SELECT SUM(q.Quantita)
			FROM
				dbo.tblEoWLottiRifiutiRegistrazioni q
				INNER JOIN dbo.tblRifiutiRegistrazioni rr ON q.IdRegistrazione = rr.Id
			WHERE
				q.IdLotto = @Id
				AND rr.Lock < 2
		), 0);
		IF @QuantitaMax IS NOT NULL AND @QuantitaMax < @quantitaAllocata
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La quantità massima non può essere inferiore alla quantità già allocata al lotto (' + FORMAT(@quantitaAllocata, 'N2', 'it-IT') + ')';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro lotto attivo con lo stesso nome nella stessa sede
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWLotti
			WHERE
				Id <> @Id
				AND IdSede = @idSede
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro lotto con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblEoWLotti
			SET
				Lock = 0,
				IdMagazzino = @IdMagazzino,
				IdMateriale = @IdMateriale,
				Nome = @Nome,
				DataApertura = @DataApertura,
				DataChiusura = @DataChiusura,
				QuantitaMax = @QuantitaMax,
				Disabilitato = @Disabilitato
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Lotto non trovato o già eliminato';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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

PRINT 'uspEoWLotti_get';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEoWLotti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWLotti
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lotto non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			l.Id,
			l.IdSede,
			SedeNome = s.Nome,
			l.IdMagazzino,
			MagazzinoNome = g.Nome,
			l.IdMateriale,
			MaterialeNome = m.Nome,
			l.Nome,
			l.DataApertura,
			l.DataChiusura,
			l.QuantitaMax,
			QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0),
			-- Scaricata dal magazzino e giacenza (allocata - scaricata): gli scarichi non liberano capienza
			QuantitaScaricata = sl.Scaricata,
			Giacenza = sl.Giacenza,
			CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAllocata, 0) END,
			Disabilitato = ISNULL(l.Disabilitato, 0),
			l.Lock
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.tblSedi s ON l.IdSede = s.Id
			LEFT JOIN dbo.tblEoWMagazzini g ON l.IdMagazzino = g.Id
			LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
			OUTER APPLY (
				-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
				-- mantiene le sue quote per un eventuale ripristino, ma non conta più
				SELECT QuantitaAllocata = SUM(r.Quantita)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
				WHERE
					r.IdLotto = l.Id
					AND rr.Lock < 2
			) q
			CROSS APPLY dbo.ufnEoWLotti_get_Saldo(l.Id) sl
		WHERE
			l.Id = @Id
			AND l.Lock <= 2;

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

PRINT 'uspEoWLotti_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdMagazzino CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@Aperto BIT = NULL,
	@Disabilitato BIT = NULL,
	@DataAperturaDa DATE = NULL,
	@DataAperturaA DATE = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		-- Le select della ricerca usano gli zeri come "nessuna selezione" ((Nessuno)/(Selezionare))
		SET @IdMagazzino = NULLIF(NULLIF(LTRIM(RTRIM(@IdMagazzino)), ''), REPLICATE('0', 16));
		SET @IdMateriale = NULLIF(NULLIF(LTRIM(RTRIM(@IdMateriale)), ''), REPLICATE('0', 2));
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT
			l.Id,
			-- Stato: prima l'anomalia "Scaricato più del prodotto" (il magazzino tradizionale ha scaricato
			-- più di quanto il registro operativo alloca al lotto: il magazzino EoW prevale e non viene
			-- mai corretto in automatico), poi la capacità (solo con quantità massima impostata; il lotto EoW
			-- è una partita di produzione, gli scarichi non liberano capienza): 2 = anomalia o capacità
			-- superata, 1 = lotto pieno o capacità residua sotto il 30% della quantità massima, 0 = OK
			StatoValore = CASE
				WHEN s.Giacenza < 0 THEN 2
				WHEN l.QuantitaMax IS NULL THEN 0
				WHEN c.QuantitaAllocata > l.QuantitaMax THEN 2
				WHEN l.QuantitaMax - c.QuantitaAllocata < l.QuantitaMax * 0.3 THEN 1
				ELSE 0
			END,
			StatoDescrizione = CASE
				WHEN s.Giacenza < 0
					THEN 'Scaricato più del prodotto: prodotti ' + FORMAT(s.Prodotta, 'N2', 'it-IT') + ' kg, scaricati '
						+ FORMAT(s.Scaricata, 'N2', 'it-IT') + ' kg dal magazzino'
				WHEN l.QuantitaMax IS NULL THEN 'OK'
				WHEN c.QuantitaAllocata > l.QuantitaMax
					THEN 'Quantità massima superata di ' + FORMAT(c.QuantitaAllocata - l.QuantitaMax, 'N2', 'it-IT') + ' kg: allocati '
						+ FORMAT(c.QuantitaAllocata, 'N2', 'it-IT') + ' kg su ' + FORMAT(l.QuantitaMax, 'N2', 'it-IT') + ' kg'
				WHEN c.QuantitaAllocata = l.QuantitaMax THEN 'Lotto pieno: disponibilità esaurita'
				WHEN l.QuantitaMax - c.QuantitaAllocata < l.QuantitaMax * 0.3
					THEN 'Disponibilità sotto il 30%: ' + FORMAT(l.QuantitaMax - c.QuantitaAllocata, 'N2', 'it-IT') + ' kg su '
						+ FORMAT(l.QuantitaMax, 'N2', 'it-IT') + ' kg'
				ELSE 'OK'
			END,
			NumeroRegistrazioni = ISNULL(q.NumeroRegistrazioni, 0),
			l.Nome,
			MaterialeNome = m.Nome,
			MagazzinoNome = g.Nome,
			l.DataApertura,
			l.DataChiusura,
			l.QuantitaMax,
			QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0),
			CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.QuantitaAllocata, 0) END,
			Disabilitato = ISNULL(l.Disabilitato, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
			LEFT JOIN dbo.tblEoWMagazzini g ON l.IdMagazzino = g.Id
			OUTER APPLY (
				-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
				-- mantiene le sue quote per un eventuale ripristino, ma non conta più
				SELECT
					QuantitaAllocata = SUM(r.Quantita),
					NumeroRegistrazioni = COUNT(DISTINCT r.IdRegistrazione)
				FROM
					dbo.tblEoWLottiRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiRegistrazioni rr ON r.IdRegistrazione = rr.Id
				WHERE
					r.IdLotto = l.Id
					AND rr.Lock < 2
			) q
					CROSS APPLY (SELECT QuantitaAllocata = ISNULL(q.QuantitaAllocata, 0)) c
					CROSS APPLY dbo.ufnEoWLotti_get_Saldo(l.Id) s
		WHERE
			l.Lock = 0
			AND l.IdSede = @idSede
			AND
				(
				@IdMagazzino IS NULL
				OR l.IdMagazzino = @IdMagazzino
				)
			AND
				(
				@IdMateriale IS NULL
				OR l.IdMateriale = @IdMateriale
				)
			AND
				(
				@Aperto IS NULL
				OR
					(
					@Aperto = 1
					AND l.DataChiusura IS NULL
					)
				OR
					(
					@Aperto = 0
					AND l.DataChiusura IS NOT NULL
					)
				)
			AND
				(
				@Disabilitato IS NULL
				OR ISNULL(l.Disabilitato, 0) = @Disabilitato
				)
			AND
				(
				@DataAperturaDa IS NULL
				OR l.DataApertura >= @DataAperturaDa
				)
			AND
				(
				@DataAperturaA IS NULL
				OR l.DataApertura <= @DataAperturaA
				)
			AND
				(
				@Search IS NULL
				OR l.Nome LIKE '%' + @Search + '%'
				)
		ORDER BY l.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspEoWLotti_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_del
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
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWLotti
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
				dbo.tblEoWLotti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblEoWLotti
		WHERE Id = @Id);

		-- ── CASO 1: lotto attivo (Lock = 0) → soft delete ────────────────────
		IF @lock = 0
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdLotto = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un lotto con registrazioni associate non può essere cancellato';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni
				WHERE IdLotto = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un lotto usato in una configurazione di allocazione non può essere cancellato';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblEoWLotti
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Lotto non trovato o già eliminato';
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

		-- ── CASO 2: lotto in bozza (Lock = 2) → hard delete ──────────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblEoWLottiRifiutiRegistrazioni
				WHERE IdLotto = @Id;
				DELETE dbo.tblEoWLottiAllocazioni
				WHERE IdLotto = @Id;
				DELETE dbo.tblEoWLotti
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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

PRINT 'uspEoWLotti_get_MagazziniSelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get_MagazziniSelectList
	@IdSede CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sulla sede indicata
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i
			WHERE i.Id = @IdSede)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Nessuno)' AS VARCHAR(500)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- magazzino selezionato: sempre presente, anche se non combacia con @Search

			SELECT
				g.Id,
				[Text] = g.Nome,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblEoWMagazzini g
			WHERE
				g.Id = @IdSelected
				AND g.IdSede = @IdSede

			UNION ALL -- altri magazzini attivi della sede, filtrabili per @Search

			SELECT
				g.Id,
				[Text] = g.Nome,
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM dbo.tblEoWMagazzini g
			WHERE
				g.IdSede = @IdSede
				AND g.Lock = 0
				AND ISNULL(g.Disabilitato, 0) = 0
				AND g.Id <> @IdSelected
				AND
					(
					@Search IS NULL
					OR g.Nome LIKE '%' + @Search + '%'
					)
		)
		SELECT TOP 20 Id, [Text], Selected
		FROM cte
		ORDER BY Pos, [Text]
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
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspEoWLotti_get_RegistrazioniList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get_RegistrazioniList
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEoWLotti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			lr.IdRegistrazione,
			r.Numero,
			r.Data,
			MaterialeNome = ISNULL(r.MaterialeDescrizione, mat.Nome),
			-- Quantità effettiva (viewRifiutiRegistrazioniEffettive): una rettifica non modifica l'originale
			QuantitaComplessiva = vo.Quantita,
			QuantitaAllocata = lr.Quantita
		FROM
			dbo.tblEoWLottiRifiutiRegistrazioni lr
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON lr.IdRegistrazione = r.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vo ON r.Id = vo.Id
			LEFT JOIN dbo.tblRifiutiMateriali mat ON r.IdMateriale = mat.Id
		-- Solo quote di registrazioni attive (Lock < 2): una registrazione eliminata (Lock = 4)
		-- mantiene le sue quote per un eventuale ripristino, ma non conta più
		WHERE
			lr.IdLotto = @Id
			AND r.Lock < 2
		ORDER BY r.Data DESC, r.Numero DESC;

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

PRINT 'uspEoWLotti_get_AllocazioniList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get_AllocazioniList
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEoWLotti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			a.Id AS IdAllocazione,
			a.Nome,
			TipoNome = t.Nome,
			la.Valore
		FROM
			dbo.tblEoWLottiAllocazioni la
			INNER JOIN dbo.tblEoWAllocazioni a ON la.IdAllocazione = a.Id
			INNER JOIN dbo.tblEoWAllocazioniTipi t ON a.IdAllocazioneTipo = t.Id
		WHERE
			la.IdLotto = @Id
			AND a.Lock = 0
		ORDER BY a.Nome;

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

PRINT 'uspEoWMagazzini_ins';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWMagazzini_ins
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idSede CHAR(16);
		SELECT @idSede = IdSede
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la sede';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblEoWMagazzini (Id, IdSede, Lock)
			VALUES (@returnId, @idSede, 2);
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

PRINT 'uspEoWMagazzini_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWMagazzini_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Disabilitato BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Disabilitato = ISNULL(@Disabilitato, 0);

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
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede reale del magazzino
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblEoWMagazzini c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro magazzino attivo con lo stesso nome nella stessa sede
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWMagazzini
			WHERE
				Id <> @Id
				AND IdSede = @idSede
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro magazzino con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblEoWMagazzini
			SET
				Lock = 0,
				Nome = @Nome,
				Disabilitato = @Disabilitato
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Magazzino non trovato o già eliminato';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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

PRINT 'uspEoWMagazzini_get';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWMagazzini_get
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEoWMagazzini c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWMagazzini
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Magazzino non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			g.Id,
			g.IdSede,
			SedeNome = s.Nome,
			g.Nome,
			Disabilitato = ISNULL(g.Disabilitato, 0),
			g.Lock
		FROM
			dbo.tblEoWMagazzini g
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
		WHERE
			g.Id = @Id
			AND g.Lock <= 2;

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

PRINT 'uspEoWMagazzini_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWMagazzini_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@Disabilitato BIT = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			g.Id,
			StatoValore = 0,
			StatoDescrizione = 'OK',
			g.Nome,
			SedeNome = s.Nome,
			Disabilitato = ISNULL(g.Disabilitato, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblEoWMagazzini g
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
		WHERE
			g.Lock = 0
			AND (@IdSede IS NULL OR g.IdSede = @IdSede)
			AND (@Disabilitato IS NULL OR ISNULL(g.Disabilitato, 0) = @Disabilitato)
			AND (@Search IS NULL OR g.Nome LIKE '%' + @Search + '%')
		ORDER BY g.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspEoWMagazzini_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWMagazzini_del
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
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWMagazzini
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
				dbo.tblEoWMagazzini c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblEoWMagazzini
		WHERE Id = @Id);

		-- ── CASO 1: magazzino attivo (Lock = 0) → soft delete ────────────────
		IF @lock = 0
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM dbo.tblEoWLotti
				WHERE
					IdMagazzino = @Id
					AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un magazzino con lotti associati non può essere cancellato';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblEoWMagazzini
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Magazzino non trovato o già eliminato';
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

		-- ── CASO 2: magazzino in bozza (Lock = 2) → hard delete ──────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				-- IdMagazzino è nullable su tblEoWLotti: un lotto (di un'altra bozza, di fatto
				-- irraggiungibile finché il magazzino non è mai stato Lock=0) perde solo il
				-- collegamento, non viene cancellato.
				UPDATE dbo.tblEoWLotti
				SET IdMagazzino = NULL
				WHERE IdMagazzino = @Id;

				DELETE dbo.tblEoWMagazzini
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il magazzino è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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

PRINT 'uspEoWAllocazioni_ins';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_ins
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idSede CHAR(16);
		SELECT @idSede = IdSede
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la sede';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblEoWAllocazioni (Id, IdSede, Lock)
			VALUES (@returnId, @idSede, 2);
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

PRINT 'uspEoWAllocazioni_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdAllocazioneTipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdAllocazioneTipo = NULLIF(LTRIM(RTRIM(@IdAllocazioneTipo)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);

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
		IF @IdAllocazioneTipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdAllocazioneTipo non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Nome non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) e recupera la sede reale dell'allocazione
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblEoWAllocazioniTipi WHERE Id = @IdAllocazioneTipo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il tipo di allocazione indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Non è possibile cambiare il tipo se l'allocazione ha già lotti collegati, anche se non
		-- ancora salvata (uspEoWAllocazioni_ins_Lotto memorizza il tipo con il primo lotto)
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWAllocazioni
			WHERE
				Id = @Id
				AND IdAllocazioneTipo <> @IdAllocazioneTipo
				AND EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare il tipo di un''allocazione con lotti associati';
			GOTO BRANCH_END;
		END

		-- I lotti presenti devono rispettare il tipo (stessi vincoli di uspEoWAllocazioni_ins_Lotto):
		-- intercetta anche lotti aggiunti quando il tipo non era ancora salvato
		IF @IdAllocazioneTipo = 'U' AND (SELECT COUNT(*) FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id) > 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''allocazione di tipo Lotto unico può contenere un solo lotto';
			GOTO BRANCH_END;
		END

		IF @IdAllocazioneTipo = 'P' AND (
			EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni
				WHERE
					IdAllocazione = @Id
					AND (Valore IS NULL OR Valore <= 0 OR Valore > 100)
			)
			OR (SELECT ISNULL(SUM(Valore), 0) FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id) > 100
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le percentuali dei lotti devono essere maggiori di zero e la loro somma non può superare 100';
			GOTO BRANCH_END;
		END

		IF @IdAllocazioneTipo = 'C' AND (
			EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni
				WHERE
					IdAllocazione = @Id
					AND (Valore IS NULL OR Valore <= 0)
			)
			OR EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni
				WHERE IdAllocazione = @Id
				GROUP BY Valore
				HAVING COUNT(*) > 1
			)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ogni lotto deve avere una priorità diversa: togliere e aggiungere di nuovo i lotti con la stessa priorità';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un'altra allocazione attiva con lo stesso nome nella stessa sede
		IF EXISTS (
			SELECT 1
			FROM dbo.tblEoWAllocazioni
			WHERE
				Id <> @Id
				AND IdSede = @idSede
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra allocazione con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblEoWAllocazioni
			SET
				Lock = 0,
				IdAllocazioneTipo = @IdAllocazioneTipo,
				Nome = @Nome
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Allocazione non trovata o già eliminata';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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

PRINT 'uspEoWAllocazioni_get';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_get
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEoWAllocazioni c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWAllocazioni
		WHERE
			Id = @Id
			AND Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allocazione non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			a.Id,
			a.IdSede,
			SedeNome = s.Nome,
			a.IdAllocazioneTipo,
			TipoNome = t.Nome,
			-- Il materiale non è un campo proprio dell'allocazione: si ricava dai lotti già
			-- collegati (tutti garantiti dello stesso materiale da uspEoWAllocazioni_ins_Lotto),
			-- NULL se l'allocazione non ha ancora nessun lotto.
			mat.IdMateriale,
			mat.MaterialeNome,
			a.Nome,
			a.Lock
		FROM
			dbo.tblEoWAllocazioni a
			INNER JOIN dbo.tblSedi s ON a.IdSede = s.Id
			LEFT JOIN dbo.tblEoWAllocazioniTipi t ON a.IdAllocazioneTipo = t.Id
			OUTER APPLY (
				SELECT TOP 1 IdMateriale = l.IdMateriale, MaterialeNome = m.Nome
				FROM
					dbo.tblEoWLottiAllocazioni la
					INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
					LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
				WHERE la.IdAllocazione = a.Id
			) mat
		WHERE
			a.Id = @Id
			AND a.Lock <= 2;

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

PRINT 'uspEoWAllocazioni_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT
			a.Id,
			StatoValore = 0,
			StatoDescrizione = 'OK',
			a.Nome,
			TipoNome = t.Nome,
			MaterialeNome = mat.MaterialeNome,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblEoWAllocazioni a
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON a.IdSede = i.Id
			LEFT JOIN dbo.tblEoWAllocazioniTipi t ON a.IdAllocazioneTipo = t.Id
			-- Il materiale non è un campo proprio dell'allocazione: si ricava dai lotti già collegati
			OUTER APPLY (
				SELECT TOP 1 IdMateriale = l.IdMateriale, MaterialeNome = m.Nome
				FROM
					dbo.tblEoWLottiAllocazioni la
					INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
					LEFT JOIN dbo.tblRifiutiMateriali m ON l.IdMateriale = m.Id
				WHERE la.IdAllocazione = a.Id
			) mat
		WHERE
			a.Lock = 0
			AND a.IdSede = @idSede
			AND (@IdMateriale IS NULL OR mat.IdMateriale = @IdMateriale)
			AND (@Search IS NULL OR a.Nome LIKE '%' + @Search + '%')
		ORDER BY a.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspEoWAllocazioni_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_del
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
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistita o già cancellata viene trattata come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1
		FROM dbo.tblEoWAllocazioni
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
				dbo.tblEoWAllocazioni c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblEoWAllocazioni
		WHERE Id = @Id);

		-- ── CASO 1: allocazione attiva (Lock = 0) → soft delete ──────────────
		IF @lock = 0
		BEGIN
			BEGIN TRANSACTION;
				-- Le righe tblEoWLottiAllocazioni sono la configurazione, di proprietà esclusiva
				-- dell'allocazione: cancellate insieme, non azzerate (i lotti referenziati restano intatti).
				DELETE dbo.tblEoWLottiAllocazioni
				WHERE IdAllocazione = @Id;

				UPDATE dbo.tblEoWAllocazioni
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Allocazione non trovata o già eliminata';
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

		-- ── CASO 2: allocazione in bozza (Lock = 2) → hard delete ────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblEoWLottiAllocazioni
				WHERE IdAllocazione = @Id;
				DELETE dbo.tblEoWAllocazioni
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''allocazione è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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

PRINT 'uspEoWAllocazioniTipi_get_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioniTipi_get_SelectList
	@IdSelected CHAR(1) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione (dato di riferimento statico, nessuna titolarità)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			Id,
			[Text] = Nome,
			Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblEoWAllocazioniTipi
		ORDER BY Nome
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
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspEoWAllocazioni_get_LottiList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_get_LottiList
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEoWAllocazioni c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			la.IdLotto,
			LottoNome = l.Nome,
			la.Valore
		FROM
			dbo.tblEoWLottiAllocazioni la
			INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
		WHERE la.IdAllocazione = @Id
		ORDER BY l.Nome;

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

PRINT 'uspEoWAllocazioni_get_LottiSelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_get_LottiSelectList
	@Id CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati dell'allocazione
		DECLARE @idSede CHAR(16);
		SELECT @idSede = c.IdSede
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE c.Id = @Id;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Materiale già fissato dai lotti presenti nell'allocazione, NULL se ancora nessuno
		DECLARE @idMateriale CHAR(2) = (
			SELECT TOP 1 l.IdMateriale
			FROM dbo.tblEoWLottiAllocazioni la
			INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
			WHERE la.IdAllocazione = @Id
		);

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(500)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- lotto selezionato: sempre presente, anche se non combacia con @Search

			SELECT
				l.Id,
				[Text] = l.Nome,
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblEoWLotti l
			WHERE
				l.Id = @IdSelected
				AND l.IdSede = @idSede

			UNION ALL -- altri lotti aperti/non disabilitati della sede, stesso materiale degli altri
			          -- lotti già in allocazione (o qualsiasi se nessuno ancora presente), non già
			          -- inseriti in questa allocazione, filtrabili per @Search

			SELECT
				l.Id,
				[Text] = l.Nome,
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM dbo.tblEoWLotti l
			WHERE
				l.IdSede = @idSede
				AND l.Lock = 0
				AND ISNULL(l.Disabilitato, 0) = 0
				AND l.DataChiusura IS NULL
				AND (@idMateriale IS NULL OR l.IdMateriale = @idMateriale)
				AND l.Id <> @IdSelected
				AND NOT EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id AND IdLotto = l.Id)
				AND
					(
					@Search IS NULL
					OR l.Nome LIKE '%' + @Search + '%'
					)
		)
		SELECT TOP 20 Id, [Text], Selected
		FROM cte
		ORDER BY Pos, [Text]
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
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspEoWAllocazioni_ins_Lotto';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_ins_Lotto
	@Id CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@Valore DECIMAL(18, 2) = NULL,
	@IdSessione CHAR(16) = NULL,
	-- Tipo scelto nella pagina: un'allocazione nuova ha il tipo salvato solo con il primo "Salva",
	-- quindi senza questo parametro i controlli per tipo verrebbero saltati (tipo NULL)
	@IdAllocazioneTipo CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdAllocazioneTipo = NULLIF(LTRIM(RTRIM(@IdAllocazioneTipo)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdLotto non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità + dati dell'allocazione
		DECLARE @idSedeAllocazione CHAR(16);
		DECLARE @tipo CHAR(1);
		SELECT
			@idSedeAllocazione = c.IdSede,
			@tipo = c.IdAllocazioneTipo
		FROM
			dbo.tblEoWAllocazioni c
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
		WHERE
			c.Id = @Id
			AND c.Lock <= 2;

		IF @idSedeAllocazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allocazione non trovata o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il materiale dell'allocazione non è un campo proprio: si ricava dal primo lotto aggiunto
		-- e deve restare coerente con gli altri lotti già presenti (nessuna anagrafica/duplicazione
		-- separata, "un'Allocazione = un Materiale" è solo un vincolo, non uno stato memorizzato).
		DECLARE @idMaterialeAllocazione CHAR(2) = (
			SELECT TOP 1 l.IdMateriale
			FROM dbo.tblEoWLottiAllocazioni la
			INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
			WHERE la.IdAllocazione = @Id
		);

		-- Titolarità + dati del lotto
		DECLARE @idSedeLotto CHAR(16);
		DECLARE @idMaterialeLotto CHAR(2);
		SELECT
			@idSedeLotto = l.IdSede,
			@idMaterialeLotto = l.IdMateriale
		FROM
			dbo.tblEoWLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
		WHERE
			l.Id = @IdLotto
			AND l.Lock = 0;

		IF @idSedeLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lotto non trovato o non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @idSedeLotto <> @idSedeAllocazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il lotto selezionato non appartiene alla sede dell''allocazione';
			GOTO BRANCH_END;
		END

		IF @idMaterialeAllocazione IS NOT NULL AND @idMaterialeLotto <> @idMaterialeAllocazione
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il materiale del lotto non coincide con il materiale degli altri lotti già presenti nell''allocazione';
			GOTO BRANCH_END;
		END

		IF EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id AND IdLotto = @IdLotto)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questo lotto è già presente nell''allocazione';
			GOTO BRANCH_END;
		END

		-- Tipo effettivo: con lotti già presenti vale quello salvato (non si può cambiare, come in
		-- uspEoWAllocazioni_upd); senza lotti vale quello scelto nella pagina, che viene memorizzato
		-- insieme al lotto cosi' i controlli sotto non vengono mai saltati.
		DECLARE @isLottiPresenti BIT = IIF(EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id), 1, 0);

		IF @isLottiPresenti = 1 AND @tipo IS NOT NULL AND @IdAllocazioneTipo IS NOT NULL AND @IdAllocazioneTipo <> @tipo
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non è possibile cambiare il tipo di un''allocazione con lotti associati';
			GOTO BRANCH_END;
		END

		DECLARE @isTipoDaSalvare BIT = 0;
		-- (anche con lotti presenti se il tipo non era mai stato salvato: allocazioni create prima di
		-- questo controllo)
		IF (@isLottiPresenti = 0 OR @tipo IS NULL) AND @IdAllocazioneTipo IS NOT NULL AND @IdAllocazioneTipo <> ISNULL(@tipo, '')
		BEGIN
			SET @tipo = @IdAllocazioneTipo;
			SET @isTipoDaSalvare = 1;
		END

		IF @tipo IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.tblEoWAllocazioniTipi WHERE Id = @tipo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il tipo di allocazione prima di aggiungere i lotti';
			GOTO BRANCH_END;
		END

		-- Validazione specifica per tipo (i valori dei tipi sono in tblEoWAllocazioniTipi: U=Lotto
		-- unico, P=Percentuale, C=Priorità/Capacità)
		IF @tipo = 'U' AND EXISTS (SELECT 1 FROM dbo.tblEoWLottiAllocazioni WHERE IdAllocazione = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''allocazione di tipo Lotto unico può contenere un solo lotto';
			GOTO BRANCH_END;
		END

		IF @tipo = 'P' AND (@Valore IS NULL OR @Valore <= 0 OR @Valore > 100)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La percentuale deve essere maggiore di zero e non superiore a 100';
			GOTO BRANCH_END;
		END

		IF @tipo = 'P' AND @Valore + ISNULL((
				SELECT SUM(la.Valore)
				FROM dbo.tblEoWLottiAllocazioni la
				WHERE la.IdAllocazione = @Id
			), 0) > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La somma delle percentuali dei lotti non può superare 100';
			GOTO BRANCH_END;
		END

		IF @tipo = 'C' AND (@Valore IS NULL OR @Valore <= 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La priorità deve essere un valore maggiore di zero';
			GOTO BRANCH_END;
		END

		IF @tipo = 'C' AND EXISTS (
				SELECT 1
				FROM dbo.tblEoWLottiAllocazioni la
				WHERE la.IdAllocazione = @Id AND la.Valore = @Valore
			)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Questa priorità è già assegnata a un altro lotto dell''allocazione';
			GOTO BRANCH_END;
		END

		IF @tipo = 'U'
			SET @Valore = NULL;

		BEGIN TRANSACTION;
			IF @isTipoDaSalvare = 1
				UPDATE dbo.tblEoWAllocazioni
				SET IdAllocazioneTipo = @tipo
				WHERE Id = @Id;

			INSERT dbo.tblEoWLottiAllocazioni (IdLotto, IdAllocazione, Valore)
			VALUES (@IdLotto, @Id, @Valore);
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

PRINT 'uspEoWAllocazioni_del_Lotto';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_del_Lotto
	@Id CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdLotto = NULLIF(LTRIM(RTRIM(@IdLotto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdLotto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdLotto non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Titolarità sull'allocazione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEoWAllocazioni c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DELETE dbo.tblEoWLottiAllocazioni
			WHERE
				IdAllocazione = @Id
				AND IdLotto = @IdLotto;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Lotto non presente nell''allocazione o già rimosso';
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

PRINT 'uspMagazziniArticoli_ins';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniArticoli_ins
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MGC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'Articolo appartiene all'azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblMagazziniArticoli (Id, IdSede, Lock)
			VALUES (@returnId, @idAzienda, 2);
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

PRINT 'uspMagazziniArticoli_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniArticoli_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Codice VARCHAR(20) = NULL,
	@Descrizione VARCHAR(1000) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdUnitaMisura = NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Codice = dbo.ufnStringhe_get_SenzaSpazi(@Codice, 0, 1);
		SET @Descrizione = dbo.ufnStringhe_get_SenzaSpazi(@Descrizione, 0, 1);

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
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il nome';
			GOTO BRANCH_END;
		END
		IF @IdUnitaMisura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''unità di misura';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblUnitaMisura WHERE Id = @IdUnitaMisura)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''unità di misura indicata non esiste';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MGC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = c.IdSede
		FROM
			dbo.tblMagazziniArticoli c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un altro articolo attivo con lo stesso nome nella stessa azienda
		IF EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniArticoli
			WHERE
				Id <> @Id
				AND IdSede = @idAzienda
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro articolo con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		-- Unità di misura NR (a numero): quantità intere, non frazionabili. Un articolo già
		-- movimentato con quantità decimali non può passare a NR
		IF @IdUnitaMisura = 'NR' AND EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniMovimentiRighe
			WHERE
				IdArticolo = @Id
				AND Quantita <> FLOOR(Quantita)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''articolo ha movimenti con quantità decimali: non può essere gestito a numero';
			GOTO BRANCH_END;
		END

		-- Il codice è opzionale, ma se indicato deve essere univoco nella stessa azienda
		-- (stessa regola del nome)
		IF @Codice IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblMagazziniArticoli
			WHERE
				Id <> @Id
				AND IdSede = @idAzienda
				AND Lock = 0
				AND Codice = @Codice
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un altro articolo con lo stesso codice è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblMagazziniArticoli
			SET
				Lock = 0,
				IdUnitaMisura = @IdUnitaMisura,
				Nome = @Nome,
				Codice = @Codice,
				Descrizione = @Descrizione
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Articolo non trovato o già eliminato';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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

PRINT 'uspMagazziniArticoli_get';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniArticoli_get
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

		-- Controlla il permesso sulla funzione: la scheda dell'articolo si legge con la funzione
		-- Configurazione (MGC, pagina Articoli) oppure con la funzione Magazzino (MAG): i movimenti
		-- la leggono per sapere se l'articolo è gestito a numero
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MGC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'MAG',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniArticoli c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniArticoli WHERE Id = @Id AND Lock <= 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Articolo non trovato';
			GOTO BRANCH_END;
		END

		SELECT
			a.Id,
			a.IdSede,
			a.IdUnitaMisura,
			UnitaMisuraNome = u.Nome,
			a.Nome,
			a.Codice,
			a.Descrizione,
			a.Lock
		FROM
			dbo.tblMagazziniArticoli a
			LEFT JOIN dbo.tblUnitaMisura u ON a.IdUnitaMisura = u.Id
		WHERE
			a.Id = @Id
			AND a.Lock <= 2;

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

PRINT 'uspMagazziniArticoli_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniArticoli_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MGC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda)
		SELECT
			a.Id,
			StatoValore = 0,
			StatoDescrizione = 'OK',
			a.Nome,
			a.Codice,
			UnitaMisuraNome = u.Nome,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblMagazziniArticoli a
			INNER JOIN dbo.tblSessioni e ON a.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblUnitaMisura u ON a.IdUnitaMisura = u.Id
		WHERE
			e.Id = @IdSessione
			AND a.Lock = 0
			AND (@Search IS NULL OR a.Nome LIKE '%' + @Search + '%' OR a.Codice LIKE '%' + @Search + '%')
		ORDER BY a.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspMagazziniArticoli_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniArticoli_del
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
			@IdFunzione = 'MGC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniArticoli WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniArticoli c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock FROM dbo.tblMagazziniArticoli WHERE Id = @Id);

		-- ── CASO 1: articolo attivo (Lock = 0) → soft delete ─────────────────
		IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniLotti WHERE IdArticolo = @Id AND Lock <= 2)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un articolo con lotti associati non può essere cancellato';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE IdArticolo = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un articolo con movimenti associati non può essere cancellato';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblMagazziniArticoli
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Articolo non trovato o già eliminato';
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

		-- ── CASO 2: articolo in bozza (Lock = 2) → hard delete ───────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblMagazziniArticoli
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''articolo è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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

PRINT 'uspMagazziniLotti_ins';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniLotti_ins
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MGC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idSede CHAR(16);
		SELECT @idSede = IdSede
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la sede';
			GOTO BRANCH_END;
		END

		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblMagazziniLotti (Id, IdSede, Lock)
			VALUES (@returnId, @idSede, 2);
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

PRINT 'uspMagazziniLotti_get';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniLotti_get
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
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MGC',
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
				dbo.tblMagazziniLotti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniLotti WHERE Id = @Id AND Lock <= 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Lotto non trovato';
			GOTO BRANCH_END;
		END

		-- Disponibilità = carichi confermati - scarichi confermati (mai memorizzata)
		SELECT
			l.Id,
			l.IdSede,
			l.IdArticolo,
			ArticoloNome = art.Nome,
			l.Nome,
			l.DataApertura,
			l.DataChiusura,
			l.QuantitaMax,
			QuantitaCaricata = ISNULL(q.Caricato, 0),
			QuantitaScaricata = ISNULL(q.Scaricato, 0),
			Disponibilita = ISNULL(q.Caricato, 0) - ISNULL(q.Scaricato, 0),
			CapacitaResidua = CASE WHEN l.QuantitaMax IS NULL THEN NULL ELSE l.QuantitaMax - ISNULL(q.Caricato, 0) END,
			Disabilitato = ISNULL(l.Disabilitato, 0),
			l.Lock
		FROM
			dbo.tblMagazziniLotti l
			LEFT JOIN dbo.tblMagazziniArticoli art ON l.IdArticolo = art.Id
			-- Caricato: righe di carico confermate del lotto (le righe di scarico Manuale hanno anch'esse IdLotto: filtro sull'operazione); Scaricato: relazioni di scarichi
			-- confermati su quelle righe di carico (tblMagazziniMovimentiRigheRelazioni)
			OUTER APPLY (
				SELECT
					Caricato = (
						SELECT SUM(rc.Quantita)
						FROM
							dbo.tblMagazziniMovimentiRighe rc
							INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
						WHERE
							rc.IdLotto = l.Id
							AND mc.IdOperazione = 'C'
							AND rc.Lock = 0
							AND mc.Lock = 0
					),
					Scaricato = (
						SELECT SUM(rel.Quantita)
						FROM
							dbo.tblMagazziniMovimentiRigheRelazioni rel
							INNER JOIN dbo.tblMagazziniMovimentiRighe rc ON rel.Id = rc.Id
							INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
							INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
						WHERE
							rc.IdLotto = l.Id
							AND rp.Lock = 0
							AND mp.Lock = 0
					)
			) q
		WHERE
			l.Id = @Id
			AND l.Lock <= 2;

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

PRINT 'uspMagazziniLotti_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniLotti_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@IdArticolo CHAR(16) = NULL,
	@Aperto BIT = NULL,
	@Disabilitato BIT = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdArticolo = NULLIF(LTRIM(RTRIM(@IdArticolo)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MGC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è sempre quella del contesto della sessione (tblSessioni.IdSede): il chiamante non
		-- può indicarne un'altra. Contesto "tutte le sedi" (NULL o sedici zeri) = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT
			l.Id,
			StatoValore = 0,
			StatoDescrizione = 'OK',
			l.Nome,
			ArticoloNome = art.Nome,
			l.DataApertura,
			l.DataChiusura,
			l.QuantitaMax,
			Disponibilita = ISNULL(q.Caricato, 0) - ISNULL(q.Scaricato, 0),
			Disabilitato = ISNULL(l.Disabilitato, 0),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblMagazziniLotti l
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON l.IdSede = i.Id
			LEFT JOIN dbo.tblMagazziniArticoli art ON l.IdArticolo = art.Id
			-- Caricato: righe di carico confermate del lotto (le righe di scarico Manuale hanno anch'esse IdLotto: filtro sull'operazione); Scaricato: relazioni di scarichi
			-- confermati su quelle righe di carico (tblMagazziniMovimentiRigheRelazioni)
			OUTER APPLY (
				SELECT
					Caricato = (
						SELECT SUM(rc.Quantita)
						FROM
							dbo.tblMagazziniMovimentiRighe rc
							INNER JOIN dbo.tblMagazziniMovimenti mc ON rc.IdMovimento = mc.Id
						WHERE
							rc.IdLotto = l.Id
							AND mc.IdOperazione = 'C'
							AND rc.Lock = 0
							AND mc.Lock = 0
					),
					Scaricato = (
						SELECT SUM(rel.Quantita)
						FROM
							dbo.tblMagazziniMovimentiRigheRelazioni rel
							INNER JOIN dbo.tblMagazziniMovimentiRighe rc ON rel.Id = rc.Id
							INNER JOIN dbo.tblMagazziniMovimentiRighe rp ON rel.IdParent = rp.Id
							INNER JOIN dbo.tblMagazziniMovimenti mp ON rp.IdMovimento = mp.Id
						WHERE
							rc.IdLotto = l.Id
							AND rp.Lock = 0
							AND mp.Lock = 0
					)
			) q
		WHERE
			l.Lock = 0
			AND l.IdSede = @idSede
			AND (@IdArticolo IS NULL OR l.IdArticolo = @IdArticolo)
			AND (@Aperto IS NULL OR (@Aperto = 1 AND l.DataChiusura IS NULL) OR (@Aperto = 0 AND l.DataChiusura IS NOT NULL))
			AND (@Disabilitato IS NULL OR ISNULL(l.Disabilitato, 0) = @Disabilitato)
			AND (@Search IS NULL OR l.Nome LIKE '%' + @Search + '%')
		ORDER BY l.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
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
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspMagazziniLotti_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniLotti_del
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
			@IdFunzione = 'MGC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniLotti WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniLotti c
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON c.IdSede = i.Id
			WHERE c.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock FROM dbo.tblMagazziniLotti WHERE Id = @Id);

		IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE IdLotto = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un lotto con movimenti associati non può essere cancellato';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblMagazziniLotti
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Lotto non trovato o già eliminato';
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
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblMagazziniLotti
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
			SET @returnMessage = 'Il lotto è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
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

PRINT 'uspMagazziniLotti_get_ArticoliSelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniLotti_get_ArticoliSelectList
	@IdSede CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MGC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Elenco Articoli filtrato sulla stessa Azienda a cui appartiene la Sede indicata
		-- (Sede stessa se è l'Azienda, oppure la Sede padre se è una sede figlia), non su
		-- tblSessioni.IdAzienda: questa pagina lavora nel contesto Contesto.Sede, non Azienda.
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = CASE WHEN s.IdParent IS NULL THEN s.Id ELSE s.IdParent END
		FROM
			dbo.tblSedi s
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON s.Id = i.Id
		WHERE s.Id = @IdSede;

		IF @idAzienda IS NULL
		BEGIN
			SELECT TOP (0) Id = CAST(NULL AS CHAR(16)), [Text] = CAST(NULL AS VARCHAR(120)), Selected = CAST(0 AS BIT);
			GOTO BRANCH_END;
		END

		SELECT TOP (50)
			a.Id,
			[Text] = a.Nome + ISNULL(' (' + a.Codice + ')', ''),
			Selected = CAST(IIF(a.Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblMagazziniArticoli a
		WHERE
			a.IdSede = @idAzienda
			AND a.Lock = 0
			AND (@Search IS NULL OR a.Nome LIKE '%' + @Search + '%' OR a.Codice LIKE '%' + @Search + '%')
		ORDER BY a.Nome
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
		THROW 50001, @returnMessage, 1;
	END

END;
GO
