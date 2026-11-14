SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: analisi dei movimenti letti da RENTRI (area temporanea) rispetto al registro di
-- destinazione. Si può rilanciare a piacere finché l'importazione non è eseguita: ricalcola da zero i campi
-- letti dai JSON, l'azione di ogni movimento e le anomalie. I JSON originali (Json, JsonDettaglio) non si toccano.
--
-- Come RENTRI rappresenta le rettifiche (verificato sulla sandbox il 2026-11-14): la registrazione di rettifica o
-- di annullamento porta solo i propri riferimenti (numero, data, numero_registrazione_rettifica = originale), mai i
-- valori. I valori stanno negli stati dell'originale (dettaglio: stato corrente + array variazioni): ogni stato
-- indica con numero_registrazione_di_rettifica la rettifica che l'ha prodotto; lo stato senza quel riferimento è
-- quello trasmesso in origine; lo stato prodotto da un annullamento ha annullato = true e le annotazioni.
--
-- Valori da importare (JsonValori), mai lo stato corrente rettificato al posto dell'originale:
--   - movimento mai rettificato né annullato: il movimento stesso;
--   - originale rettificato o annullato: lo stato senza numero_registrazione_di_rettifica; per un originale solo
--     annullato, se il dettaglio non c'è, il movimento stesso (l'annullamento non cambia i valori);
--   - rettifica o annullamento: lo stato dell'originale prodotto da questa rettifica.
-- Numero, data e data di trasmissione sono sempre quelli del movimento stesso (Json).
--
-- Tipo: M movimento, R rettifica di correzione, A annullamento (stato prodotto con annullato = true).
-- Azione: I da importare, P già presente in Ecomatico (stesso identificativo RENTRI nel registro), X esclusa per
-- un'anomalia bloccante. Anomalie: E bloccante, W avviso, I informazione.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_upd_Analisi]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

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
		DECLARE @idRegistro CHAR(16), @stato CHAR(1), @dalAnno SMALLINT, @dalNumero INT;
		SELECT
			@idRegistro = m.IdRegistro,
			@stato = m.Stato,
			@dalAnno = m.DalAnno,
			@dalNumero = m.DalNumero
		FROM
			dbo.tblRentriImportazioni m
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE m.Id = @Id;

		IF @idRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Importazione non trovata';
			GOTO BRANCH_END;
		END
		IF @stato <> 'P'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importazione è già stata eseguita';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Blocca la riga dell'importazione: due analisi contemporanee si mettono in fila
			UPDATE dbo.tblRentriImportazioni WITH (UPDLOCK, HOLDLOCK)
			SET DataAnalisi = SYSDATETIME()
			WHERE Id = @Id;

			-- ── 1. Riferimenti del movimento stesso (numero, data, trasmissione, originale rettificato) ──
			-- La data di registrazione è quella italiana; se cambia anno rispetto alla numerazione (registrazione
			-- vicino alla mezzanotte del 31 dicembre) si usa la data UTC, con cui RENTRI ha numerato
			UPDATE m
			SET
				RettificaAnno = j.RettificaAnno,
				RettificaProgressivo = j.RettificaProgressivo,
				Tipo = IIF(j.RettificaProgressivo IS NULL, 'M', 'R'),
				DataOra = d.DataOraLocale,
				Data = IIF(YEAR(d.DataOraLocale) <> m.Anno AND YEAR(d.DataOraUtc) = m.Anno, CAST(d.DataOraUtc AS DATE), CAST(d.DataOraLocale AS DATE)),
				DataTrasmissione = CONVERT(DATETIME2(0), TRY_CONVERT(DATETIMEOFFSET(0), j.DataTrasmissione) AT TIME ZONE 'W. Europe Standard Time'),
				IsAnnullato = ISNULL(j.Annullato, 0),
				IsRettificato = ISNULL(j.Rettificato, 0),
				JsonValori = NULL
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY OPENJSON(m.Json)
				WITH (
					RettificaAnno SMALLINT '$.riferimenti.numero_registrazione_rettifica.anno',
					RettificaProgressivo INT '$.riferimenti.numero_registrazione_rettifica.progressivo',
					DataOra VARCHAR(40) '$.riferimenti.data_ora_registrazione',
					DataTrasmissione VARCHAR(40) '$.riferimenti.data_trasmissione',
					Annullato BIT '$.annullato',
					Rettificato BIT '$.rettificato'
				) j
				CROSS APPLY (
					SELECT
						DataOraUtc = CONVERT(DATETIME2(0), TRY_CONVERT(DATETIMEOFFSET(0), j.DataOra)),
						DataOraLocale = CONVERT(DATETIME2(0), TRY_CONVERT(DATETIMEOFFSET(0), j.DataOra) AT TIME ZONE 'W. Europe Standard Time')
				) d
			WHERE m.IdImportazione = @Id;

			-- Stati degli originali letti con il dettaglio: stato corrente e variazioni
			SELECT
				m.Anno, m.Progressivo,
				DiRettificaAnno = TRY_CAST(JSON_VALUE(s.Json, '$.riferimenti.numero_registrazione_di_rettifica.anno') AS SMALLINT),
				DiRettificaProgressivo = TRY_CAST(JSON_VALUE(s.Json, '$.riferimenti.numero_registrazione_di_rettifica.progressivo') AS INT),
				IsAnnullato = IIF(JSON_VALUE(s.Json, '$.annullato') = 'true', 1, 0),
				s.Json
			INTO #stati
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY (
					SELECT m.JsonDettaglio AS Json
					UNION ALL
					SELECT v.value
					FROM OPENJSON(m.JsonDettaglio, '$.variazioni') v
					WHERE v.type = 5
				) s
			WHERE
				m.IdImportazione = @Id
				AND m.JsonDettaglio IS NOT NULL;

			-- ── 2. Valori da importare ────────────────────────────────────────────────────────────
			-- Movimento: trasmesso in origine (stato senza rettifica)
			UPDATE m
			SET JsonValori =
				CASE
					WHEN m.IsRettificato = 0 AND m.IsAnnullato = 0 THEN m.Json
					ELSE ISNULL(o.Json, IIF(m.IsRettificato = 0 AND m.JsonDettaglio IS NULL, m.Json, NULL))
				END
			FROM
				dbo.tblRentriImportazioniMovimenti m
				OUTER APPLY (
					SELECT TOP 1 s.Json
					FROM #stati s
					WHERE s.Anno = m.Anno AND s.Progressivo = m.Progressivo AND s.DiRettificaProgressivo IS NULL
				) o
			WHERE
				m.IdImportazione = @Id
				AND m.Tipo = 'M';

			-- Rettifica o annullamento: stato dell'originale prodotto da questa registrazione
			UPDATE m
			SET
				JsonValori = o.Json,
				Tipo = IIF(o.IsAnnullato = 1, 'A', 'R')
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY (
					SELECT TOP 1 s.Json, s.IsAnnullato
					FROM #stati s
					WHERE
						s.Anno = m.RettificaAnno AND s.Progressivo = m.RettificaProgressivo
						AND s.DiRettificaAnno = m.Anno AND s.DiRettificaProgressivo = m.Progressivo
				) o
			WHERE
				m.IdImportazione = @Id
				AND m.Tipo = 'R';

			-- ── 3. Causale e dati del rifiuto o del materiale dai valori da importare ─────────────
			UPDATE m
			SET
				-- RENTRI valorizza stoccaggio_istantaneo con la data fittizia 0001-01-01 anche quando non c'è
				Causale = IIF(j.Causale IS NULL AND TRY_CONVERT(DATETIMEOFFSET(0), j.StoccaggioIstantaneo) > '19000101', 'SI', j.Causale),
				Eer = COALESCE(j.Eer, j.Materiale),
				StatoFisico = j.StatoFisico,
				Quantita = TRY_CONVERT(DECIMAL(18, 4), COALESCE(j.Quantita, j.MaterialeQuantita)),
				UnitaMisura = COALESCE(j.UnitaMisura, j.MaterialeUnitaMisura)
			FROM
				dbo.tblRentriImportazioniMovimenti m
				OUTER APPLY OPENJSON(m.JsonValori)
				WITH (
					Causale VARCHAR(5) '$.riferimenti.causale_operazione',
					StoccaggioIstantaneo VARCHAR(40) '$.riferimenti.stoccaggio_istantaneo',
					Eer VARCHAR(10) '$.rifiuto.codice_eer',
					StatoFisico VARCHAR(5) '$.rifiuto.stato_fisico',
					Quantita VARCHAR(40) '$.rifiuto.quantita.valore',
					UnitaMisura VARCHAR(5) '$.rifiuto.quantita.unita_misura',
					Materiale VARCHAR(10) '$.materiali.materiale',
					MaterialeQuantita VARCHAR(40) '$.materiali.quantita.valore',
					MaterialeUnitaMisura VARCHAR(5) '$.materiali.quantita.unita_misura'
				) j
			WHERE m.IdImportazione = @Id;

			-- Codici di Ecomatico (tabelle di decodifica, colonna Codice; l'EER ha come Id il codice stesso)
			UPDATE m
			SET
				IdEer = IIF(x.IsMateriale = 0, (SELECT TOP 1 e.Id FROM dbo.tblRifiutiEer e WHERE e.Id = m.Eer), NULL),
				IdMateriale = IIF(x.IsMateriale = 1, (SELECT TOP 1 t.Id FROM dbo.tblRifiutiMateriali t WHERE t.Codice = m.Eer), NULL),
				IdStatoFisico = (SELECT TOP 1 s.Id FROM dbo.tblRifiutiStatiFisici s WHERE s.Codice = m.StatoFisico),
				IdUnitaMisura = (SELECT TOP 1 u.Id FROM dbo.tblUnitaMisura u WHERE u.Codice = m.UnitaMisura)
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY (SELECT IsMateriale = IIF(JSON_QUERY(m.JsonValori, '$.materiali') IS NOT NULL, 1, 0)) x
			WHERE m.IdImportazione = @Id;

			-- ── 4. Causali RENTRI -> operazioni Ecomatico ─────────────────────────────────────────
			-- Proposta: l'operazione con lo stesso codice RENTRI, esclusa quella del formulario unico degli
			-- spurghisti (si vidima su Vi.Vi.FIR, non arriva dal registro). La scelta dell'utente resta.
			INSERT dbo.tblRentriImportazioniCausali (IdImportazione, Causale, IdOperazione)
			SELECT
				@Id,
				c.Causale,
				(
					SELECT TOP 1 o.Id
					FROM dbo.tblRifiutiOperazioni o
					WHERE
						o.Codice = c.Causale
						AND ISNULL(o.IsRentri, 0) = 1
						AND ISNULL(o.IsFormularioUnico, 0) = 0
					ORDER BY o.Pos
				)
			FROM (
				SELECT DISTINCT m.Causale
				FROM dbo.tblRentriImportazioniMovimenti m
				WHERE m.IdImportazione = @Id AND m.Causale IS NOT NULL
			) c
			WHERE NOT EXISTS (
				SELECT 1
				FROM dbo.tblRentriImportazioniCausali x
				WHERE x.IdImportazione = @Id AND x.Causale = c.Causale);

			UPDATE m
			SET IdOperazione = c.IdOperazione
			FROM
				dbo.tblRentriImportazioniMovimenti m
				LEFT JOIN dbo.tblRentriImportazioniCausali c ON c.IdImportazione = m.IdImportazione AND c.Causale = m.Causale
			WHERE m.IdImportazione = @Id;

			-- ── 5. Registrazioni del registro già in Ecomatico ────────────────────────────────────
			-- Valori di lettura: numero, anno (anno della data) e identificativo RENTRI delle registrazioni attive
			SELECT
				r.Id, r.Numero, YEAR(r.Data) AS Anno, r.Data, r.RentriIdentificativo
			INTO #registro
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti v ON r.IdMovimento = v.Id
			WHERE
				v.IdRegistro = @idRegistro
				AND r.Lock < 2;

			UPDATE m
			SET
				IdRegistrazione = x.Id,
				Azione = NULL
			FROM
				dbo.tblRentriImportazioniMovimenti m
				OUTER APPLY (
					SELECT TOP 1 g.Id
					FROM #registro g
					WHERE g.RentriIdentificativo = m.Identificativo
				) x
			WHERE m.IdImportazione = @Id;

			-- ── 6. Anomalie ───────────────────────────────────────────────────────────────────────
			DELETE dbo.tblRentriImportazioniAnomalie
			WHERE IdImportazione = @Id;

			-- Già presente in Ecomatico con lo stesso identificativo RENTRI: non si importa di nuovo
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo,
				IIF(g.Numero = m.Progressivo AND g.Anno = m.Anno, 'I', 'W'),
				'GIA_PRESENTE',
				IIF(g.Numero = m.Progressivo AND g.Anno = m.Anno,
					'Già presente in Ecomatico: non viene importata di nuovo',
					CONCAT('Già presente in Ecomatico con il numero ', g.Numero, '/', g.Anno, ' invece di ', m.Progressivo, '/', m.Anno, ': non viene importata di nuovo'))
			FROM
				dbo.tblRentriImportazioniMovimenti m
				INNER JOIN #registro g ON m.IdRegistrazione = g.Id
			WHERE m.IdImportazione = @Id;

			-- Stesso identificativo RENTRI su un altro registro
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT DISTINCT
				@Id, m.Anno, m.Progressivo, 'E', 'ALTRO_REGISTRO',
				'La registrazione è già presente in Ecomatico in un altro registro'
			FROM
				dbo.tblRentriImportazioniMovimenti m
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON r.RentriIdentificativo = m.Identificativo AND r.Lock < 2
				INNER JOIN dbo.tblRifiutiMovimenti v ON r.IdMovimento = v.Id
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND v.IdRegistro <> @idRegistro;

			-- Numero già usato nel registro da un'altra registrazione
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'NUMERO_OCCUPATO',
				CONCAT('Il numero ', m.Progressivo, '/', m.Anno, ' è già usato in Ecomatico dalla registrazione del ', FORMAT(g.Data, 'dd/MM/yyyy'),
					IIF(g.RentriIdentificativo IS NULL, ', non inviata al RENTRI', ', inviata al RENTRI con un altro identificativo'))
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY (
					SELECT TOP 1 x.Data, x.RentriIdentificativo
					FROM #registro x
					WHERE
						x.Anno = m.Anno
						AND x.Numero = m.Progressivo
						AND (m.IdRegistrazione IS NULL OR x.Id <> m.IdRegistrazione)
					ORDER BY x.Data
				) g
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL;

			-- Data di registrazione non leggibile
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT @Id, m.Anno, m.Progressivo, 'E', 'DATA', 'La data di registrazione restituita da RENTRI non è valida'
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND (m.Data IS NULL OR YEAR(m.Data) <> m.Anno);

			-- Numerazione non coerente con le date delle registrazioni già nel registro (stessa regola del salvataggio)
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'DATA_INCOERENTE',
				CONCAT('La data ', FORMAT(m.Data, 'dd/MM/yyyy'), ' non è coerente con la registrazione n. ', g.Numero, '/', g.Anno,
					' del ', FORMAT(g.Data, 'dd/MM/yyyy'), ' già presente in Ecomatico')
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY (
					SELECT TOP 1 x.Numero, x.Anno, x.Data
					FROM #registro x
					WHERE
						x.Anno = m.Anno
						AND ((x.Numero < m.Progressivo AND x.Data > m.Data) OR (x.Numero > m.Progressivo AND x.Data < m.Data))
						AND NOT EXISTS (
							SELECT 1
							FROM dbo.tblRentriImportazioniMovimenti y
							WHERE y.IdImportazione = @Id AND y.IdRegistrazione = x.Id)
					ORDER BY ABS(x.Numero - m.Progressivo)
				) g
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Data IS NOT NULL;

			-- Causale non riconosciuta
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'CAUSALE',
				IIF(m.Causale IS NULL, 'Causale RENTRI mancante', CONCAT('Nessuna operazione di Ecomatico corrisponde alla causale RENTRI "', m.Causale, '"'))
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Tipo = 'M'
				AND m.IdOperazione IS NULL;

			-- Valori non disponibili: trasmessi in origine (originale rettificato) o della rettifica (stato
			-- dell'originale che la rettifica ha prodotto); originale assente = ORIGINALE_MANCANTE
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'VALORI_ORIGINALI',
				IIF(m.Tipo = 'M',
					'RENTRI non ha restituito i valori trasmessi in origine di questa registrazione rettificata',
					CONCAT('RENTRI non ha restituito i valori di questa rettifica nella storia della registrazione n. ', m.RettificaProgressivo, '/', m.RettificaAnno))
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.JsonValori IS NULL
				AND (
					m.Tipo = 'M'
					OR EXISTS (
						SELECT 1
						FROM dbo.tblRentriImportazioniMovimenti o
						WHERE o.IdImportazione = @Id AND o.Anno = m.RettificaAnno AND o.Progressivo = m.RettificaProgressivo));

			-- Dati del rifiuto o del materiale mancanti
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'DATI_RIFIUTO',
				'Codice EER (o materiale), quantità o unità di misura mancanti'
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.JsonValori IS NOT NULL
				AND m.Tipo IN ('M', 'R')
				AND (m.Eer IS NULL OR m.Quantita IS NULL OR m.UnitaMisura IS NULL);

			-- Codici RENTRI senza corrispondenza nelle tabelle di Ecomatico
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'CODICI',
				CONCAT('Codici RENTRI non presenti in Ecomatico:',
					IIF(m.IdEer IS NULL AND m.IdMateriale IS NULL, CONCAT(' ', IIF(JSON_QUERY(m.JsonValori, '$.materiali') IS NULL, 'EER ', 'materiale '), m.Eer), ''),
					IIF(m.StatoFisico IS NOT NULL AND m.IdStatoFisico IS NULL, CONCAT(' stato fisico ', m.StatoFisico), ''),
					IIF(m.IdUnitaMisura IS NULL, CONCAT(' unità di misura ', m.UnitaMisura), ''))
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Tipo IN ('M', 'R')
				AND m.Eer IS NOT NULL AND m.UnitaMisura IS NOT NULL
				AND (
					(m.IdEer IS NULL AND m.IdMateriale IS NULL)
					OR (m.StatoFisico IS NOT NULL AND m.IdStatoFisico IS NULL)
					OR m.IdUnitaMisura IS NULL);

			-- Testi più lunghi delle colonne di Ecomatico: non si troncano
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'LUNGHEZZA',
				CONCAT('Testo più lungo di quanto Ecomatico può memorizzare: ', STUFF(CONCAT(
					IIF(LEN(j.NumeroFir) > 20, ', numero del formulario', ''),
					IIF(LEN(j.CausaleAltro) > 100, ', causale di respingimento', ''),
					IIF(LEN(j.DescrizioneMateriale) > 200, ', descrizione del materiale', ''),
					IIF(LEN(j.DescrizioneEer) > 200, ', descrizione EER', ''),
					IIF(LEN(j.Annotazioni) > 500, ', annotazioni', ''),
					IIF(LEN(j.VeicoloNumero) > 50, ', numero del veicolo fuori uso', '')), 1, 2, ''))
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY OPENJSON(m.JsonValori)
				WITH (
					NumeroFir NVARCHAR(200) '$.integrazione_fir.numero_fir',
					CausaleAltro NVARCHAR(1000) '$.esito.respingimento.causale_altro',
					DescrizioneMateriale NVARCHAR(1000) '$.materiali.descrizione_materiale',
					DescrizioneEer NVARCHAR(1000) '$.rifiuto.descrizione_eer',
					Annotazioni NVARCHAR(2000) '$.annotazioni',
					VeicoloNumero NVARCHAR(200) '$.rifiuto.veicolo_fuori_uso_reg_pubblica_sicurezza.numero'
				) j
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.JsonValori IS NOT NULL
				AND (LEN(j.NumeroFir) > 20 OR LEN(j.CausaleAltro) > 100 OR LEN(j.DescrizioneMateriale) > 200 OR LEN(j.DescrizioneEer) > 200
					OR LEN(j.Annotazioni) > 500 OR LEN(j.VeicoloNumero) > 50);

			-- Più di 2 decimali: Ecomatico ne gestisce 2, la quantità non si arrotonda
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'DECIMALI',
				CONCAT('La quantità ', FORMAT(m.Quantita, '0.####', 'it-IT'), ' ha più di 2 decimali: Ecomatico ne gestisce 2 e non la arrotonda')
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Quantita <> ROUND(m.Quantita, 2);

			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'DECIMALI_ESITO',
				'Il peso verificato a destino o la quantità respinta hanno più di 2 decimali: Ecomatico ne gestisce 2 e non li arrotonda'
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY OPENJSON(m.JsonValori)
				WITH (
					PesoVerificato VARCHAR(40) '$.esito.peso_verificato_destino',
					QuantitaRespinta VARCHAR(40) '$.esito.respingimento.quantita.valore'
				) j
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.JsonValori IS NOT NULL
				AND (
					TRY_CONVERT(DECIMAL(18, 4), j.PesoVerificato) <> ROUND(TRY_CONVERT(DECIMAL(18, 4), j.PesoVerificato), 2)
					OR TRY_CONVERT(DECIMAL(18, 4), j.QuantitaRespinta) <> ROUND(TRY_CONVERT(DECIMAL(18, 4), j.QuantitaRespinta), 2));

			-- Rettifica o annullamento senza la registrazione originale (né letta da RENTRI né in Ecomatico)
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'ORIGINALE_MANCANTE',
				CONCAT(IIF(m.Tipo = 'A', 'Annullamento', 'Rettifica'), ' della registrazione n. ', m.RettificaProgressivo, '/', m.RettificaAnno,
					', che non è stata trovata né su RENTRI né in Ecomatico')
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Tipo IN ('R', 'A')
				AND NOT EXISTS (
					SELECT 1
					FROM dbo.tblRentriImportazioniMovimenti o
					WHERE o.IdImportazione = @Id AND o.Anno = m.RettificaAnno AND o.Progressivo = m.RettificaProgressivo)
				AND NOT EXISTS (
					SELECT 1
					FROM #registro g
					WHERE g.Anno = m.RettificaAnno AND g.Numero = m.RettificaProgressivo AND g.RentriIdentificativo IS NOT NULL);

			-- ── 6b. Soggetti (produttore, trasportatore, destinatario, intermediari) ─────────────
			-- Dai valori da importare, solo per i ruoli che l'operazione di Ecomatico prevede (IsProduttore,
			-- IsTrasportatore, IsDestinatario, IsIntermediario). Un soggetto per ruolo, codice fiscale e numero
			-- (iscrizione all'Albo o autorizzazione), condiviso da tutte le registrazioni che lo usano. Anche le rettifiche e gli
			-- annullamenti: in Ecomatico riportano i valori in vigore, soggetti compresi (R2.6).
			-- Trasportatore, destinatario e intermediari che la registrazione su RENTRI non riporta (altri gestionali
			-- trasmettono solo il numero del formulario) si prendono dal formulario digitale con quel numero, letto da
			-- RENTRI (FormularioStato D, JSON originale del formulario letto dall'hub): servono anche per il MUD.
			-- Formulari digitali letti da RENTRI, una riga per numero (letti una sola volta: con migliaia di registrazioni
			-- leggere il JSON a ogni confronto costa decine di secondi)
			SELECT Numero = CAST(JSON_VALUE(f.JsonFormulario, '$.dati_partenza.numero_fir') AS VARCHAR(50)), Json = MIN(f.JsonFormulario)
			INTO #fir
			FROM dbo.tblRentriImportazioniMovimenti f
			WHERE f.IdImportazione = @Id AND f.FormularioStato = 'D' AND JSON_VALUE(f.JsonFormulario, '$.dati_partenza.numero_fir') IS NOT NULL
			GROUP BY JSON_VALUE(f.JsonFormulario, '$.dati_partenza.numero_fir');
			CREATE UNIQUE CLUSTERED INDEX IX_fir ON #fir (Numero);

			SELECT
				m.Anno, m.Progressivo,
				s.Ruolo, s.Pos,
				CodiceFiscale = UPPER(LTRIM(RTRIM(s.CodiceFiscale))),
				Numero = ISNULL(UPPER(REPLACE(LTRIM(RTRIM(s.Numero)), ' ', '')), ''),
				Denominazione = LEFT(s.Denominazione, 200),
				s.NazioneId,
				s.IndirizzoJson
			INTO #ms
			FROM
				dbo.tblRentriImportazioniMovimenti m
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN #fir fir ON fir.Numero = CAST(JSON_VALUE(m.JsonValori, '$.integrazione_fir.numero_fir') AS VARCHAR(50))
				CROSS APPLY (
					SELECT 'P', 1, JSON_VALUE(m.JsonValori, '$.produttore.codice_fiscale'), NULL,
						JSON_VALUE(m.JsonValori, '$.produttore.denominazione'), JSON_VALUE(m.JsonValori, '$.produttore.nazione_id'),
						JSON_QUERY(m.JsonValori, '$.produttore.indirizzo')
					WHERE ISNULL(o.IsProduttore, 0) = 1
					UNION ALL
					SELECT 'T', 1, JSON_VALUE(m.JsonValori, '$.trasportatore.codice_fiscale'), JSON_VALUE(m.JsonValori, '$.trasportatore.num_iscrizione_albo'),
						JSON_VALUE(m.JsonValori, '$.trasportatore.denominazione'), JSON_VALUE(m.JsonValori, '$.trasportatore.nazione_id'), NULL
					WHERE ISNULL(o.IsTrasportatore, 0) = 1 AND JSON_QUERY(m.JsonValori, '$.trasportatore') IS NOT NULL
					UNION ALL
					SELECT 'T', 1, JSON_VALUE(fir.Json, '$.dati_partenza.trasportatori[0].codice_fiscale'), JSON_VALUE(fir.Json, '$.dati_partenza.trasportatori[0].numero_iscrizione_albo'),
						JSON_VALUE(fir.Json, '$.dati_partenza.trasportatori[0].denominazione'), JSON_VALUE(fir.Json, '$.dati_partenza.trasportatori[0].nazione_id'), NULL
					WHERE ISNULL(o.IsTrasportatore, 0) = 1 AND JSON_QUERY(m.JsonValori, '$.trasportatore') IS NULL AND fir.Json IS NOT NULL
					UNION ALL
					SELECT 'D', 1, JSON_VALUE(m.JsonValori, '$.destinatario.codice_fiscale'), JSON_VALUE(m.JsonValori, '$.destinatario.num_autorizzazione'),
						JSON_VALUE(m.JsonValori, '$.destinatario.denominazione'), JSON_VALUE(m.JsonValori, '$.destinatario.nazione_id'), NULL
					WHERE ISNULL(o.IsDestinatario, 0) = 1 AND JSON_QUERY(m.JsonValori, '$.destinatario') IS NOT NULL
					UNION ALL
					SELECT 'D', 1, JSON_VALUE(fir.Json, '$.dati_partenza.destinatario.codice_fiscale'), JSON_VALUE(fir.Json, '$.dati_partenza.destinatario.autorizzazione.numero'),
						JSON_VALUE(fir.Json, '$.dati_partenza.destinatario.denominazione'), JSON_VALUE(fir.Json, '$.dati_partenza.destinatario.nazione_id'),
						JSON_QUERY(fir.Json, '$.dati_partenza.destinatario.indirizzo')
					WHERE ISNULL(o.IsDestinatario, 0) = 1 AND JSON_QUERY(m.JsonValori, '$.destinatario') IS NULL AND fir.Json IS NOT NULL
					UNION ALL
					SELECT 'I', CAST(i.[key] AS INT) + 1, JSON_VALUE(i.value, '$.codice_fiscale'), JSON_VALUE(i.value, '$.num_iscrizione_albo'),
						JSON_VALUE(i.value, '$.denominazione'), JSON_VALUE(i.value, '$.nazione_id'), NULL
					FROM OPENJSON(m.JsonValori, '$.intermediari') i
					WHERE ISNULL(o.IsIntermediario, 0) = 1
					UNION ALL
					SELECT 'I', CAST(k.[key] AS INT) + 1, JSON_VALUE(k.value, '$.codice_fiscale'), JSON_VALUE(k.value, '$.numero_iscrizione_albo'),
						JSON_VALUE(k.value, '$.denominazione'), JSON_VALUE(k.value, '$.nazione_id'), NULL
					FROM OPENJSON(fir.Json, '$.dati_partenza.intermediari') k
					WHERE
						ISNULL(o.IsIntermediario, 0) = 1
						AND fir.Json IS NOT NULL
						AND ISNULL(JSON_QUERY(m.JsonValori, '$.intermediari'), '[]') = '[]'
						AND JSON_QUERY(m.JsonValori, '$.intermediario') IS NULL
				) s (Ruolo, Pos, CodiceFiscale, Numero, Denominazione, NazioneId, IndirizzoJson)
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Tipo IN ('M', 'R', 'A')
				AND m.JsonValori IS NOT NULL
				AND NULLIF(LTRIM(RTRIM(s.CodiceFiscale)), '') IS NOT NULL;

			-- Soggetti non più usati: via; nuovi: da abbinare
			DELETE x
			FROM dbo.tblRentriImportazioniSoggetti x
			WHERE
				x.IdImportazione = @Id
				AND NOT EXISTS (
					SELECT 1
					FROM #ms s
					WHERE s.Ruolo = x.Ruolo AND s.CodiceFiscale = x.CodiceFiscale AND s.Numero = x.Numero);

			INSERT dbo.tblRentriImportazioniSoggetti (IdImportazione, Ruolo, CodiceFiscale, Numero, Denominazione, NazioneId, IndirizzoJson, Stato, IsModificato)
			SELECT @Id, s.Ruolo, s.CodiceFiscale, s.Numero, MIN(s.Denominazione), MIN(s.NazioneId), MIN(s.IndirizzoJson), 'M', 0
			FROM #ms s
			WHERE NOT EXISTS (
				SELECT 1
				FROM dbo.tblRentriImportazioniSoggetti x
				WHERE x.IdImportazione = @Id AND x.Ruolo = s.Ruolo AND x.CodiceFiscale = s.CodiceFiscale AND x.Numero = s.Numero)
			GROUP BY s.Ruolo, s.CodiceFiscale, s.Numero;

			-- Sedi visibili all'azienda interna del registro (stesso calcolo di uspRifiutiAutorizzazioni_get_MatchImportazione)
			DECLARE @idAziendaInterna CHAR(16), @idUtente CHAR(16);
			SELECT @idAziendaInterna = s.IdAziendaInterna
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			WHERE g.Id = @idRegistro;
			SELECT @idUtente = IdUtente FROM dbo.tblSessioni WHERE Id = @IdSessione;

			SELECT s.Id, CodiceFiscale = UPPER(s.CodiceFiscale), PartitaIva = UPPER(s.PartitaIva)
			INTO #sedi
			FROM
				dbo.ufnSedi_get_SediByUtente_List(@idUtente) u
				INNER JOIN dbo.tblSedi s ON u.Id = s.Id
			WHERE
				u.Disabilitata = 0
				AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
				AND s.Disabilitata = 0
				AND s.Lock < 2;

			-- Abbinamento automatico (non tocca le scelte dell'utente, IsModificato):
			--   A  autorizzazione dello stesso ruolo con lo stesso numero, su una sede con quel codice fiscale (o
			--      partita IVA); senza numero (produttore), l'unica autorizzazione del ruolo su quelle sedi;
			--   N  nessuna autorizzazione ma una sola sede con quel codice fiscale: all'importazione le si aggiunge
			--      l'autorizzazione con il numero di RENTRI (per il produttore la "Nessuna");
			--   M  da completare: nessuna sede, oppure più sedi o autorizzazioni possibili (sceglie l'utente).
			UPDATE x
			SET
				Stato = CASE WHEN a.Conteggio = 1 THEN 'A' WHEN c.Conteggio = 1 THEN 'N' ELSE 'M' END,
				IdAutorizzazione = IIF(a.Conteggio = 1, a.Id, NULL),
				IdSede = IIF(a.Conteggio = 1, NULL, IIF(c.Conteggio = 1, c.Id, NULL)),
				-- Dati proposti per creare il soggetto (completati dall'utente nell'anteprima)
				Nome = LEFT(x.Denominazione, 50),
				IdNazione = ISNULL((SELECT TOP 1 n.Id FROM dbo.tblNazioni n WHERE n.Sigla = ISNULL(NULLIF(x.NazioneId, ''), 'IT')), '380'),
				PartitaIva = IIF(LEN(x.CodiceFiscale) = 11 AND x.CodiceFiscale NOT LIKE '%[^0-9]%', x.CodiceFiscale, NULL),
				IdComune = (SELECT TOP 1 k.Id FROM dbo.tblComuni k WHERE k.Id = JSON_VALUE(x.IndirizzoJson, '$.citta.comune_id')),
				Localita = LEFT(JSON_VALUE(x.IndirizzoJson, '$.citta.nome_citta'), 50),
				CAP = LEFT(NULLIF(JSON_VALUE(x.IndirizzoJson, '$.cap'), ''), 10),
				Indirizzo = LEFT(NULLIF(JSON_VALUE(x.IndirizzoJson, '$.indirizzo'), ''), 50),
				NumeroCivico = LEFT(NULLIF(JSON_VALUE(x.IndirizzoJson, '$.civico'), ''), 10)
			FROM
				dbo.tblRentriImportazioniSoggetti x
				OUTER APPLY (
					SELECT Conteggio = COUNT(DISTINCT z.Id), Id = MIN(z.Id)
					FROM
						dbo.tblRifiutiAutorizzazioni z
						INNER JOIN #sedi s ON z.IdSede = s.Id
					WHERE
						z.IdRuolo = x.Ruolo
						AND z.Disabilitata = 0
						AND z.Lock < 2
						AND (s.CodiceFiscale = x.CodiceFiscale OR s.PartitaIva = x.CodiceFiscale)
						AND (
							(x.Numero <> '' AND UPPER(REPLACE(z.Numero, ' ', '')) = x.Numero)
							OR (x.Numero = '' AND (x.Ruolo <> 'P' OR ISNULL(z.Nessuna, 0) = 1 OR z.Numero IS NULL)))
				) a
				OUTER APPLY (
					SELECT Conteggio = COUNT(*), Id = MIN(s.Id)
					FROM #sedi s
					WHERE s.CodiceFiscale = x.CodiceFiscale OR s.PartitaIva = x.CodiceFiscale
				) c
			WHERE
				x.IdImportazione = @Id
				AND x.IsModificato = 0;

			-- Scelte dell'utente non più valide (autorizzazione cancellata o non più visibile): di nuovo da completare
			UPDATE x
			SET Stato = 'M', IsModificato = 0, IdAutorizzazione = NULL, IdSede = NULL
			FROM dbo.tblRentriImportazioniSoggetti x
			WHERE
				x.IdImportazione = @Id
				AND x.Stato = 'U'
				AND NOT EXISTS (
					SELECT 1
					FROM
						dbo.tblRifiutiAutorizzazioni z
						INNER JOIN #sedi s ON z.IdSede = s.Id
					WHERE z.Id = x.IdAutorizzazione AND z.IdRuolo = x.Ruolo AND z.Disabilitata = 0 AND z.Lock < 2)
				AND NOT EXISTS (SELECT 1 FROM #sedi s WHERE x.IdAutorizzazione IS NULL AND s.Id = x.IdSede);

			DELETE dbo.tblRentriImportazioniMovimentiSoggetti
			WHERE IdImportazione = @Id;

			INSERT dbo.tblRentriImportazioniMovimentiSoggetti (IdImportazione, Anno, Progressivo, Ruolo, Pos, IdSoggetto)
			SELECT DISTINCT @Id, s.Anno, s.Progressivo, s.Ruolo, s.Pos, x.Id
			FROM
				#ms s
				INNER JOIN dbo.tblRentriImportazioniSoggetti x
					ON x.IdImportazione = @Id AND x.Ruolo = s.Ruolo AND x.CodiceFiscale = s.CodiceFiscale AND x.Numero = s.Numero;

			-- Soggetti presi dal formulario digitale, oppure assenti perché il formulario non è digitale
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo,
				IIF(fir.Numero IS NOT NULL, 'I', 'W'),
				'SOGGETTI_FORMULARIO',
				IIF(fir.Numero IS NOT NULL,
					CONCAT('Trasportatore e destinatario non sono nella registrazione su RENTRI: letti dal formulario digitale n. ', x.NumeroFir),
					CONCAT('Trasportatore e destinatario non sono nella registrazione su RENTRI e il formulario n. ', x.NumeroFir,
						' non è digitale: verrà importata senza, da completare a mano se servono (per esempio per il MUD)'))
			FROM
				dbo.tblRentriImportazioniMovimenti m
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				CROSS APPLY (SELECT NumeroFir = CAST(JSON_VALUE(m.JsonValori, '$.integrazione_fir.numero_fir') AS VARCHAR(50))) x
				LEFT JOIN #fir fir ON fir.Numero = x.NumeroFir
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Tipo IN ('M', 'R', 'A')
				AND x.NumeroFir IS NOT NULL
				AND (
					(ISNULL(o.IsTrasportatore, 0) = 1 AND JSON_QUERY(m.JsonValori, '$.trasportatore') IS NULL)
					OR (ISNULL(o.IsDestinatario, 0) = 1 AND JSON_QUERY(m.JsonValori, '$.destinatario') IS NULL));

			-- Soggetto da completare: bloccante per ogni registrazione che lo usa (mai un soggetto vuoto)
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, ms.Anno, ms.Progressivo, 'E', 'SOGGETTO',
				CONCAT(
					CASE x.Ruolo WHEN 'P' THEN 'Produttore' WHEN 'T' THEN 'Trasportatore' WHEN 'D' THEN 'Destinatario' ELSE 'Intermediario' END,
					' ', ISNULL(x.Denominazione, ''), ' (', x.CodiceFiscale, ') da abbinare o completare nella sezione Soggetti')
			FROM
				dbo.tblRentriImportazioniMovimentiSoggetti ms
				INNER JOIN dbo.tblRentriImportazioniSoggetti x ON ms.IdSoggetto = x.Id
			WHERE
				ms.IdImportazione = @Id
				AND x.Stato = 'M';

			-- ── 7. Azione e relazioni carico/scarico ─────────────────────────────────────────────
			UPDATE m
			SET Azione =
				CASE
					WHEN m.IdRegistrazione IS NOT NULL THEN 'P'
					WHEN EXISTS (
						SELECT 1
						FROM dbo.tblRentriImportazioniAnomalie a
						WHERE a.IdImportazione = @Id AND a.Anno = m.Anno AND a.Progressivo = m.Progressivo AND a.Livello = 'E') THEN 'X'
					ELSE 'I'
				END
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE m.IdImportazione = @Id;

			-- Riferimenti di RENTRI: ogni registrazione riporta le associate su entrambi i lati, con associazione_diretta
			-- = true sul lato di chi le ha scelte; nei dati più vecchi però il flag è true su tutti e due i lati
			-- (verificato sulla sandbox). Il verso si decide quindi così, per ogni coppia:
			--   1. le coppie ammesse da Ecomatico (tblRifiutiOperazioniRelazioni): se è ammesso un solo verso, vale quello;
			--   2. se sono ammessi tutti e due i versi (scarico R e carico M: consumo o derivazione), il padre è la
			--      registrazione successiva (data, poi anno e numero), perché il padre non precede mai il figlio;
			--   3. se non è ammesso nessun verso, o l'associata non è nell'area temporanea, vale associazione_diretta.
			-- Il padre (IdParent in Ecomatico) è lo scarico S/R che preleva dai carichi (consumo) o il carico K/M che
			-- deriva dallo scarico R (derivazione). Le rettifiche non hanno relazioni proprie (R2.7).
			SELECT
				AAnno = m.Anno,
				AProgressivo = m.Progressivo,
				BAnno = r.Anno,
				BProgressivo = r.Progressivo,
				BIdentificativo = r.Identificativo,
				Diretta = IIF(r.Diretta = 'true', 1, 0)
			INTO #rif
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY OPENJSON(ISNULL(m.JsonValori, m.Json), '$.riferimenti.riferimento_operazione') x
				CROSS APPLY (
					SELECT
						Anno = TRY_CAST(JSON_VALUE(x.value, '$.anno') AS SMALLINT),
						Progressivo = TRY_CAST(JSON_VALUE(x.value, '$.progressivo') AS INT),
						Identificativo = JSON_VALUE(x.value, '$.identificativo'),
						Diretta = JSON_VALUE(x.value, '$.associazione_diretta')
				) r
			WHERE
				m.IdImportazione = @Id
				AND m.Tipo = 'M'
				AND m.Azione IN ('I', 'X')
				AND r.Anno IS NOT NULL
				AND r.Progressivo IS NOT NULL;

			SELECT
				r.AAnno, r.AProgressivo, r.BAnno, r.BProgressivo, r.BIdentificativo,
				BInArea = IIF(b.Anno IS NULL, 0, 1),
				BAzione = b.Azione,
				PadreA =
					CASE
						WHEN b.Anno IS NULL THEN MAX(r.Diretta) OVER (PARTITION BY r.AAnno, r.AProgressivo, r.BAnno, r.BProgressivo)
						WHEN v.AB = 1 AND v.BA = 0 THEN 1
						WHEN v.BA = 1 AND v.AB = 0 THEN 0
						WHEN v.AB = 0 AND v.BA = 0 THEN MAX(r.Diretta) OVER (PARTITION BY r.AAnno, r.AProgressivo, r.BAnno, r.BProgressivo)
						WHEN a.Data > b.Data OR (a.Data = b.Data AND (a.Anno > b.Anno OR (a.Anno = b.Anno AND a.Progressivo > b.Progressivo))) THEN 1
						ELSE 0
					END
			INTO #verso
			FROM
				#rif r
				INNER JOIN dbo.tblRentriImportazioniMovimenti a
					ON a.IdImportazione = @Id AND a.Anno = r.AAnno AND a.Progressivo = r.AProgressivo
				LEFT JOIN dbo.tblRentriImportazioniMovimenti b
					ON b.IdImportazione = @Id AND b.Anno = r.BAnno AND b.Progressivo = r.BProgressivo AND b.Tipo = 'M'
				CROSS APPLY (
					SELECT
						AB = IIF(EXISTS (SELECT 1 FROM dbo.tblRifiutiOperazioniRelazioni z WHERE z.Id = a.IdOperazione AND z.IdParent = b.IdOperazione), 1, 0),
						BA = IIF(EXISTS (SELECT 1 FROM dbo.tblRifiutiOperazioniRelazioni z WHERE z.Id = b.IdOperazione AND z.IdParent = a.IdOperazione), 1, 0)
				) v;

			SELECT
				PadreAnno, PadreProgressivo, FiglioAnno, FiglioProgressivo,
				FiglioIdentificativo = MIN(FiglioIdentificativo),
				Pos = ROW_NUMBER() OVER (PARTITION BY PadreAnno, PadreProgressivo ORDER BY FiglioAnno, FiglioProgressivo)
			INTO #riferimenti
			FROM (
				SELECT
					PadreAnno = AAnno, PadreProgressivo = AProgressivo,
					FiglioAnno = BAnno, FiglioProgressivo = BProgressivo, FiglioIdentificativo = BIdentificativo
				FROM #verso
				WHERE PadreA = 1
				UNION ALL
				SELECT
					BAnno, BProgressivo, AAnno, AProgressivo,
					(SELECT TOP 1 m.Identificativo FROM dbo.tblRentriImportazioniMovimenti m WHERE m.IdImportazione = @Id AND m.Anno = AAnno AND m.Progressivo = AProgressivo)
				FROM #verso
				WHERE PadreA = 0 AND BInArea = 1 AND BAzione IN ('I', 'X')
			) z
			GROUP BY PadreAnno, PadreProgressivo, FiglioAnno, FiglioProgressivo;

			-- Le relazioni corrette dall'utente (IsModificata) restano; le altre si ripropongono da zero
			DELETE l
			FROM dbo.tblRentriImportazioniRelazioni l
			WHERE
				l.IdImportazione = @Id
				AND (
					l.IsModificata = 0
					OR NOT EXISTS (
						SELECT 1
						FROM dbo.tblRentriImportazioniMovimenti m
						WHERE m.IdImportazione = @Id AND m.Anno = l.PadreAnno AND m.Progressivo = l.PadreProgressivo AND m.Azione IN ('I', 'X')));

			INSERT dbo.tblRentriImportazioniRelazioni (
				IdImportazione, PadreAnno, PadreProgressivo, FiglioAnno, FiglioProgressivo, FiglioIdentificativo, Pos, Operazione, IsModificata)
			SELECT
				@Id, r.PadreAnno, r.PadreProgressivo, r.FiglioAnno, r.FiglioProgressivo, MIN(r.FiglioIdentificativo), MIN(r.Pos), MIN(o.Operazione), 0
			FROM
				#riferimenti r
				INNER JOIN dbo.tblRentriImportazioniMovimenti p
					ON p.IdImportazione = @Id AND p.Anno = r.PadreAnno AND p.Progressivo = r.PadreProgressivo
				LEFT JOIN dbo.tblRifiutiOperazioni o ON p.IdOperazione = o.Id
			WHERE NOT EXISTS (
				SELECT 1
				FROM dbo.tblRentriImportazioniRelazioni l
				WHERE l.IdImportazione = @Id AND l.PadreAnno = r.PadreAnno AND l.PadreProgressivo = r.PadreProgressivo)
			GROUP BY r.PadreAnno, r.PadreProgressivo, r.FiglioAnno, r.FiglioProgressivo;

			-- Figlio già in Ecomatico: per identificativo RENTRI, altrimenti per numero e anno tra le inviate
			UPDATE l
			SET IdRegistrazioneFiglio = COALESCE(f.IdRegistrazione, g1.Id, g2.Id)
			FROM
				dbo.tblRentriImportazioniRelazioni l
				LEFT JOIN dbo.tblRentriImportazioniMovimenti f
					ON f.IdImportazione = @Id AND f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
				OUTER APPLY (SELECT TOP 1 g.Id FROM #registro g WHERE g.RentriIdentificativo = l.FiglioIdentificativo) g1
				OUTER APPLY (
					SELECT TOP 1 g.Id
					FROM #registro g
					WHERE g.Anno = l.FiglioAnno AND g.Numero = l.FiglioProgressivo AND g.RentriIdentificativo IS NOT NULL
				) g2
			WHERE l.IdImportazione = @Id;

			-- Registrazioni associate (figli) con la quantità disponibile di partenza: nell'area temporanea la
			-- quantità trasmessa in origine, in Ecomatico il residuo operativo (giacenza: R7 delle rettifiche)
			SELECT
				f.Anno, f.Progressivo, f.Data, f.IdOperazione, f.IdEer, f.IdStatoFisico, f.IdUnitaMisura,
				Disponibile = ISNULL(f.Quantita, 0),
				IsStaging = CAST(1 AS BIT),
				f.Azione
			INTO #figli
			FROM dbo.tblRentriImportazioniMovimenti f
			WHERE
				f.IdImportazione = @Id
				AND f.Azione IN ('I', 'X')
				AND EXISTS (
					SELECT 1
					FROM dbo.tblRentriImportazioniRelazioni l
					WHERE l.IdImportazione = @Id AND l.FiglioAnno = f.Anno AND l.FiglioProgressivo = f.Progressivo);

			CREATE UNIQUE CLUSTERED INDEX IX_figli ON #figli (Anno, Progressivo);

			INSERT #figli (Anno, Progressivo, Data, IdOperazione, IdEer, IdStatoFisico, IdUnitaMisura, Disponibile, IsStaging, Azione)
			SELECT
				l.FiglioAnno, l.FiglioProgressivo, r.Data, v.IdOperazione, e.IdEer, e.IdStatoFisico, e.IdUnitaMisura,
				ISNULL(e.Quantita, 0) - ISNULL((
					SELECT SUM(x.Quantita)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni x
						INNER JOIN dbo.tblRifiutiRegistrazioni rp ON x.IdParent = rp.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON rp.Id = vp.Id
					WHERE
						x.Id = r.Id
						AND x.Quantita > 0
						AND rp.Lock < 2
						AND vp.IsAnnullata = 0
				), 0),
				0,
				'P'
			FROM
				(
					SELECT FiglioAnno, FiglioProgressivo, IdRegistrazioneFiglio = MIN(IdRegistrazioneFiglio)
					FROM dbo.tblRentriImportazioniRelazioni
					WHERE IdImportazione = @Id AND IdRegistrazioneFiglio IS NOT NULL
					GROUP BY FiglioAnno, FiglioProgressivo
				) l
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.IdRegistrazioneFiglio = r.Id
				INNER JOIN dbo.tblRifiutiMovimenti v ON r.IdMovimento = v.Id
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive e ON r.Id = e.Id
			WHERE NOT EXISTS (
				SELECT 1
				FROM #figli f
				WHERE f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo);

			-- Ripartizione FIFO: padri in ordine di data e numero, figli di ciascun padre in ordine di data e numero.
			-- Un solo figlio: riceve tutta la quantità del padre (l'eventuale eccedenza è un'anomalia). Più figli:
			-- ognuno dà al massimo il proprio residuo, solo tra i figli che RENTRI riporta. Le relazioni corrette
			-- dall'utente si tengono come sono. Un padre annullato su RENTRI non consuma (annullamento operativo, R4.6).
			DECLARE
				@pAnno SMALLINT, @pProgressivo INT, @pQuantita DECIMAL(18, 4), @pAnnullato BIT, @pModificata INT, @pFigli INT,
				@fAnno SMALLINT, @fProgressivo INT, @fQuantita DECIMAL(18, 4), @disponibile DECIMAL(18, 4), @quota DECIMAL(18, 4);

			DECLARE cPadri CURSOR LOCAL FAST_FORWARD FOR
				SELECT p.Anno, p.Progressivo, ISNULL(p.Quantita, 0), ISNULL(p.IsAnnullato, 0), MAX(CAST(l.IsModificata AS INT)), COUNT(*)
				FROM
					dbo.tblRentriImportazioniRelazioni l
					INNER JOIN dbo.tblRentriImportazioniMovimenti p
						ON p.IdImportazione = l.IdImportazione AND p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
				WHERE l.IdImportazione = @Id
				GROUP BY p.Anno, p.Progressivo, p.Quantita, p.IsAnnullato, p.Data
				ORDER BY p.Data, p.Anno, p.Progressivo;

			OPEN cPadri;
			FETCH cPadri INTO @pAnno, @pProgressivo, @pQuantita, @pAnnullato, @pModificata, @pFigli;
			WHILE @@FETCH_STATUS = 0
			BEGIN
				DECLARE cFigli CURSOR LOCAL FAST_FORWARD FOR
					SELECT l.FiglioAnno, l.FiglioProgressivo, l.Quantita
					FROM
						dbo.tblRentriImportazioniRelazioni l
						LEFT JOIN #figli f ON f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
					WHERE l.IdImportazione = @Id AND l.PadreAnno = @pAnno AND l.PadreProgressivo = @pProgressivo
					ORDER BY IIF(f.Data IS NULL, 1, 0), f.Data, l.FiglioAnno, l.FiglioProgressivo;

				OPEN cFigli;
				FETCH cFigli INTO @fAnno, @fProgressivo, @fQuantita;
				WHILE @@FETCH_STATUS = 0
				BEGIN
					SET @disponibile = (SELECT Disponibile FROM #figli WHERE Anno = @fAnno AND Progressivo = @fProgressivo);

					IF @pModificata = 1
						SET @quota = ISNULL(@fQuantita, 0);
					ELSE IF @pFigli = 1
						SET @quota = @pQuantita;
					ELSE
						SET @quota = CASE
							WHEN ISNULL(@disponibile, 0) <= 0 THEN 0
							WHEN @disponibile < @pQuantita THEN @disponibile
							ELSE @pQuantita
						END;

					UPDATE dbo.tblRentriImportazioniRelazioni
					SET
						DisponibilePrima = @disponibile,
						QuantitaProposta = IIF(@pModificata = 1, QuantitaProposta, @quota),
						Quantita = @quota
					WHERE
						IdImportazione = @Id
						AND PadreAnno = @pAnno AND PadreProgressivo = @pProgressivo
						AND FiglioAnno = @fAnno AND FiglioProgressivo = @fProgressivo;

					SET @pQuantita = @pQuantita - @quota;
					IF @pQuantita < 0 SET @pQuantita = 0;

					IF @pAnnullato = 0
						UPDATE #figli
						SET Disponibile = Disponibile - @quota
						WHERE Anno = @fAnno AND Progressivo = @fProgressivo;

					FETCH cFigli INTO @fAnno, @fProgressivo, @fQuantita;
				END
				CLOSE cFigli;
				DEALLOCATE cFigli;

				FETCH cPadri INTO @pAnno, @pProgressivo, @pQuantita, @pAnnullato, @pModificata, @pFigli;
			END
			CLOSE cPadri;
			DEALLOCATE cPadri;

			-- Anomalie delle relazioni (sul padre)
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, l.PadreAnno, l.PadreProgressivo, 'E', 'RIFERIMENTO_MANCANTE',
				CONCAT('Si riferisce alla registrazione n. ', l.FiglioProgressivo, '/', l.FiglioAnno, ', che non è stata trovata né su RENTRI né in Ecomatico')
			FROM dbo.tblRentriImportazioniRelazioni l
			WHERE
				l.IdImportazione = @Id
				AND NOT EXISTS (SELECT 1 FROM #figli f WHERE f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo);

			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, l.PadreAnno, l.PadreProgressivo, 'E', 'RELAZIONE_NON_AMMESSA',
				CONCAT('In Ecomatico la registrazione n. ', l.FiglioProgressivo, '/', l.FiglioAnno, ' (', ISNULL(oFiglio.Nome, 'operazione sconosciuta'),
					') non può essere associata a questa (', ISNULL(oPadre.Nome, 'operazione sconosciuta'), ')')
			FROM
				dbo.tblRentriImportazioniRelazioni l
				INNER JOIN dbo.tblRentriImportazioniMovimenti p
					ON p.IdImportazione = l.IdImportazione AND p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
				INNER JOIN #figli f ON f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
				LEFT JOIN dbo.tblRifiutiOperazioni oPadre ON p.IdOperazione = oPadre.Id
				LEFT JOIN dbo.tblRifiutiOperazioni oFiglio ON f.IdOperazione = oFiglio.Id
			WHERE
				l.IdImportazione = @Id
				AND p.IdOperazione IS NOT NULL
				AND f.IdOperazione IS NOT NULL
				AND NOT EXISTS (
					SELECT 1
					FROM dbo.tblRifiutiOperazioniRelazioni x
					WHERE x.Id = p.IdOperazione AND x.IdParent = f.IdOperazione);

			-- Stesso EER, stato fisico e unità di misura (come al salvataggio; non per la derivazione da K/M)
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, l.PadreAnno, l.PadreProgressivo, 'E', 'RELAZIONE_EER',
				CONCAT('La registrazione associata n. ', l.FiglioProgressivo, '/', l.FiglioAnno, ' ha EER, stato fisico o unità di misura diversi')
			FROM
				dbo.tblRentriImportazioniRelazioni l
				INNER JOIN dbo.tblRentriImportazioniMovimenti p
					ON p.IdImportazione = l.IdImportazione AND p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
				INNER JOIN #figli f ON f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
			WHERE
				l.IdImportazione = @Id
				AND ISNULL(p.IdOperazione, '') NOT IN ('K', 'M')
				AND (
					ISNULL(f.IdEer, '') <> ISNULL(p.IdEer, '')
					OR ISNULL(f.IdStatoFisico, '') <> ISNULL(p.IdStatoFisico, '')
					OR ISNULL(f.IdUnitaMisura, '') <> ISNULL(p.IdUnitaMisura, ''));

			-- La registrazione associata non può essere successiva (data, poi numero) a quella che la associa
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, l.PadreAnno, l.PadreProgressivo, 'E', 'RELAZIONE_DATA',
				CONCAT('La registrazione associata n. ', l.FiglioProgressivo, '/', l.FiglioAnno, ' ha data o numero successivi a questa')
			FROM
				dbo.tblRentriImportazioniRelazioni l
				INNER JOIN dbo.tblRentriImportazioniMovimenti p
					ON p.IdImportazione = l.IdImportazione AND p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
				INNER JOIN #figli f ON f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
			WHERE
				l.IdImportazione = @Id
				AND (
					f.Data > p.Data
					OR (f.Data = p.Data AND (f.Anno > p.Anno OR (f.Anno = p.Anno AND f.Progressivo > p.Progressivo))));

			-- Quantità: disponibilità superata o quantità attribuite diverse da quella del padre
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, l.PadreAnno, l.PadreProgressivo, 'E', 'GIACENZA_INSUFFICIENTE',
				CONCAT('La registrazione associata n. ', l.FiglioProgressivo, '/', l.FiglioAnno, ' ha disponibili ',
					FORMAT(IIF(ISNULL(l.DisponibilePrima, 0) < 0, 0, ISNULL(l.DisponibilePrima, 0)), '0.##', 'it-IT'),
					', ne vengono attribuiti ', FORMAT(l.Quantita, '0.##', 'it-IT'))
			FROM dbo.tblRentriImportazioniRelazioni l
			WHERE
				l.IdImportazione = @Id
				AND l.Quantita > ISNULL(l.DisponibilePrima, 0)
				AND EXISTS (SELECT 1 FROM #figli f WHERE f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo);

			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, p.Anno, p.Progressivo, 'E', 'QUANTITA_RELAZIONI',
				IIF(s.Modificata = 0 AND s.Attribuita < ISNULL(p.Quantita, 0),
					CONCAT('Quantità insufficiente nelle registrazioni associate: disponibili ', FORMAT(s.Attribuita, '0.##', 'it-IT'),
						' su ', FORMAT(p.Quantita, '0.##', 'it-IT')),
					CONCAT('Le quantità attribuite alle registrazioni associate (', FORMAT(s.Attribuita, '0.##', 'it-IT'),
						') non corrispondono alla quantità della registrazione (', FORMAT(p.Quantita, '0.##', 'it-IT'), ')'))
			FROM
				dbo.tblRentriImportazioniMovimenti p
				CROSS APPLY (
					SELECT Attribuita = SUM(ISNULL(l.Quantita, 0)), Modificata = MAX(CAST(l.IsModificata AS INT))
					FROM dbo.tblRentriImportazioniRelazioni l
					WHERE l.IdImportazione = @Id AND l.PadreAnno = p.Anno AND l.PadreProgressivo = p.Progressivo
					HAVING COUNT(*) > 0
				) s
			WHERE
				p.IdImportazione = @Id
				AND s.Attribuita <> ISNULL(p.Quantita, 0);

			-- Registrazione che in Ecomatico prevede associazioni ma su RENTRI non ne ha
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'W', 'SENZA_RELAZIONI',
				IIF(m.IdOperazione = 'S',
					'Scarico senza registrazioni associate su RENTRI: verrà importato con "Nessuna registrazione associata"',
					'Su RENTRI non ha registrazioni associate')
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.Azione = 'I'
				AND m.Tipo = 'M'
				AND EXISTS (SELECT 1 FROM dbo.tblRifiutiOperazioniRelazioni x WHERE x.Id = m.IdOperazione)
				AND NOT EXISTS (
					SELECT 1
					FROM dbo.tblRentriImportazioniRelazioni l
					WHERE l.IdImportazione = @Id AND l.PadreAnno = m.Anno AND l.PadreProgressivo = m.Progressivo);

			-- Esclusioni a catena, finché ce ne sono: anomalia bloccante -> esclusa; rettifica o annullamento di un
			-- originale escluso; registrazione che associa una registrazione esclusa
			DECLARE @nuove INT = 1;
			WHILE @nuove > 0
			BEGIN
				UPDATE m
				SET Azione = 'X'
				FROM dbo.tblRentriImportazioniMovimenti m
				WHERE
					m.IdImportazione = @Id
					AND m.Azione = 'I'
					AND EXISTS (
						SELECT 1
						FROM dbo.tblRentriImportazioniAnomalie a
						WHERE a.IdImportazione = @Id AND a.Anno = m.Anno AND a.Progressivo = m.Progressivo AND a.Livello = 'E');

				INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
				SELECT
					@Id, m.Anno, m.Progressivo, 'E', 'ORIGINALE_ESCLUSO',
					CONCAT('La registrazione n. ', o.Progressivo, '/', o.Anno, ' che ', IIF(m.Tipo = 'A', 'annulla', 'rettifica'), ' non può essere importata')
				FROM
					dbo.tblRentriImportazioniMovimenti m
					INNER JOIN dbo.tblRentriImportazioniMovimenti o
						ON o.IdImportazione = m.IdImportazione AND o.Anno = m.RettificaAnno AND o.Progressivo = m.RettificaProgressivo
				WHERE
					m.IdImportazione = @Id
					AND m.Azione = 'I'
					AND o.Azione = 'X';
				SET @nuove = @@ROWCOUNT;

				INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
				SELECT DISTINCT
					@Id, p.Anno, p.Progressivo, 'E', 'ASSOCIATA_ESCLUSA',
					CONCAT('La registrazione associata n. ', f.Progressivo, '/', f.Anno, ' non può essere importata')
				FROM
					dbo.tblRentriImportazioniRelazioni l
					INNER JOIN dbo.tblRentriImportazioniMovimenti p
						ON p.IdImportazione = l.IdImportazione AND p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
					INNER JOIN dbo.tblRentriImportazioniMovimenti f
						ON f.IdImportazione = l.IdImportazione AND f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
				WHERE
					l.IdImportazione = @Id
					AND p.Azione = 'I'
					AND f.Azione = 'X';
				SET @nuove = @nuove + @@ROWCOUNT;
			END

			-- ── 8. Avvisi ─────────────────────────────────────────────────────────────────────────
			-- Registrazioni recuperate fuori dall'intervallo perché richiamate da quelle dell'intervallo
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'W', 'FUORI_INTERVALLO',
				'Registrazione fuori dall''intervallo indicato, recuperata da RENTRI perché richiamata da una registrazione dell''intervallo'
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IsIntervallo = 0
				AND m.Azione = 'I';

			-- Numeri mancanti su RENTRI dentro l'intervallo letto (dal primo numero richiesto all'ultimo trovato)
			;WITH n AS (
				SELECT
					m.Anno, m.Progressivo,
					Precedente = LAG(m.Progressivo) OVER (PARTITION BY m.Anno ORDER BY m.Progressivo)
				FROM dbo.tblRentriImportazioniMovimenti m
				WHERE m.IdImportazione = @Id AND m.IsIntervallo = 1
			)
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, n.Anno, NULL, 'W', 'NUMERI_MANCANTI',
				IIF(x.Dal = x.Al,
					CONCAT('Su RENTRI non c''è la registrazione n. ', x.Dal, '/', n.Anno),
					CONCAT('Su RENTRI non ci sono le registrazioni dal n. ', x.Dal, ' al n. ', x.Al, '/', n.Anno))
			FROM
				n
				CROSS APPLY (
					SELECT
						Dal = ISNULL(n.Precedente + 1, IIF(n.Anno = @dalAnno, @dalNumero, 1)),
						Al = n.Progressivo - 1
				) x
			WHERE x.Dal <= x.Al;

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
END;
GO
