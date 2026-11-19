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
-- un'autorizzazione valida alla data del trasporto per il trasportatore e il destinatario: se ne manca uno la
-- registrazione non si crea e il messaggio dice tutto quello che manca (si completa l'anagrafica e si rifà).
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
			DellAzienda BIT
		);
		INSERT INTO @soggetti (Ruolo, Pos, OperatorInternalId, Nome, MezzoTrasporto, IdSede, DellAzienda)
		SELECT
			x.Ruolo,
			x.Pos,
			v.OperatorInternalId,
			ISNULL(sd.NomeCompleto, x.Nome),
			x.MezzoTrasporto,
			sc.Id,
			CAST(IIF(si.Id IS NULL, 0, 1) AS BIT)
		FROM
			dbo.tblDiwassAllegatiViiSoggetti x
			LEFT JOIN dbo.tblSedi sd ON x.IdSede = sd.Id
			LEFT JOIN dbo.tblDiwassOperatori od ON x.IdSede = od.Id
			CROSS APPLY (SELECT OperatorInternalId = ISNULL(od.OperatorInternalId, x.OperatorInternalId)) v
			OUTER APPLY (
				SELECT TOP 1 z.Id
				FROM
					dbo.tblSedi z
					LEFT JOIN dbo.tblDiwassOperatori oz ON z.Id = oz.Id
				WHERE
					z.IdAziendaInterna = @idAzienda
					AND z.Lock = 0
					AND
						(
						z.Id = x.IdSede
						OR oz.OperatorInternalId = v.OperatorInternalId
						)
				ORDER BY IIF(z.Id = x.IdSede, 0, 1), IIF(z.InternaEsterna = 'I', 0, 1), z.Id
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
		DECLARE @mancanti TABLE (Pos INT IDENTITY(1, 1), Testo NVARCHAR(400));
		DECLARE @idAziendaRegistro CHAR(16) = (SELECT IdAziendaInterna
		FROM dbo.tblSedi
		WHERE Id = @idSedeRegistro);

		-- Produttore: la sede del registro (scarico a terzi) o il produttore del documento, se manca chi organizza;
		-- un'autorizzazione da produttore valida o, senza, l'autorizzazione "Nessuna" della sede (creata se manca)
		DECLARE @idSedeProduttore CHAR(16), @idAutorizzazioneProduttore CHAR(16), @idSedeProduttoreNessuna CHAR(16);
		IF @isProduttore = 1
		BEGIN
			IF @produttoreSede = 1
				SET @idSedeProduttore = @idSedeRegistro;
			ELSE
			BEGIN
				DECLARE @produttoreNome NVARCHAR(250), @produttoreOperatore BIGINT, @produttoreRuolo CHAR(1);
				SELECT TOP 1
					@idSedeProduttore = IdSede,
					@produttoreNome = Nome,
					@produttoreOperatore = OperatorInternalId,
					@produttoreRuolo = Ruolo
				FROM @soggetti
				WHERE Ruolo IN ('P', 'O')
				ORDER BY IIF(Ruolo = 'P', 0, 1), Pos;

				IF @idSedeProduttore IS NULL
					INSERT INTO @mancanti (Testo)
					VALUES (IIF(@produttoreRuolo = 'P', N'il produttore ', N'chi organizza la spedizione (produttore) ') + ISNULL(@produttoreNome, N'') + ISNULL(N' (operatore DIWASS ' + CAST(@produttoreOperatore AS NVARCHAR(20)) + N')', N'')
						+ N' non è collegato a un soggetto in anagrafica: inserirlo in Anagrafica e collegarlo in Diwass > Operatori');
			END

			IF @idSedeProduttore IS NOT NULL
			BEGIN
				SELECT TOP 1 @idAutorizzazioneProduttore = a.Id
				FROM dbo.tblRifiutiAutorizzazioni a
				WHERE
					a.IdSede = @idSedeProduttore
					AND a.IdRuolo = 'P'
					AND a.Lock = 0
					AND ISNULL(a.Disabilitata, 0) = 0
					AND ISNULL(a.Nessuna, 0) = 0
					AND @dataTrasporto BETWEEN a.DataInizio AND a.DataFine
				ORDER BY a.DataFine DESC, a.Id;

				IF @idAutorizzazioneProduttore IS NULL
					SELECT TOP 1 @idAutorizzazioneProduttore = a.Id
					FROM dbo.tblRifiutiAutorizzazioni a
					WHERE
						a.IdSede = @idSedeProduttore
						AND a.IdRuolo = 'P'
						AND a.Nessuna = 1
						AND a.Lock = 0;

				IF @idAutorizzazioneProduttore IS NULL
					SET @idSedeProduttoreNessuna = @idSedeProduttore;
			END
		END

		-- Destinatario: la sede del registro (carico da terzi) o l'impianto del documento, con un'autorizzazione da
		-- destinatario valida alla data del trasporto
		DECLARE @idAutorizzazioneDestinatario CHAR(16);
		IF @isDestinatario = 1
		BEGIN
			DECLARE @idSedeDestinatario CHAR(16), @destinatarioNome NVARCHAR(250), @destinatarioOperatore BIGINT;
			IF @destinatarioSede = 1
				SELECT
					@idSedeDestinatario = Id,
					@destinatarioNome = NomeCompleto
				FROM dbo.tblSedi
				WHERE Id = @idSedeRegistro;
			ELSE
				SELECT TOP 1
					@idSedeDestinatario = s.IdSede,
					@destinatarioNome = s.Nome,
					@destinatarioOperatore = s.OperatorInternalId
				FROM @soggetti s
				WHERE s.Ruolo = 'I'
				ORDER BY s.Pos;

			IF @idSedeDestinatario IS NULL
				INSERT INTO @mancanti (Testo)
				VALUES (N'l''impianto ' + ISNULL(@destinatarioNome, N'') + ISNULL(N' (operatore DIWASS ' + CAST(@destinatarioOperatore AS NVARCHAR(20)) + N')', N'')
					+ N' non è collegato a un soggetto in anagrafica: inserirlo in Anagrafica e collegarlo in Diwass > Operatori');
			ELSE
			BEGIN
				SELECT TOP 1 @idAutorizzazioneDestinatario = a.Id
				FROM
					dbo.tblRifiutiAutorizzazioni a
					INNER JOIN dbo.tblSedi z ON z.Id = @idSedeDestinatario
				WHERE
					a.IdSede IN (z.Id, z.IdParent)
					AND a.IdRuolo = 'D'
					AND a.Lock = 0
					AND ISNULL(a.Disabilitata, 0) = 0
					AND ISNULL(a.Nessuna, 0) = 0
					AND @dataTrasporto BETWEEN a.DataInizio AND a.DataFine
				ORDER BY IIF(a.IdSede = z.Id, 0, 1), a.DataFine DESC, a.Id;

				IF @idAutorizzazioneDestinatario IS NULL
					INSERT INTO @mancanti (Testo)
					VALUES (ISNULL(@destinatarioNome, N'l''impianto') + N' non ha un''autorizzazione da destinatario valida al ' + CONVERT(NVARCHAR(10), @dataTrasporto, 103));
			END
		END

		-- Trasportatori: l'azienda del registro (trasporto) o i trasportatori del documento, ciascuno con
		-- un'autorizzazione da trasportatore valida alla data del trasporto; mezzo dal documento
		DECLARE @trasportatori TABLE (Pos TINYINT, IdAutorizzazione CHAR(16), IdTipo CHAR(1));
		IF @isTrasportatore = 1
		BEGIN
			DECLARE @tras TABLE (Pos TINYINT, IdSede CHAR(16), Nome NVARCHAR(250), OperatorInternalId BIGINT, MezzoTrasporto CHAR(1));
			IF @trasportatoreSede = 1
				INSERT INTO @tras (Pos, IdSede, Nome, OperatorInternalId, MezzoTrasporto)
				SELECT TOP 1 0, @idAziendaRegistro, ISNULL(z.NomeCompleto, s.Nome), NULL, s.MezzoTrasporto
				FROM
					@soggetti s
					LEFT JOIN dbo.tblSedi z ON z.Id = @idAziendaRegistro
				WHERE
					s.Ruolo = 'T'
					AND s.DellAzienda = 1
				ORDER BY s.Pos;
			ELSE
				INSERT INTO @tras (Pos, IdSede, Nome, OperatorInternalId, MezzoTrasporto)
				SELECT TOP 3 ROW_NUMBER() OVER (ORDER BY s.Pos) - 1, s.IdSede, s.Nome, s.OperatorInternalId, s.MezzoTrasporto
				FROM @soggetti s
				WHERE s.Ruolo = 'T'
				ORDER BY s.Pos;

			INSERT INTO @mancanti (Testo)
			SELECT N'il trasportatore ' + ISNULL(t.Nome, N'') + ISNULL(N' (operatore DIWASS ' + CAST(t.OperatorInternalId AS NVARCHAR(20)) + N')', N'')
				+ N' non è collegato a un soggetto in anagrafica: inserirlo in Anagrafica e collegarlo in Diwass > Operatori'
			FROM @tras t
			WHERE t.IdSede IS NULL
			ORDER BY t.Pos;

			INSERT INTO @trasportatori (Pos, IdAutorizzazione, IdTipo)
			SELECT
				t.Pos,
				au.Id,
				CASE t.MezzoTrasporto
					WHEN 'R' THEN 'G'
					WHEN 'T' THEN 'T'
					WHEN 'S' THEN 'N'
				END
			FROM
				@tras t
				INNER JOIN dbo.tblSedi z ON t.IdSede = z.Id
				OUTER APPLY (
					SELECT TOP 1 a.Id
					FROM dbo.tblRifiutiAutorizzazioni a
					WHERE
						a.IdSede IN (z.Id, z.IdParent)
						AND a.IdRuolo = 'T'
						AND a.Lock = 0
						AND ISNULL(a.Disabilitata, 0) = 0
						AND ISNULL(a.Nessuna, 0) = 0
						AND @dataTrasporto BETWEEN a.DataInizio AND a.DataFine
					ORDER BY IIF(a.IdSede = z.Id, 0, 1), a.DataFine DESC, a.Id
				) au;

			INSERT INTO @mancanti (Testo)
			SELECT ISNULL(z.NomeCompleto, t.Nome) + N' non ha un''autorizzazione da trasportatore valida al ' + CONVERT(NVARCHAR(10), @dataTrasporto, 103)
			FROM
				@tras t
				INNER JOIN dbo.tblSedi z ON t.IdSede = z.Id
				INNER JOIN @trasportatori r ON t.Pos = r.Pos
			WHERE r.IdAutorizzazione IS NULL
			ORDER BY t.Pos;

			DELETE @trasportatori
			WHERE IdAutorizzazione IS NULL;

			IF NOT EXISTS (SELECT 1
			FROM @tras)
				INSERT INTO @mancanti (Testo)
				VALUES (N'il documento non ha trasportatori');
		END

		IF EXISTS (SELECT 1
		FROM @mancanti)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = LEFT(N'Per registrare l''Allegato VII completare l''anagrafica: '
				+ STUFF((SELECT N'; ' + Testo
				FROM @mancanti ORDER BY Pos FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N''), 2000);
			GOTO BRANCH_END;
		END

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
			SELECT @idMovimento, IdAutorizzazione, IdTipo, Pos
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

	SELECT Id = @returnId;

END;
GO
