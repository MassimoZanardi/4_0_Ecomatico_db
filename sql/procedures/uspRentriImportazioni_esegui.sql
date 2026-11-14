SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: esecuzione definitiva. Scrive nel registro le registrazioni dell'anteprima, in un'unica
-- transazione (tutto o niente) con il registro bloccato come al salvataggio (R11.2 delle rettifiche):
--   1. rilancia l'analisi dentro la transazione (dati del registro e anagrafiche letti dopo il blocco);
--   2. registrazioni da importare: azione I. Con anomalie bloccanti (azione X) si procede solo con
--      @FinoAlPrimoProblema = 1, importando le registrazioni numerate prima della prima esclusa (registro senza buchi);
--   3. soggetti: autorizzazione abbinata (A, U), autorizzazione nuova su una sede esistente (N, U con sede), soggetto
--      nuovo con le sue autorizzazioni (C, uno per codice fiscale, dell'azienda interna del registro); per il produttore
--      senza numero l'autorizzazione "Nessuna" della sede; produttore assente su RENTRI ma previsto nella sede del
--      registro (ProduttoreSede): la "Nessuna" della sede del registro. Come uspSedi_ins/_upd e la migrazione 3.1;
--   4. movimenti e registrazioni con i valori trasmessi in origine (JsonValori), numero, data, identificativo e data di
--      trasmissione RENTRI: risultano già inviate e non si ritrasmettono (RentriIdentificativo/RentriData);
--   5. relazioni carico/scarico con le quantità dell'anteprima;
--   6. rettifiche e annullamenti (tblRentriRegistrazioniRettifiche) in ordine cronologico, con i valori operativi
--      calcolati come alla conferma nell'app (ufnRifiutiRegistrazioni_get_RettificaOperativa, come la migrazione 3.1).
-- Importazioni contemporanee: registri diversi non si aspettano, tranne per l'anagrafica. Due importazioni della stessa
-- azienda interna (registri diversi) si mettono in fila con un blocco applicativo sull'azienda, preso dopo il registro
-- e prima dell'analisi; un soggetto da creare che nel frattempo esiste già (stesso codice fiscale o partita IVA, unico
-- tra le sedi visibili) si riusa invece di crearne un doppione.
-- I JSON dell'area temporanea restano come storico, con l'Id della registrazione creata.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_esegui]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@FinoAlPrimoProblema BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @FinoAlPrimoProblema = ISNULL(@FinoAlPrimoProblema, 0);

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

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		DECLARE @idRegistro CHAR(16), @idSedeRegistro CHAR(16), @idAziendaInterna CHAR(16);
		SELECT
			@idRegistro = m.IdRegistro,
			@idSedeRegistro = g.IdSede,
			@idAziendaInterna = s.IdAziendaInterna
		FROM
			dbo.tblRentriImportazioni m
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			m.Id = @Id
			AND g.Lock = 0;

		IF @idRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Importazione non trovata';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16) = (SELECT IdUtente FROM dbo.tblSessioni WHERE Id = @IdSessione);
		DECLARE @adesso DATETIME2(0) = SYSDATETIME();

		BEGIN TRANSACTION;

			-- Registro bloccato per primo (R11.2, R11.4), poi l'importazione
			DECLARE @blocco INT;
			SELECT @blocco = 1
			FROM dbo.tblRifiutiRegistri WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @idRegistro;

			UPDATE dbo.tblRentriImportazioni WITH (UPDLOCK, HOLDLOCK)
			SET DataEsecuzione = DataEsecuzione
			WHERE Id = @Id AND Stato = 'P';

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'L''importazione è già stata eseguita';
				GOTO BRANCH_END;
			END

			-- Anagrafica: una importazione alla volta per azienda interna (stesso ordine per tutti: registro, poi azienda)
			DECLARE @risorsa NVARCHAR(255) = CONCAT(N'RentriImportazione_', @idAziendaInterna), @blocco2 INT;
			EXEC @blocco2 = sp_getapplock @Resource = @risorsa, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 20000; -- entro il limite di 30 s dei comandi dell'app: oltre, il messaggio qui sotto
			IF @blocco2 < 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Un''altra importazione della stessa azienda è in corso: riprovare tra qualche minuto';
				GOTO BRANCH_END;
			END

			EXEC dbo.uspRentriImportazioni_upd_Analisi @IdSessione = @IdSessione, @Id = @Id;

			-- ── 2. Registrazioni da importare ─────────────────────────────────────────────────────
			DECLARE @limiteAnno SMALLINT, @limiteProgressivo INT;
			SELECT TOP 1 @limiteAnno = Anno, @limiteProgressivo = Progressivo
			FROM dbo.tblRentriImportazioniMovimenti
			WHERE IdImportazione = @Id AND Azione = 'X'
			ORDER BY Anno, Progressivo;

			IF @limiteAnno IS NOT NULL AND @FinoAlPrimoProblema = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Ci sono registrazioni escluse: risolvere le anomalie oppure importare fino al primo problema';
				GOTO BRANCH_END;
			END

			SELECT
				m.Anno, m.Progressivo, m.Identificativo, m.Tipo, m.RettificaAnno, m.RettificaProgressivo, m.Data, m.DataTrasmissione,
				m.IdOperazione, m.IdEer, m.IdMateriale, m.IdStatoFisico, m.IdUnitaMisura, Quantita = CAST(m.Quantita AS DECIMAL(18, 2)),
				m.JsonValori,
				o.Operazione, IsProduttore = ISNULL(o.IsProduttore, 0), ProduttoreSede = ISNULL(o.ProduttoreSede, 0),
				IsEsito = ISNULL(o.IsEsito, 0),
				IdMovimento = CAST(NULL AS CHAR(16)), IdRegistrazione = CAST(NULL AS CHAR(16))
			INTO #imp
			FROM
				dbo.tblRentriImportazioniMovimenti m
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			WHERE
				m.IdImportazione = @Id
				AND m.Azione = 'I'
				AND (@limiteAnno IS NULL OR m.Anno < @limiteAnno OR (m.Anno = @limiteAnno AND m.Progressivo < @limiteProgressivo));

			IF NOT EXISTS (SELECT 1 FROM #imp)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Nessuna registrazione da importare';
				GOTO BRANCH_END;
			END

			CREATE UNIQUE CLUSTERED INDEX IX_imp ON #imp (Anno, Progressivo);

			-- Id nuovi, nello stesso formato di uspId_get, registrati in tblId e tblIdLog (inserimento dell'utente)
			CREATE TABLE #id (Chiave VARCHAR(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY, Id CHAR(16) COLLATE DATABASE_DEFAULT NULL);

			-- ── 3. Soggetti ───────────────────────────────────────────────────────────────────────
			SELECT DISTINCT
				x.Id, x.Ruolo, x.CodiceFiscale, x.Numero, x.Stato, x.IdAutorizzazione, x.IdSede, x.Nome, x.PartitaIva, x.IdNazione,
				x.IdComune, x.Localita, x.CAP, x.Indirizzo, x.NumeroCivico,
				IdSedeFinale = CAST(NULL AS CHAR(16)), IdAutorizzazioneFinale = CAST(NULL AS CHAR(16))
			INTO #sogg
			FROM
				dbo.tblRentriImportazioniMovimentiSoggetti ms
				INNER JOIN #imp i ON ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo
				INNER JOIN dbo.tblRentriImportazioniSoggetti x ON ms.IdSoggetto = x.Id
			WHERE ms.IdImportazione = @Id;

			IF EXISTS (SELECT 1 FROM #sogg WHERE Stato = 'M')
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Ci sono soggetti da completare';
				GOTO BRANCH_END;
			END

			UPDATE #sogg SET IdAutorizzazioneFinale = IdAutorizzazione WHERE Stato IN ('A', 'U') AND IdAutorizzazione IS NOT NULL;
			UPDATE #sogg SET IdSedeFinale = IdSede WHERE IdAutorizzazioneFinale IS NULL AND IdSede IS NOT NULL;

			-- Soggetti nuovi (C): uno per codice fiscale, con i dati del primo completamento
			SELECT
				CodiceFiscale,
				Nome = MIN(Nome), PartitaIva = MIN(PartitaIva), IdNazione = ISNULL(MIN(IdNazione), '380'), IdComune = MIN(IdComune),
				Localita = MIN(Localita), CAP = MIN(CAP), Indirizzo = MIN(Indirizzo), NumeroCivico = MIN(NumeroCivico)
			INTO #nuoviSoggetti
			FROM #sogg
			WHERE Stato = 'C'
			GROUP BY CodiceFiscale;

			-- Soggetto creato nel frattempo (da un'altra importazione o a mano): si riusa la sede se è l'unica con quel codice
			SELECT n.CodiceFiscale, IdSede = MIN(s.Id)
			INTO #esistenti
			FROM
				#nuoviSoggetti n
				INNER JOIN dbo.tblSedi s ON UPPER(s.CodiceFiscale) = n.CodiceFiscale OR UPPER(s.PartitaIva) = n.CodiceFiscale
				INNER JOIN dbo.ufnSedi_get_SediByUtente_List(@idUtente) u ON u.Id = s.Id
			WHERE
				s.Disabilitata = 0
				AND s.Lock < 2
				AND u.Disabilitata = 0
				AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
			GROUP BY n.CodiceFiscale
			HAVING COUNT(DISTINCT s.Id) = 1;

			UPDATE x
			SET IdSedeFinale = e.IdSede
			FROM
				#sogg x
				INNER JOIN #esistenti e ON e.CodiceFiscale = x.CodiceFiscale
			WHERE
				x.Stato = 'C'
				AND x.IdAutorizzazioneFinale IS NULL;

			DELETE n
			FROM #nuoviSoggetti n
			WHERE EXISTS (SELECT 1 FROM #esistenti e WHERE e.CodiceFiscale = n.CodiceFiscale);

			INSERT #id (Chiave)
			SELECT 'S:' + CodiceFiscale FROM #nuoviSoggetti
			UNION ALL
			SELECT 'X:' + CodiceFiscale FROM #nuoviSoggetti;

			-- Produttore della sede del registro: per le registrazioni senza produttore su RENTRI ma con il produttore
			-- previsto nella sede del registro (ProduttoreSede), come uspRifiutiRegistrazioni_upd
			DECLARE @serveNessunaRegistro BIT = IIF(EXISTS (
				SELECT 1
				FROM #imp i
				WHERE
					i.IsProduttore = 1
					AND i.ProduttoreSede = 1
					AND NOT EXISTS (
						SELECT 1
						FROM dbo.tblRentriImportazioniMovimentiSoggetti ms
						WHERE ms.IdImportazione = @Id AND ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo AND ms.Ruolo = 'P')), 1, 0);

			-- Autorizzazioni da usare o creare, una per sede, ruolo e numero (produttore senza numero: "Nessuna")
			SELECT DISTINCT
				IdSede = ISNULL(s.IdSedeFinale, 'S:' + s.CodiceFiscale),
				s.Ruolo,
				s.Numero,
				IdAutorizzazione = CAST(NULL AS CHAR(16))
			INTO #aut
			FROM #sogg s
			WHERE s.IdAutorizzazioneFinale IS NULL;

			IF @serveNessunaRegistro = 1 AND NOT EXISTS (SELECT 1 FROM #aut WHERE IdSede = @idSedeRegistro AND Ruolo = 'P' AND Numero = '')
				INSERT #aut (IdSede, Ruolo, Numero) VALUES (@idSedeRegistro, 'P', '');

			-- Autorizzazioni già esistenti sulle sedi esistenti
			UPDATE a
			SET IdAutorizzazione = (
				SELECT TOP 1 z.Id
				FROM dbo.tblRifiutiAutorizzazioni z
				WHERE
					z.IdSede = a.IdSede
					AND z.Lock < 2
					AND z.Disabilitata = 0
					AND (
						(a.Numero = '' AND a.Ruolo = 'P' AND z.Nessuna = 1)
						OR (a.Numero <> '' AND z.IdRuolo = a.Ruolo AND ISNULL(z.Nessuna, 0) = 0 AND UPPER(REPLACE(z.Numero, ' ', '')) = a.Numero))
				ORDER BY z.Lock, z.Id)
			FROM #aut a
			WHERE a.IdSede NOT LIKE 'S:%';

			INSERT #id (Chiave)
			SELECT CONCAT('A:', IdSede, ':', Ruolo, ':', Numero)
			FROM #aut
			WHERE IdAutorizzazione IS NULL;

			-- Movimenti e registrazioni
			INSERT #id (Chiave)
			SELECT CONCAT('M:', Anno, '/', Progressivo) FROM #imp
			UNION ALL
			SELECT CONCAT('R:', Anno, '/', Progressivo) FROM #imp;

			UPDATE #id SET Id = LOWER(LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 16));

			DECLARE @tentativi INT = 0;
			WHILE @tentativi < 10
			BEGIN
				;WITH doppi AS (
					SELECT Chiave, n = ROW_NUMBER() OVER (PARTITION BY Id ORDER BY Chiave)
					FROM #id
				)
				UPDATE i
				SET Id = LOWER(LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 16))
				FROM
					#id i
					INNER JOIN doppi d ON i.Chiave = d.Chiave
				WHERE
					d.n > 1
					OR i.Id LIKE '000000000000000[0-9a-f]'
					OR EXISTS (SELECT 1 FROM dbo.tblId t WITH (UPDLOCK, HOLDLOCK) WHERE t.Id = i.Id);

				IF @@ROWCOUNT = 0 BREAK;
				SET @tentativi += 1;
			END

			IF @tentativi >= 10
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Impossibile generare Id univoci';
				GOTO BRANCH_END;
			END

			INSERT dbo.tblId (Id) SELECT Id FROM #id;
			INSERT dbo.tblIdLog (Id, Operazione, [Data], IdUtente) SELECT Id, 'I', @adesso, @idUtente FROM #id;

			-- Soggetti nuovi: sede esterna radice dell'azienda interna del registro, con indirizzo (come uspSedi_ins/_upd)
			INSERT dbo.tblOsepe (Id, Tipo)
			SELECT k.Id, 'S'
			FROM #nuoviSoggetti n INNER JOIN #id k ON k.Chiave = 'S:' + n.CodiceFiscale;

			INSERT dbo.tblSedi (Id, IdParent, InternaEsterna, IdTipo, Nome, Cognome, CodiceFiscale, PartitaIva, Codice, Note, Disabilitata, UnitaLocale, Lock)
			SELECT
				k.Id, NULL, 'E', IIF(n.PartitaIva IS NULL, 'P', 'L'), n.Nome, NULL, n.CodiceFiscale, n.PartitaIva, NULL,
				'Creato dall''importazione delle registrazioni da RENTRI', 0, 1, 0
			FROM #nuoviSoggetti n INNER JOIN #id k ON k.Chiave = 'S:' + n.CodiceFiscale;

			INSERT dbo.tblSediEsterne (Id, IdSedeInterna)
			SELECT k.Id, @idAziendaInterna
			FROM #nuoviSoggetti n INNER JOIN #id k ON k.Chiave = 'S:' + n.CodiceFiscale;

			INSERT dbo.tblIndirizzi (Id, Indirizzo, NumeroCivico, CAP, Localita, IdComune, IdNazione)
			SELECT k.Id, n.Indirizzo, n.NumeroCivico, n.CAP, n.Localita, n.IdComune, n.IdNazione
			FROM #nuoviSoggetti n INNER JOIN #id k ON k.Chiave = 'X:' + n.CodiceFiscale;

			INSERT dbo.tblSediIndirizzi (Id, IdIndirizzo)
			SELECT ks.Id, ki.Id
			FROM
				#nuoviSoggetti n
				INNER JOIN #id ks ON ks.Chiave = 'S:' + n.CodiceFiscale
				INNER JOIN #id ki ON ki.Chiave = 'X:' + n.CodiceFiscale;

			UPDATE s
			SET
				NomeCompleto = COALESCE(s.Cognome + ' ' + s.Nome, s.Nome),
				IndirizzoCompleto = CASE WHEN i.IdNazione = '380' THEN ISNULL(i.Indirizzo + ISNULL(', ' + i.NumeroCivico, '') + ' - ', '') + ISNULL(i.Localita + ' - ', '') + ISNULL(i.CAP + ' ', '') + ISNULL(c.Nome + ' (' + p.Sigla + ')', '') ELSE ISNULL(i.Indirizzo + ISNULL(', ' + i.NumeroCivico, '') + ' - ', '') + ISNULL(i.CAP + ' ', '') + ISNULL(i.Localita + ' ', '') + ISNULL(na.Nome, '') END,
				IdAziendaInterna = @idAziendaInterna
			FROM
				#nuoviSoggetti n
				INNER JOIN #id k ON k.Chiave = 'S:' + n.CodiceFiscale
				INNER JOIN dbo.tblSedi s ON s.Id = k.Id
				INNER JOIN dbo.tblSediIndirizzi si ON s.Id = si.Id
				INNER JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
				LEFT JOIN dbo.tblComuni c ON i.IdComune = c.Id
				LEFT JOIN dbo.tblProvince p ON c.IdProvincia = p.Id
				LEFT JOIN dbo.tblNazioni na ON i.IdNazione = na.Id;

			-- Autorizzazioni nuove: dati di RENTRI (ruolo e numero); tipo, date e codici EER si completano in anagrafica
			UPDATE a
			SET IdAutorizzazione = k.Id
			FROM
				#aut a
				INNER JOIN #id k ON k.Chiave = CONCAT('A:', a.IdSede, ':', a.Ruolo, ':', a.Numero)
			WHERE a.IdAutorizzazione IS NULL;

			INSERT dbo.tblRifiutiAutorizzazioni
				(Id, IdSede, IdRuolo, IdTipo, IdNumeroTipo, Numero, Identificativo, DataInizio, DataFine, Note, Nessuna, Disabilitata, Lock)
			SELECT
				a.IdAutorizzazione,
				ISNULL(ks.Id, a.IdSede),
				a.Ruolo,
				NULL,
				IIF(a.Numero <> '' AND a.Ruolo IN ('T', 'I'), 'A', NULL),
				NULLIF(a.Numero, ''),
				NULL,
				IIF(a.Numero = '' AND a.Ruolo = 'P', '19000101', NULL),
				IIF(a.Numero = '' AND a.Ruolo = 'P', '20501231', NULL),
				IIF(a.Numero = '' AND a.Ruolo = 'P', NULL, 'Creata dall''importazione delle registrazioni da RENTRI: completare tipo, date e codici EER'),
				IIF(a.Numero = '' AND a.Ruolo = 'P', 1, 0),
				0,
				0
			FROM
				#aut a
				INNER JOIN #id k ON k.Chiave = CONCAT('A:', a.IdSede, ':', a.Ruolo, ':', a.Numero)
				LEFT JOIN #id ks ON a.IdSede = ks.Chiave;

			UPDATE s
			SET IdAutorizzazioneFinale = a.IdAutorizzazione
			FROM
				#sogg s
				INNER JOIN #aut a ON a.IdSede = ISNULL(s.IdSedeFinale, 'S:' + s.CodiceFiscale) AND a.Ruolo = s.Ruolo AND a.Numero = s.Numero
			WHERE s.IdAutorizzazioneFinale IS NULL;

			IF EXISTS (SELECT 1 FROM #sogg WHERE IdAutorizzazioneFinale IS NULL)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Autorizzazione di un soggetto non risolta';
				GOTO BRANCH_END;
			END

			DECLARE @idNessunaRegistro CHAR(16) = (SELECT TOP 1 IdAutorizzazione FROM #aut WHERE IdSede = @idSedeRegistro AND Ruolo = 'P' AND Numero = '');

			-- ── 4. Movimenti e registrazioni ──────────────────────────────────────────────────────
			UPDATE i
			SET
				IdMovimento = km.Id,
				IdRegistrazione = kr.Id
			FROM
				#imp i
				INNER JOIN #id km ON km.Chiave = CONCAT('M:', i.Anno, '/', i.Progressivo)
				INNER JOIN #id kr ON kr.Chiave = CONCAT('R:', i.Anno, '/', i.Progressivo);

			SELECT
				i.Anno, i.Progressivo,
				IdAttivita = (SELECT TOP 1 t.Id FROM dbo.tblRifiutiAttivitaRecuperoSmaltimento t WHERE t.Codice = j.Attivita),
				IdProvenienza = (SELECT TOP 1 t.Id FROM dbo.tblRifiutiProvenienze t WHERE t.Id = j.Provenienza),
				EerDescrizione = NULLIF(j.EerDescrizione, ''),
				FormularioNumero = NULLIF(j.NumeroFir, ''),
				-- RENTRI usa 0001-01-01 come data assente
				DataInizioTrasporto = IIF(TRY_CONVERT(DATETIMEOFFSET(0), j.DataInizioTrasporto) BETWEEN '19000102' AND '20790601',
					CONVERT(SMALLDATETIME, TRY_CONVERT(DATETIMEOFFSET(0), j.DataInizioTrasporto) AT TIME ZONE 'W. Europe Standard Time'), NULL),
				IdTrasportoTransfrontalieroTipo = (SELECT TOP 1 t.Id FROM dbo.tblRifiutiTrasportiTransfrontalieriTipi t WHERE t.Codice = j.TipoTransfrontaliero),
				IdRaee = (SELECT TOP 1 t.Id FROM dbo.tblRifiutiRaee t WHERE t.Codice = JSON_VALUE(i.JsonValori, '$.rifiuto.categorie_aee[0]')),
				MaterialeDescrizione = NULLIF(j.MaterialeDescrizione, ''),
				VeicoloFuoriUso = ISNULL(j.VeicoloFuoriUso, 0),
				VeicoloFuoriUsoNumero = NULLIF(j.VeicoloNumero, ''),
				VeicoloFuoriUsoData = IIF(TRY_CONVERT(DATE, LEFT(j.VeicoloData, 10)) > '19000101', TRY_CONVERT(DATE, LEFT(j.VeicoloData, 10)), NULL),
				Note = NULLIF(j.Annotazioni, ''),
				-- Esito solo per le operazioni che lo prevedono
				IdEsito = IIF(i.IsEsito = 1 AND j.Esito IS NOT NULL, CASE j.RespingimentoTipo WHEN 'T' THEN 'R' WHEN 'P' THEN 'P' ELSE 'A' END, NULL),
				IdCausaleRespingimento = IIF(i.IsEsito = 1, (SELECT TOP 1 t.Id FROM dbo.tblRifiutiRegistrazioniEsitiCausaliRespingimento t WHERE t.Codice = j.RespingimentoCausale), NULL),
				CausaleRespingimentoAltro = IIF(i.IsEsito = 1, NULLIF(j.RespingimentoCausaleAltro, ''), NULL),
				QuantitaRespinta = IIF(i.IsEsito = 1, TRY_CONVERT(DECIMAL(18, 2), j.RespingimentoQuantita), NULL),
				IdUnitaMisuraQuantitaRespinta = IIF(i.IsEsito = 1, (SELECT TOP 1 t.Id FROM dbo.tblUnitaMisura t WHERE t.Codice = j.RespingimentoUnitaMisura), NULL),
				DataFineTrasporto = IIF(i.IsEsito = 1 AND TRY_CONVERT(DATETIMEOFFSET(0), j.DataFineTrasporto) BETWEEN '19000102' AND '20790601',
					CONVERT(SMALLDATETIME, TRY_CONVERT(DATETIMEOFFSET(0), j.DataFineTrasporto) AT TIME ZONE 'W. Europe Standard Time'), NULL),
				QuantitaVerificata = IIF(i.IsEsito = 1, TRY_CONVERT(DECIMAL(18, 2), j.PesoVerificato), NULL)
			INTO #valori
			FROM
				#imp i
				CROSS APPLY OPENJSON(i.JsonValori)
				WITH (
					Attivita VARCHAR(5) '$.rifiuto.destinato_attivita',
					Provenienza VARCHAR(5) '$.rifiuto.provenienza',
					EerDescrizione VARCHAR(200) '$.rifiuto.descrizione_eer',
					NumeroFir VARCHAR(20) '$.integrazione_fir.numero_fir',
					DataInizioTrasporto VARCHAR(40) '$.integrazione_fir.data_inizio_trasporto',
					TipoTransfrontaliero VARCHAR(5) '$.integrazione_fir.tipo_trasporto_transfrontaliero',
					MaterialeDescrizione VARCHAR(200) '$.materiali.descrizione_materiale',
					VeicoloFuoriUso BIT '$.rifiuto.veicolo_fuori_uso',
					VeicoloNumero VARCHAR(50) '$.rifiuto.veicolo_fuori_uso_reg_pubblica_sicurezza.numero',
					VeicoloData VARCHAR(40) '$.rifiuto.veicolo_fuori_uso_reg_pubblica_sicurezza.data',
					Annotazioni VARCHAR(500) '$.annotazioni',
					Esito NVARCHAR(MAX) '$.esito' AS JSON,
					RespingimentoTipo VARCHAR(5) '$.esito.respingimento.tipo',
					RespingimentoCausale VARCHAR(5) '$.esito.respingimento.causale',
					RespingimentoCausaleAltro VARCHAR(100) '$.esito.respingimento.causale_altro',
					RespingimentoQuantita VARCHAR(40) '$.esito.respingimento.quantita.valore',
					RespingimentoUnitaMisura VARCHAR(5) '$.esito.respingimento.quantita.unita_misura',
					DataFineTrasporto VARCHAR(40) '$.esito.data_fine_trasporto',
					PesoVerificato VARCHAR(40) '$.esito.peso_verificato_destino'
				) j;

			INSERT dbo.tblRifiutiMovimenti
				(Id, IdRegistro, IdOperazione, IdEer, IdStatoFisico, IdAttivita, IdUnitaMisura, IdProvenienza, Quantita, EerDescrizione,
				 FormularioNumero, DataInizioTrasporto)
			SELECT
				i.IdMovimento, @idRegistro, i.IdOperazione, i.IdEer, i.IdStatoFisico, v.IdAttivita, i.IdUnitaMisura, v.IdProvenienza, i.Quantita,
				v.EerDescrizione, v.FormularioNumero, v.DataInizioTrasporto
			FROM
				#imp i
				INNER JOIN #valori v ON v.Anno = i.Anno AND v.Progressivo = i.Progressivo;

			INSERT dbo.tblRifiutiRegistrazioni
				(Id, IdMovimento, IdEsito, IdRaee, IdCausaleRespingimento, IdTrasportoTransfrontalieroTipo, IdMateriale, IdAttivitaProvenienza,
				 IdUnitaMisuraQuantitaRespinta, CausaleRespingimentoAltro, QuantitaRespinta, DataFineTrasporto, Operazione, [Data], Numero,
				 QuantitaVerificata, VeicoloFuoriUso, VeicoloFuoriUsoNumero, VeicoloFuoriUsoData, MaterialeDescrizione, RentriIdentificativo,
				 RentriData, Note, Lock)
			SELECT
				i.IdRegistrazione, i.IdMovimento, v.IdEsito, v.IdRaee, v.IdCausaleRespingimento, v.IdTrasportoTransfrontalieroTipo, i.IdMateriale, NULL,
				v.IdUnitaMisuraQuantitaRespinta, v.CausaleRespingimentoAltro, v.QuantitaRespinta, v.DataFineTrasporto, i.Operazione, i.[Data], i.Progressivo,
				v.QuantitaVerificata, v.VeicoloFuoriUso, v.VeicoloFuoriUsoNumero, v.VeicoloFuoriUsoData, v.MaterialeDescrizione, i.Identificativo,
				i.DataTrasmissione, v.Note, 0
			FROM
				#imp i
				INNER JOIN #valori v ON v.Anno = i.Anno AND v.Progressivo = i.Progressivo;

			-- Caratteristiche di pericolo
			INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
			SELECT DISTINCT i.IdMovimento, c.Id
			FROM
				#imp i
				CROSS APPLY OPENJSON(i.JsonValori, '$.rifiuto.caratteristiche_pericolo') h
				INNER JOIN dbo.tblRifiutiClassiPericolo c ON c.Codice = h.value;

			-- Ruoli (come la migrazione 3.1 e uspRifiutiRegistrazioni_upd)
			INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
			SELECT i.IdMovimento, s.IdAutorizzazioneFinale, i.Quantita, 0
			FROM
				#imp i
				INNER JOIN dbo.tblRentriImportazioniMovimentiSoggetti ms ON ms.IdImportazione = @Id AND ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo AND ms.Ruolo = 'P'
				INNER JOIN #sogg s ON ms.IdSoggetto = s.Id
			UNION ALL
			SELECT i.IdMovimento, @idNessunaRegistro, i.Quantita, 0
			FROM #imp i
			WHERE
				i.IsProduttore = 1
				AND i.ProduttoreSede = 1
				AND @idNessunaRegistro IS NOT NULL
				AND NOT EXISTS (
					SELECT 1
					FROM dbo.tblRentriImportazioniMovimentiSoggetti ms
					WHERE ms.IdImportazione = @Id AND ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo AND ms.Ruolo = 'P');

			INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
			SELECT i.IdMovimento, s.IdAutorizzazioneFinale, 0
			FROM
				#imp i
				INNER JOIN dbo.tblRentriImportazioniMovimentiSoggetti ms ON ms.IdImportazione = @Id AND ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo AND ms.Ruolo = 'D'
				INNER JOIN #sogg s ON ms.IdSoggetto = s.Id;

			INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, Pos, IdTipo)
			SELECT i.IdMovimento, s.IdAutorizzazioneFinale, ms.Pos - 1, NULL
			FROM
				#imp i
				INNER JOIN dbo.tblRentriImportazioniMovimentiSoggetti ms ON ms.IdImportazione = @Id AND ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo AND ms.Ruolo = 'T'
				INNER JOIN #sogg s ON ms.IdSoggetto = s.Id;

			INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
			SELECT i.IdMovimento, s.IdAutorizzazioneFinale, ms.Pos - 1
			FROM
				#imp i
				INNER JOIN dbo.tblRentriImportazioniMovimentiSoggetti ms ON ms.IdImportazione = @Id AND ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo AND ms.Ruolo = 'I'
				INNER JOIN #sogg s ON ms.IdSoggetto = s.Id;

			-- Sedi del movimento dalle autorizzazioni dei ruoli, come uspRifiutiRegistrazioni_upd
			UPDATE m
			SET
				IdSedeProduttoreDetentore = ap.IdSede,
				IdSedeDestinatario = ad.IdSede,
				IdSedeTrasportatore1 = ar.IdSede,
				IdSedeIntermediario1 = ai.IdSede
			FROM
				#imp x
				INNER JOIN dbo.tblRifiutiMovimenti m ON x.IdMovimento = m.Id
				LEFT JOIN dbo.tblRifiutiMovimentiProduttori p ON p.Id = m.Id AND p.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ap ON p.IdAutorizzazione = ap.Id
				LEFT JOIN dbo.tblRifiutiMovimentiDestinatari d ON d.Id = m.Id AND d.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ad ON d.IdAutorizzazione = ad.Id
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori t ON t.Id = m.Id AND t.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ar ON t.IdAutorizzazione = ar.Id
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari n ON n.Id = m.Id AND n.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ai ON n.IdAutorizzazione = ai.Id;

			-- ── 5. Relazioni carico/scarico ───────────────────────────────────────────────────────
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRentriImportazioniRelazioni l
					INNER JOIN #imp p ON p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
					LEFT JOIN #imp f ON f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
				WHERE
					l.IdImportazione = @Id
					AND f.Anno IS NULL
					AND l.IdRegistrazioneFiglio IS NULL)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Una registrazione da importare è associata a una registrazione che non viene importata';
				GOTO BRANCH_END;
			END

			INSERT dbo.tblRifiutiRegistrazioniRelazioni (Id, IdParent, Operazione, Quantita, Pos)
			SELECT
				ISNULL(f.IdRegistrazione, l.IdRegistrazioneFiglio),
				p.IdRegistrazione,
				p.Operazione,
				CAST(ISNULL(l.Quantita, 0) AS DECIMAL(18, 2)),
				ROW_NUMBER() OVER (PARTITION BY p.IdRegistrazione ORDER BY l.FiglioAnno, l.FiglioProgressivo) - 1
			FROM
				dbo.tblRentriImportazioniRelazioni l
				INNER JOIN #imp p ON p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
				LEFT JOIN #imp f ON f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
			WHERE l.IdImportazione = @Id;

			-- ── 6. Rettifiche e annullamenti, in ordine cronologico ────────────────────────────────
			DECLARE @idOriginale CHAR(16), @idRettifica CHAR(16), @annullata BIT;

			DECLARE cr CURSOR LOCAL FAST_FORWARD FOR
				SELECT
					ISNULL(o.IdRegistrazione, om.IdRegistrazione),
					r.IdRegistrazione,
					IIF(r.Tipo = 'A', 1, 0)
				FROM
					#imp r
					LEFT JOIN #imp o ON o.Anno = r.RettificaAnno AND o.Progressivo = r.RettificaProgressivo
					LEFT JOIN dbo.tblRentriImportazioniMovimenti om
						ON om.IdImportazione = @Id AND om.Anno = r.RettificaAnno AND om.Progressivo = r.RettificaProgressivo AND om.Azione = 'P'
				WHERE r.Tipo IN ('R', 'A')
				ORDER BY r.[Data], r.Anno, r.Progressivo;

			OPEN cr;
			FETCH cr INTO @idOriginale, @idRettifica, @annullata;
			WHILE @@FETCH_STATUS = 0
			BEGIN
				IF @idOriginale IS NULL
				BEGIN
					CLOSE cr;
					DEALLOCATE cr;
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Registrazione originale di una rettifica non trovata';
					GOTO BRANCH_END;
				END

				INSERT dbo.tblRentriRegistrazioniRettifiche (Id, IdRettifica, Annullata)
				VALUES (@idOriginale, @idRettifica, @annullata);

				IF @annullata = 1
					UPDATE t
					SET
						t.IdEer = o.IdEer,
						t.EerDescrizione = o.EerDescrizione,
						t.IdStatoFisico = o.IdStatoFisico,
						t.IdUnitaMisura = o.IdUnitaMisura,
						t.Quantita = IIF(o.IsOperativa = 1, 0, o.Quantita)
					FROM
						dbo.tblRentriRegistrazioniRettifiche t
						CROSS APPLY dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(t.IdRettifica, NULL, NULL, NULL, NULL) o
					WHERE t.IdRettifica = @idRettifica;
				ELSE
					UPDATE t
					SET
						t.IdEer = IIF(o.IsOperativa = 1, m.IdEer, o.IdEer),
						t.EerDescrizione = IIF(o.IsOperativa = 1, m.EerDescrizione, o.EerDescrizione),
						t.IdStatoFisico = IIF(o.IsOperativa = 1, m.IdStatoFisico, o.IdStatoFisico),
						t.IdUnitaMisura = IIF(o.IsOperativa = 1, m.IdUnitaMisura, o.IdUnitaMisura),
						t.Quantita = IIF(o.IsOperativa = 1, m.Quantita, o.Quantita)
					FROM
						dbo.tblRentriRegistrazioniRettifiche t
						INNER JOIN dbo.tblRifiutiRegistrazioni r ON t.IdRettifica = r.Id
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
						CROSS APPLY dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(t.IdRettifica, m.IdEer, m.IdStatoFisico, m.IdUnitaMisura, m.Quantita) o
					WHERE t.IdRettifica = @idRettifica;

				FETCH cr INTO @idOriginale, @idRettifica, @annullata;
			END
			CLOSE cr;
			DEALLOCATE cr;

			-- ── 7. Storico ────────────────────────────────────────────────────────────────────────
			UPDATE m
			SET IdRegistrazione = i.IdRegistrazione
			FROM
				dbo.tblRentriImportazioniMovimenti m
				INNER JOIN #imp i ON m.Anno = i.Anno AND m.Progressivo = i.Progressivo
			WHERE m.IdImportazione = @Id;

			UPDATE dbo.tblRentriImportazioni
			SET
				Stato = 'E',
				FinoAlPrimoProblema = @FinoAlPrimoProblema,
				DataEsecuzione = @adesso
			WHERE Id = @Id;

			DECLARE
				@importate INT = (SELECT COUNT(*) FROM #imp),
				@soggettiCreati INT = (SELECT COUNT(*) FROM #nuoviSoggetti),
				@autorizzazioniCreate INT = (SELECT COUNT(*) FROM #aut a INNER JOIN #id k ON k.Chiave = CONCAT('A:', a.IdSede, ':', a.Ruolo, ':', a.Numero)),
				@relazioni INT = (SELECT COUNT(*) FROM dbo.tblRifiutiRegistrazioniRelazioni x INNER JOIN #imp p ON x.IdParent = p.IdRegistrazione),
				@rettifiche INT = (SELECT COUNT(*) FROM #imp WHERE Tipo IN ('R', 'A'));

		COMMIT TRANSACTION;

		SELECT
			ReturnValue = @returnValue,
			Importate = @importate,
			GiaPresenti = (SELECT COUNT(*) FROM dbo.tblRentriImportazioniMovimenti WHERE IdImportazione = @Id AND Azione = 'P'),
			NonImportate = (SELECT COUNT(*) FROM dbo.tblRentriImportazioniMovimenti WHERE IdImportazione = @Id AND Azione IN ('I', 'X') AND IdRegistrazione IS NULL),
			Rettifiche = @rettifiche,
			Relazioni = @relazioni,
			SoggettiCreati = @soggettiCreati,
			AutorizzazioniCreate = @autorizzazioniCreate,
			PrimaEsclusaAnno = @limiteAnno,
			PrimaEsclusaProgressivo = @limiteProgressivo;

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
