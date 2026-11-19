SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Crea la bozza (Lock = 2) di una registrazione dai dati di un Allegato VII dell'azienda del contesto, inviato o
-- ricevuto da DIWASS (Diwass > Allegati VII, Azioni > Registra nel registro; docs/regole/diwass.md D8), come
-- l'acquisizione da formulario digitale (uspRifiutiMovimenti_ins_DaAcquisizioneFormulario): l'utente controlla la
-- bozza in Rifiuti > Registrazioni, Salva la finalizza con uspRifiutiRegistrazioni_upd, Annulla la cancella con
-- uspRifiutiRegistrazioni_del. Causali ammesse (filtro proprio di questa funzione): trasporto T*aT (T) se l'azienda è
-- un trasportatore, carico da terzi T* (Z) se è l'impianto, scarico a terzi aT (S) se è il produttore o chi organizza.
-- La registrazione si fa solo dopo il passaggio su DIWASS che la giustifica: T*aT dopo la presa in carico del suo
-- trasportatore, T* dopo la ricezione al suo impianto, aT dopo la prima presa in carico (decisione dell'utente del
-- 2026-11-19). I soggetti si prendono dalle sedi in anagrafica collegate agli operatori DIWASS del documento, con
-- un'autorizzazione valida alla data del trasporto per il trasportatore e il destinatario: quelli non trovati restano
-- vuoti, l'utente li sceglie nella scheda della registrazione (come nell'acquisizione da formulario digitale) e gli
-- avvisi restituiti con l'Id dicono quali sono (decisione dell'utente del 2026-11-19).
-- Documento di trasporto Allegato VII (IdTrasportoTransfrontalieroTipo = 'D'), numero DIWASS nelle note del movimento,
-- registrazione collegata all'Allegato VII (tblDiwassAllegatiVii.IdRegistrazione)
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiMovimenti_ins_DaAllegatoVii]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(2000) = NULL;
		DECLARE @returnId CHAR(16) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');

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
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il registro';
			GOTO BRANCH_END;
		END
		IF @IdOperazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la causale';
			GOTO BRANCH_END;
		END

		-- Permessi: Allegati VII in lettura e registrazioni in scrittura
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWA',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
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

		-- Allegato VII dell'azienda del contesto
		DECLARE
			@idAzienda CHAR(16), @numero VARCHAR(50), @stato VARCHAR(20), @ruoli VARCHAR(10), @dataSpedizione DATE,
			@quantita DECIMAL(18, 5), @unitaQuantita CHAR(1), @idEer CHAR(6), @descrizione VARCHAR(500),
			@idAttivita CHAR(2), @idRegistrazioneEsistente CHAR(16);
		SELECT
			@idAzienda = a.IdAziendaInterna,
			@numero = a.Numero,
			@stato = a.Stato,
			@ruoli = ISNULL(a.Ruoli, IIF(ISNULL(a.Ricevuto, 0) = 0, 'O', '')),
			@dataSpedizione = a.DataSpedizione,
			@quantita = a.Quantita,
			@unitaQuantita = a.UnitaQuantita,
			@idEer = a.IdEer,
			@descrizione = a.Descrizione,
			@idAttivita = a.IdAttivita,
			@idRegistrazioneEsistente = a.IdRegistrazione
		FROM
			dbo.tblDiwassAllegatiVii a
			INNER JOIN dbo.tblSessioni e ON a.IdAziendaInterna = e.IdAzienda
		WHERE
			a.Id = @Id
			AND a.Lock = 0
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Allegato VII non trovato nell''azienda del contesto';
			GOTO BRANCH_END;
		END
		IF @numero IS NULL OR @stato IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''Allegato VII non è ancora stato inviato a DIWASS';
			GOTO BRANCH_END;
		END
		IF @stato = 'CANCELLED'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''Allegato VII è annullato su DIWASS: non si registra';
			GOTO BRANCH_END;
		END

		-- Una sola registrazione attiva per Allegato VII (una bozza abbandonata non conta)
		DECLARE @esistenteNumero INT, @esistenteData DATE;
		SELECT
			@esistenteNumero = r.Numero,
			@esistenteData = r.[Data]
		FROM dbo.tblRifiutiRegistrazioni r
		WHERE
			r.Id = @idRegistrazioneEsistente
			AND r.Lock < 2;
		IF @esistenteData IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''Allegato VII ha già la registrazione n. ' + CAST(@esistenteNumero AS VARCHAR(10)) + ' del ' + CONVERT(VARCHAR(10), @esistenteData, 103);
			GOTO BRANCH_END;
		END

		-- Registro di una sede interna dell'azienda, visibile all'utente, del tipo che ammette la causale
		DECLARE @idSedeRegistro CHAR(16), @idTipoRegistro CHAR(1);
		SELECT
			@idSedeRegistro = g.IdSede,
			@idTipoRegistro = g.IdTipo
		FROM
			dbo.tblRifiutiRegistri g
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
		WHERE
			g.Id = @IdRegistro
			AND g.Lock = 0
			AND s.IdAziendaInterna = @idAzienda;

		IF @idSedeRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro non è di una sede dell''azienda dell''Allegato VII';
			GOTO BRANCH_END;
		END

		DECLARE
			@operazione CHAR(1), @codiceOperazione VARCHAR(5), @isProduttore BIT, @isTrasportatore BIT,
			@isDestinatario BIT, @isEsito BIT, @isAttivitaRs BIT, @produttoreSede BIT, @trasportatoreSede BIT,
			@destinatarioSede BIT;
		SELECT
			@operazione = o.Operazione,
			@codiceOperazione = o.Codice,
			@isProduttore = ISNULL(o.IsProduttore, 0),
			@isTrasportatore = ISNULL(o.IsTrasportatore, 0),
			@isDestinatario = ISNULL(o.IsDestinatario, 0),
			@isEsito = ISNULL(o.IsEsito, 0),
			@isAttivitaRs = ISNULL(o.IsAttivitaRs, 0),
			@produttoreSede = ISNULL(o.ProduttoreSede, 0),
			@trasportatoreSede = ISNULL(o.TrasportatoreSede, 0),
			@destinatarioSede = ISNULL(o.DestinatarioSede, 0)
		FROM dbo.tblRifiutiOperazioni o
		WHERE
			o.Id = @IdOperazione
			AND o.Id IN ('T', 'Z', 'S');

		IF @operazione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La causale indicata non è valida per la registrazione da Allegato VII';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRifiutiOperazioniRegistriTipi
			WHERE
				Id = @IdOperazione
				AND IdTipo = @idTipoRegistro
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La causale indicata non è ammessa nel registro selezionato';
			GOTO BRANCH_END;
		END

		-- Ruolo dell'azienda richiesto dalla causale
		IF (@IdOperazione = 'T' AND @ruoli NOT LIKE '%T%')
			OR (@IdOperazione = 'Z' AND @ruoli NOT LIKE '%I%')
			OR (@IdOperazione = 'S' AND @ruoli NOT LIKE '%P%' AND @ruoli NOT LIKE '%O%')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con la causale ' + @codiceOperazione + ' l''azienda deve essere '
				+ CASE @IdOperazione
					WHEN 'T' THEN 'un trasportatore'
					WHEN 'Z' THEN 'l''impianto'
					ELSE 'il produttore o chi organizza la spedizione'
				END + ' nell''Allegato VII';
			GOTO BRANCH_END;
		END

		-- Soggetti del documento con l'operatore DIWASS (della sede in anagrafica o letto da DIWASS), la sede in
		-- anagrafica dell'azienda collegata allo stesso operatore (prima quella del documento, poi le interne) e se
		-- l'operatore è di una sede interna dell'azienda
		DECLARE @soggetti TABLE (
			Ruolo CHAR(1),
			Pos TINYINT,
			OperatorInternalId BIGINT,
			Nome NVARCHAR(250),
			MezzoTrasporto CHAR(1),
			IdSede CHAR(16),
			NSedi INT,
			DellAzienda BIT
		);
		-- Sede: quella del documento se è dell'azienda, altrimenti l'unica sede dell'azienda collegata allo stesso
		-- operatore; con più sedi collegate allo stesso operatore non si sceglie (NSedi > 1, la sceglie l'utente)
		INSERT INTO @soggetti (Ruolo, Pos, OperatorInternalId, Nome, MezzoTrasporto, IdSede, NSedi, DellAzienda)
		SELECT
			x.Ruolo,
			x.Pos,
			v.OperatorInternalId,
			ISNULL(sd.NomeCompleto, x.Nome),
			x.MezzoTrasporto,
			ISNULL(sv.Id, IIF(sc.N = 1, sc.IdUnico, NULL)),
			IIF(sv.Id IS NOT NULL, 1, sc.N),
			CAST(IIF(si.Id IS NULL, 0, 1) AS BIT)
		FROM
			dbo.tblDiwassAllegatiViiSoggetti x
			LEFT JOIN dbo.tblSedi sd ON x.IdSede = sd.Id
			LEFT JOIN dbo.tblSedi sv ON x.IdSede = sv.Id AND sv.IdAziendaInterna = @idAzienda AND sv.Lock = 0
			LEFT JOIN dbo.tblDiwassOperatori od ON x.IdSede = od.Id
			CROSS APPLY (SELECT OperatorInternalId = ISNULL(od.OperatorInternalId, x.OperatorInternalId)) v
			OUTER APPLY (
				SELECT
					N = COUNT(*),
					IdUnico = MIN(z.Id)
				FROM
					dbo.tblSedi z
					INNER JOIN dbo.tblDiwassOperatori oz ON z.Id = oz.Id
				WHERE
					z.IdAziendaInterna = @idAzienda
					AND z.Lock = 0
					AND oz.OperatorInternalId = v.OperatorInternalId
			) sc
					OUTER APPLY (
				SELECT TOP 1 z.Id
				FROM
					dbo.tblDiwassOperatori oz
					INNER JOIN dbo.tblSedi z ON oz.Id = z.Id
				WHERE
					oz.OperatorInternalId = v.OperatorInternalId
					AND z.InternaEsterna = 'I'
					AND z.IdAziendaInterna = @idAzienda
					) si
		WHERE x.Id = @Id;

		-- Passaggio su DIWASS che giustifica la registrazione (le ricezioni e il recupero lette prima della correzione
		-- dell'hub del 2026-11-09 hanno l'operatore 0: valgono per l'unico impianto)
		DECLARE @dataPresaInCarico DATE, @dataRicezione DATE, @quantitaRespinta DECIMAL(18, 5);
		IF @IdOperazione = 'T'
			SELECT @dataPresaInCarico = MIN(k.Data)
			FROM
				@soggetti s
				INNER JOIN dbo.tblDiwassAllegatiViiConferme k ON k.Id = @Id AND k.Tipo = 'T' AND k.OperatorInternalId = s.OperatorInternalId
			WHERE
				s.Ruolo = 'T'
				AND s.DellAzienda = 1;
		ELSE
			SELECT @dataPresaInCarico = MIN(k.Data)
			FROM dbo.tblDiwassAllegatiViiConferme k
			WHERE
				k.Id = @Id
				AND k.Tipo = 'T';

		SELECT TOP 1
			@dataRicezione = k.Data,
			@quantitaRespinta = k.QuantitaRespinta
		FROM
			@soggetti s
			INNER JOIN dbo.tblDiwassAllegatiViiConferme k ON k.Id = @Id AND k.Tipo = 'I' AND (k.OperatorInternalId = s.OperatorInternalId OR ISNULL(k.OperatorInternalId, 0) = 0)
		WHERE
			s.Ruolo = 'I'
			AND k.Data IS NOT NULL
			AND
				(
				@IdOperazione <> 'Z'
				OR s.DellAzienda = 1
				)
		ORDER BY s.Pos;

		IF @IdOperazione IN ('T', 'S') AND @dataPresaInCarico IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@IdOperazione = 'T', N'La presa in carico del trasportatore', N'La presa in carico')
				+ N' non risulta ancora su DIWASS: la registrazione si fa dopo (Azioni > DIWASS – Leggi stato la aggiorna)';
			GOTO BRANCH_END;
		END
		IF @IdOperazione = 'Z' AND @dataRicezione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = N'La ricezione all''impianto non risulta ancora su DIWASS: la registrazione si fa dopo (Azioni > DIWASS – Leggi stato la aggiorna)';
			GOTO BRANCH_END;
		END

		DECLARE @dataTrasporto DATE = ISNULL(@dataPresaInCarico, @dataSpedizione);

		-- ── Soggetti della registrazione ────────────────────────────────────────────────────────────────────────────
		-- Un soggetto per riga: la sede (fissa, quella del registro o dell'azienda, oppure dal documento) e
		-- l'autorizzazione del ruolo valida alla data del trasporto. Si compila solo con una corrispondenza unica; con
		-- nessuna o più corrispondenze il campo resta vuoto e l'avviso dice quale e perché (lo sceglie l'utente nella
		-- registrazione, come nell'acquisizione da formulario digitale)
		DECLARE @idAziendaRegistro CHAR(16) = (SELECT IdAziendaInterna
		FROM dbo.tblSedi
		WHERE Id = @idSedeRegistro);
		DECLARE @dataTesto NVARCHAR(10) = CONVERT(NVARCHAR(10), @dataTrasporto, 103);

		DECLARE @req TABLE (
			Ordine INT IDENTITY(1, 1),
			Tipo CHAR(1),
			PosTrasportatore TINYINT,
			Etichetta NVARCHAR(60),
			Nome NVARCHAR(250),
			OperatorInternalId BIGINT,
			MezzoTrasporto CHAR(1),
			IdSede CHAR(16),
			NSedi INT,
			IdAutorizzazione CHAR(16),
			NAutorizzazioni INT
		);

		-- Produttore: la sede del registro (scarico a terzi) o il produttore del documento, se manca chi organizza
		IF @isProduttore = 1
		BEGIN
			IF @produttoreSede = 1
				INSERT INTO @req (Tipo, Etichetta, Nome, IdSede, NSedi)
				SELECT 'P', N'Produttore', NomeCompleto, Id, 1
				FROM dbo.tblSedi
				WHERE Id = @idSedeRegistro;
			ELSE
				INSERT INTO @req (Tipo, Etichetta, Nome, OperatorInternalId, IdSede, NSedi)
				SELECT TOP 1 'P', IIF(Ruolo = 'P', N'Produttore', N'Chi organizza la spedizione (produttore)'), Nome, OperatorInternalId, IdSede, NSedi
				FROM @soggetti
				WHERE Ruolo IN ('P', 'O')
				ORDER BY IIF(Ruolo = 'P', 0, 1), Pos;
		END

		-- Destinatario: la sede del registro (carico da terzi) o il primo impianto del documento
		IF @isDestinatario = 1
		BEGIN
			IF @destinatarioSede = 1
				INSERT INTO @req (Tipo, Etichetta, Nome, IdSede, NSedi)
				SELECT 'D', N'Destinatario', NomeCompleto, Id, 1
				FROM dbo.tblSedi
				WHERE Id = @idSedeRegistro;
			ELSE
				INSERT INTO @req (Tipo, Etichetta, Nome, OperatorInternalId, IdSede, NSedi)
				SELECT TOP 1 'D', N'Impianto', Nome, OperatorInternalId, IdSede, NSedi
				FROM @soggetti
				WHERE Ruolo = 'I'
				ORDER BY Pos;
		END

		-- Trasportatori: l'azienda del registro (trasporto) o fino a tre trasportatori del documento; mezzo dal documento
		IF @isTrasportatore = 1
		BEGIN
			IF @trasportatoreSede = 1
				INSERT INTO @req (Tipo, PosTrasportatore, Etichetta, Nome, MezzoTrasporto, IdSede, NSedi)
				SELECT TOP 1 'T', 0, N'Trasportatore', z.NomeCompleto, s.MezzoTrasporto, @idAziendaRegistro, 1
				FROM
					@soggetti s
					INNER JOIN dbo.tblSedi z ON z.Id = @idAziendaRegistro
				WHERE
					s.Ruolo = 'T'
					AND s.DellAzienda = 1
				ORDER BY s.Pos;
			ELSE
				INSERT INTO @req (Tipo, PosTrasportatore, Etichetta, Nome, OperatorInternalId, MezzoTrasporto, IdSede, NSedi)
				SELECT TOP 3 'T', ROW_NUMBER() OVER (ORDER BY Pos) - 1, N'Trasportatore', Nome, OperatorInternalId, MezzoTrasporto, IdSede, NSedi
				FROM @soggetti
				WHERE Ruolo = 'T'
				ORDER BY Pos;
		END

		-- Autorizzazione del ruolo valida alla data del trasporto (non "Nessuna"): della sede o, se la sede non ne ha,
		-- della sua azienda (per destinatario e trasportatore); compilata solo se è una
		UPDATE q
		SET
			NAutorizzazioni = au.N,
			IdAutorizzazione = IIF(au.N = 1, au.IdUnico, NULL)
		FROM
			@req q
			INNER JOIN dbo.tblSedi z ON q.IdSede = z.Id
			CROSS APPLY (
				SELECT TOP 1
					N = COUNT(*),
					IdUnico = MIN(a.Id)
				FROM dbo.tblRifiutiAutorizzazioni a
				WHERE
					(
					a.IdSede = z.Id
					OR
						(
						q.Tipo IN ('D', 'T')
						AND a.IdSede = z.IdParent
						)
					)
					AND a.IdRuolo = q.Tipo
					AND a.Lock = 0
					AND ISNULL(a.Disabilitata, 0) = 0
					AND ISNULL(a.Nessuna, 0) = 0
					AND @dataTrasporto BETWEEN a.DataInizio AND a.DataFine
				GROUP BY IIF(a.IdSede = z.Id, 0, 1)
				ORDER BY IIF(a.IdSede = z.Id, 0, 1)
			) au
		WHERE q.NSedi = 1;

		UPDATE @req
		SET NAutorizzazioni = 0
		WHERE
			NSedi = 1
			AND NAutorizzazioni IS NULL;

		-- Produttore senza autorizzazioni da produttore: l'autorizzazione "Nessuna" della sede (creata se manca)
		DECLARE @idSedeProduttoreNessuna CHAR(16) = NULL;
		UPDATE q
		SET IdAutorizzazione = ( SELECT TOP 1 a.Id FROM dbo.tblRifiutiAutorizzazioni a WHERE a.IdSede = q.IdSede AND a.IdRuolo = 'P' AND a.Nessuna = 1 AND a.Lock = 0 )
		FROM @req q
		WHERE
			q.Tipo = 'P'
			AND q.NSedi = 1
			AND q.NAutorizzazioni = 0;

		SELECT @idSedeProduttoreNessuna = IdSede
		FROM @req
		WHERE
			Tipo = 'P'
			AND NSedi = 1
			AND NAutorizzazioni = 0
			AND IdAutorizzazione IS NULL;

		-- Avvisi, uno per soggetto da completare
		-- Avvisi, uno per soggetto da completare: ruolo (in grassetto nella finestra) e testo "soggetto – motivo"
		DECLARE @mancanti TABLE (Pos INT IDENTITY(1, 1), Ruolo NVARCHAR(60), Testo NVARCHAR(400), Mancante BIT);
		-- Mancante = 1: soggetto o autorizzazione da inserire in anagrafica; 0: più corrispondenze, solo da scegliere
		INSERT INTO @mancanti (Ruolo, Testo, Mancante)
		SELECT
			q.Etichetta,
			ISNULL(q.Nome, N'') + ISNULL(N' (operatore DIWASS ' + CAST(q.OperatorInternalId AS NVARCHAR(20)) + N')', N'') + N' – '
			+ CASE
				WHEN ISNULL(q.NSedi, 0) = 0 THEN N'non è in anagrafica'
				WHEN q.NSedi > 1 THEN CAST(q.NSedi AS NVARCHAR(10)) + N' soggetti in anagrafica collegati allo stesso operatore, sceglierne uno'
				WHEN q.NAutorizzazioni = 0 THEN N'nessuna autorizzazione da ' + IIF(q.Tipo = 'D', N'destinatario', N'trasportatore') + N' valida al ' + @dataTesto
				ELSE CAST(q.NAutorizzazioni AS NVARCHAR(10)) + N' autorizzazioni valide al ' + @dataTesto + N', sceglierne una'
			END,
			CAST(IIF(ISNULL(q.NSedi, 0) = 0 OR (q.NSedi = 1 AND q.NAutorizzazioni = 0), 1, 0) AS BIT)
		FROM @req q
		WHERE
			q.IdAutorizzazione IS NULL
			AND NOT (q.Tipo = 'P' AND q.NSedi = 1 AND q.NAutorizzazioni = 0)
		ORDER BY q.Ordine;

		IF @isTrasportatore = 1 AND NOT EXISTS (SELECT 1
		FROM @req
		WHERE Tipo = 'T')
			INSERT INTO @mancanti (Ruolo, Testo, Mancante)
			VALUES (N'Trasportatore', N'il documento non ne indica nessuno', 0);

		-- Elenco per la finestra "Da completare" della scheda della registrazione
		DECLARE @avvisi NVARCHAR(MAX) = (SELECT Ruolo, Testo, Mancante
		FROM @mancanti
		ORDER BY Pos
		FOR JSON PATH);

		DECLARE @idAutorizzazioneProduttore CHAR(16) = (SELECT IdAutorizzazione
		FROM @req
		WHERE Tipo = 'P');
		DECLARE @idAutorizzazioneDestinatario CHAR(16) = (SELECT IdAutorizzazione
		FROM @req
		WHERE Tipo = 'D');
		DECLARE @trasportatori TABLE (Pos TINYINT, IdAutorizzazione CHAR(16), IdTipo CHAR(1));
		INSERT INTO @trasportatori (Pos, IdAutorizzazione, IdTipo)
		SELECT
			PosTrasportatore,
			IdAutorizzazione,
			CASE MezzoTrasporto
				WHEN 'R' THEN 'G'
				WHEN 'T' THEN 'T'
				WHEN 'S' THEN 'N'
			END
		FROM @req
		WHERE
			Tipo = 'T'
			AND IdAutorizzazione IS NOT NULL;

		-- ── Dati del movimento e della registrazione ────────────────────────────────────────────────────────────────
		DECLARE @idUnitaMisura CHAR(2) = IIF(@unitaQuantita = 'M', 'MC', 'TN');
		DECLARE @quantitaMovimento DECIMAL(18, 3) = ISNULL(@quantita, 0);
		IF @isAttivitaRs = 0 SET @idAttivita = NULL;
		-- Esito solo se l'impianto ha accettato tutto: con una quantità respinta lo completa l'utente
		DECLARE @idEsito CHAR(1) = IIF(@isEsito = 1 AND @dataRicezione IS NOT NULL AND ISNULL(@quantitaRespinta, 0) = 0, 'A', NULL);
		DECLARE @dataFineTrasporto SMALLDATETIME = IIF(@IdOperazione IN ('T', 'Z') OR @idEsito IS NOT NULL, @dataRicezione, NULL);
		DECLARE @note VARCHAR(500) = LEFT('Allegato VII ' + @numero, 500);

		-- Data di registrazione proposta: oggi, come nell'acquisizione da formulario digitale
		DECLARE @registrazioneData DATE = CAST(GETDATE() AS DATE);
		CREATE TABLE #numero (Rtn INT);
		INSERT #numero EXEC dbo.uspRifiutiRegistrazioni_get_UltimoNumero @IdRegistro = @IdRegistro, @Data = @registrazioneData, @IdSessione = @IdSessione;
		DECLARE @registrazioneNumero INT = (SELECT TOP 1 Rtn + 1
		FROM #numero);

		-- uspId_get FUORI dalla transazione
		DECLARE @idMovimento CHAR(16);
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idMovimento OUTPUT;
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;
		IF @idSedeProduttoreNessuna IS NOT NULL
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @NoLog = 1, @Id = @idAutorizzazioneProduttore OUTPUT;

		BEGIN TRANSACTION;

			IF @idSedeProduttoreNessuna IS NOT NULL
				INSERT INTO dbo.tblRifiutiAutorizzazioni (Id, IdSede, IdRuolo, DataInizio, DataFine, Nessuna, Disabilitata, Lock)
				VALUES (@idAutorizzazioneProduttore, @idSedeProduttoreNessuna, 'P', '19000101', '20501231', 1, 0, 0);

			INSERT INTO dbo.tblRifiutiMovimenti (Id, IdRegistro, IdOperazione, IdEer, EerDescrizione, IdAttivita, IdUnitaMisura, Quantita, DataInizioTrasporto, Note)
			VALUES (@idMovimento, @IdRegistro, @IdOperazione, @idEer, LEFT(@descrizione, 200), @idAttivita, @idUnitaMisura, @quantitaMovimento, @dataTrasporto, @note);

			IF @idAutorizzazioneProduttore IS NOT NULL
				INSERT INTO dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
				VALUES (@idMovimento, @idAutorizzazioneProduttore, @quantitaMovimento, 0);

			IF @idAutorizzazioneDestinatario IS NOT NULL
				INSERT INTO dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
				VALUES (@idMovimento, @idAutorizzazioneDestinatario, 0);

			INSERT INTO dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, IdTipo, Pos)
			SELECT @idMovimento, IdAutorizzazione, IdTipo, ROW_NUMBER() OVER (ORDER BY Pos) - 1
			FROM @trasportatori;

			INSERT INTO dbo.tblRifiutiRegistrazioni (Id, IdMovimento, Operazione, [Data], Numero, IdEsito, DataFineTrasporto, IdTrasportoTransfrontalieroTipo, Lock)
			VALUES (@returnId, @idMovimento, @operazione, @registrazioneData, @registrazioneNumero, @idEsito, @dataFineTrasporto, 'D', 2);

			UPDATE dbo.tblDiwassAllegatiVii
			SET IdRegistrazione = @returnId
			WHERE Id = @Id;

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

	SELECT
		Id = @returnId,
		Avvisi = @avvisi;

END;
GO
