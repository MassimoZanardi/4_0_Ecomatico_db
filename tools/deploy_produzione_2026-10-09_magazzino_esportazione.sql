/*
Deploy produzione 2026-10-09 - Esportazione in Excel e CSV degli elenchi del modulo Magazzino

Indipendente dagli altri script del 2026-10-09: usa solo tabelle e SP già in produzione. Rieseguibile.
Eseguire con sqlcmd -f 65001 -I.

SP di esportazione, una per elenco: stesse righe e stesso ordine della SP dell'elenco, colonne con il nome
dell'intestazione, al massimo @MaxRighe + 1 righe.
1. uspMagazziniArticoli_get_Esportazione: articoli.
2. uspMagazziniMovimenti_get_Esportazione: movimenti e DDT emessi.
3. uspMagazziniLotti_get_Esportazione: lotti (chiama uspMagazziniLotti_get_List).
4. uspMagazziniGiacenze_get_Esportazione: giacenze per articolo e per lotto (chiama
   uspMagazziniGiacenze_get_List).
5. uspMagazziniGiacenze_get_Carichi_Esportazione: carichi in giacenza (chiama
   uspMagazziniGiacenze_get_Carichi_List).

Nessuna modifica alle tabelle né alle SP degli elenchi. Va deployato insieme all'app.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/


PRINT 'uspMagazziniArticoli_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Articoli di magazzino: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel,
-- Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService,
-- CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si
-- modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspMagazziniArticoli_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspMagazziniArticoli_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

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
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga
		SELECT TOP (@MaxRighe + 1)
			[Nome] = a.Nome,
			[Codice] = a.Codice,
			[Unità di misura] = u.Nome,
			[Descrizione] = a.Descrizione
		FROM
			dbo.tblMagazziniArticoli a
			INNER JOIN dbo.tblSessioni e ON a.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblUnitaMisura u ON a.IdUnitaMisura = u.Id
		WHERE
			e.Id = @IdSessione
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

PRINT 'uspMagazziniMovimenti_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Movimenti di magazzino e DDT emessi: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta
-- in Excel, Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione
-- (ExcelService, CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa
-- si esporta si modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspMagazziniMovimenti_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al
-- massimo @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
-- Come l'elenco, serve due pagine: Magazzino > Movimenti (@DdtEmessi = 0) e Magazzino > DDT (@DdtEmessi = 1),
-- con intestazioni diverse sulle stesse righe.
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimenti_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdOperazione CHAR(1) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@ConDdt BIT = 0,
	@DdtNumero INT = NULL,
	@DdtNumeroFornitore VARCHAR(20) = NULL,
	@DdtMittente VARCHAR(50) = NULL,
	@DdtDestinatario VARCHAR(50) = NULL,
	@DdtTrasportatore VARCHAR(50) = NULL,
	@DdtEmessi BIT = 0,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOperazione = NULLIF(LTRIM(RTRIM(@IdOperazione)), '');
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		-- Ricerca sul DDT: "Con DDT" limita ai movimenti che hanno un DDT e abilita gli altri filtri
		-- sul DDT, che senza di esso vengono ignorati. Elenco DDT: solo i movimenti con un DDT emesso,
		-- cioè non ricevuto da un fornitore (sezionale R); date e ordinamento sono quelli del DDT
		SET @ConDdt = ISNULL(@ConDdt, 0);
		SET @DdtEmessi = ISNULL(@DdtEmessi, 0);
		IF @DdtEmessi = 1 SET @ConDdt = 1;
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

		-- Controlla il permesso sulla funzione
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

		-- Elenco DDT: la sede è quella del contesto della sessione (tblSessioni.IdSede); contesto "tutte le
		-- sedi" = nessuna riga. L'elenco dei movimenti resta sull'azienda del contesto
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT TOP (@MaxRighe + 1)
			Ordine = ROW_NUMBER() OVER (ORDER BY IIF(@DdtEmessi = 1, d.[Data], m.[Data]) DESC, IIF(@DdtEmessi = 1, d.Numero, m.Numero) DESC, m.Numero DESC),
			MovimentoNumero = m.Numero,
			MovimentoData = m.[Data],
			Operazione = o.Nome,
			Righe = ISNULL(r.RigheCount, 0) + ISNULL(re.RigheCount, 0),
			DdtNumero = d.Numero,
			DdtSezionale = d.Sezionale,
			DdtNumeroFornitore = d.NumeroFornitore,
			DdtData = d.[Data],
			DdtCausale = d.CausaleNome,
			DdtSede = d.SedeNome,
			DdtMittente = d.MittenteNome,
			DdtDestinatario = d.DestinatarioNome,
			DdtDestinazione = d.DestinazioneNome,
			DdtTrasportatore = d.TrasportatoreNome,
			DdtInizioTrasporto = d.DataInizioTrasporto,
			DdtPeso = d.Peso
		INTO #righe
		FROM
			dbo.tblMagazziniMovimenti m
			INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblMagazziniOperazioni o ON m.IdOperazione = o.Id
			OUTER APPLY (SELECT RigheCount = COUNT(*) FROM dbo.tblMagazziniMovimentiRighe WHERE IdMovimento = m.Id) r
			OUTER APPLY (SELECT RigheCount = COUNT(*) FROM dbo.tblMagazziniMovimentiRigheEoW WHERE IdMovimento = m.Id) re
			-- DDT del movimento (al massimo uno); NULL se non c'è
			OUTER APPLY (
				SELECT TOP (1)
					dd.Id,
					dd.IdSede,
					dd.Numero,
					dd.NumeroFornitore,
					dd.Sezionale,
					dd.[Data],
					dd.IdMittente,
					dd.IdDestinatario,
					dd.IdTrasportatore,
					dd.DataInizioTrasporto,
					dd.Peso,
					SedeNome = sd.NomeCompleto + ISNULL(' ' + sd.IndirizzoCompleto, ''),
					CausaleNome = ca.Nome,
					MittenteNome = mt.NomeCompleto + ISNULL(' ' + mt.IndirizzoCompleto, ''),
					DestinatarioNome = ds.NomeCompleto + ISNULL(' ' + ds.IndirizzoCompleto, ''),
					DestinazioneNome = dz.NomeCompleto + ISNULL(' ' + dz.IndirizzoCompleto, ''),
					TrasportatoreNome = tr.NomeCompleto + ISNULL(' ' + tr.IndirizzoCompleto, '')
				FROM
					dbo.tblMagazziniDdt dd
					LEFT JOIN dbo.tblSedi sd ON dd.IdSede = sd.Id
					LEFT JOIN dbo.tblMagazziniCausali ca ON dd.IdCausale = ca.Id
					LEFT JOIN dbo.tblSedi mt ON dd.IdMittente = mt.Id
					LEFT JOIN dbo.tblSedi ds ON dd.IdDestinatario = ds.Id
					LEFT JOIN dbo.tblSedi dz ON dd.IdDestinazione = dz.Id
					LEFT JOIN dbo.tblSedi tr ON dd.IdTrasportatore = tr.Id
				WHERE dd.IdMovimento = m.Id
				ORDER BY dd.Id
			) d
		WHERE
			e.Id = @IdSessione
			AND m.Lock = 0
			AND (@IdOperazione IS NULL OR m.IdOperazione = @IdOperazione)
			AND (@DallaData IS NULL OR IIF(@DdtEmessi = 1, d.[Data], m.[Data]) >= @DallaData)
			AND (@AllaData IS NULL OR IIF(@DdtEmessi = 1, d.[Data], m.[Data]) <= @AllaData)
			AND (@ConDdt = 0 OR d.Id IS NOT NULL)
			AND (@DdtEmessi = 0 OR ISNULL(d.Sezionale, '') <> 'R')
			AND (@DdtEmessi = 0 OR d.IdSede = @idSede)
			AND (@DdtNumero IS NULL OR d.Numero = @DdtNumero)
			AND (@DdtNumeroFornitore IS NULL OR d.NumeroFornitore LIKE '%' + @DdtNumeroFornitore + '%')
			AND (@DdtMittente IS NULL OR EXISTS (SELECT 1 FROM dbo.tblSedi sm WHERE sm.Id = d.IdMittente AND sm.NomeCompleto + ISNULL(' ' + sm.IndirizzoCompleto, '') LIKE '%' + @DdtMittente + '%'))
			AND (@DdtDestinatario IS NULL OR EXISTS (SELECT 1 FROM dbo.tblSedi sn WHERE sn.Id = d.IdDestinatario AND sn.NomeCompleto + ISNULL(' ' + sn.IndirizzoCompleto, '') LIKE '%' + @DdtDestinatario + '%'))
			AND (@DdtTrasportatore IS NULL OR EXISTS (SELECT 1 FROM dbo.tblSedi st WHERE st.Id = d.IdTrasportatore AND st.NomeCompleto + ISNULL(' ' + st.IndirizzoCompleto, '') LIKE '%' + @DdtTrasportatore + '%'))
		ORDER BY
			IIF(@DdtEmessi = 1, d.[Data], m.[Data]) DESC,
			IIF(@DdtEmessi = 1, d.Numero, m.Numero) DESC,
			m.Numero DESC
		OPTION (RECOMPILE);

		IF @DdtEmessi = 1
			SELECT
				[Numero] = DdtNumero,
				[Sezionale] = DdtSezionale,
				[Data] = DdtData,
				[Causale] = DdtCausale,
				[Mittente] = DdtMittente,
				[Destinatario] = DdtDestinatario,
				[Destinazione] = DdtDestinazione,
				[Trasportatore] = DdtTrasportatore,
				[Inizio trasporto] = DdtInizioTrasporto,
				[Peso] = DdtPeso,
				[Operazione] = Operazione,
				[Movimento] = MovimentoNumero,
				[Data movimento] = MovimentoData,
				[Righe] = Righe
			FROM #righe
			ORDER BY Ordine;
		ELSE
			SELECT
				[Numero] = MovimentoNumero,
				[Data] = MovimentoData,
				[Operazione] = Operazione,
				[Righe] = Righe,
				[DDT nr] = DdtNumero,
				[DDT sezionale] = DdtSezionale,
				[DDT nr fornitore] = DdtNumeroFornitore,
				[DDT data] = DdtData,
				[DDT sede] = DdtSede,
				[DDT causale] = DdtCausale,
				[DDT mittente] = DdtMittente,
				[DDT destinatario] = DdtDestinatario,
				[DDT destinazione] = DdtDestinazione,
				[DDT trasportatore] = DdtTrasportatore,
				[DDT inizio trasporto] = DdtInizioTrasporto,
				[DDT peso] = DdtPeso
			FROM #righe
			ORDER BY Ordine;

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

PRINT 'uspMagazziniLotti_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Lotti di magazzino: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspMagazziniLotti_get_List (che controlla anche permesso e sede del contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspMagazziniLotti_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdArticolo CHAR(16) = NULL,
	@Aperto BIT = NULL,
	@Disabilitato BIT = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);
		DECLARE @righe INT = @MaxRighe + 1;

		CREATE TABLE #righe (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			StatoValore INT NULL,
			StatoDescrizione VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			Nome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			ArticoloNome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			DataApertura DATE NULL,
			DataChiusura DATE NULL,
			QuantitaMax DECIMAL(18, 2) NULL,
			Disponibilita DECIMAL(38, 2) NULL,
			Disabilitato BIT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, StatoValore, StatoDescrizione, Nome, ArticoloNome, DataApertura, DataChiusura, QuantitaMax, Disponibilita, Disabilitato, RowsCount)
		EXEC dbo.uspMagazziniLotti_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@IdArticolo = @IdArticolo,
			@Aperto = @Aperto,
			@Disabilitato = @Disabilitato,
			@Search = @Search;

		-- Stesso ordine dell'elenco
		SELECT
			[Nome] = c.Nome,
			[Articolo] = c.ArticoloNome,
			[Codice articolo] = art.Codice,
			[Data apertura] = c.DataApertura,
			[Data chiusura] = c.DataChiusura,
			[Quantità max] = c.QuantitaMax,
			[Giacenza] = c.Disponibilita,
			[Unità di misura] = u.Nome,
			[Disabilitato] = IIF(c.Disabilitato = 1, 'Sì', 'No')
		FROM
			#righe c
			LEFT JOIN dbo.tblMagazziniLotti l ON c.Id = l.Id
			LEFT JOIN dbo.tblMagazziniArticoli art ON l.IdArticolo = art.Id
			LEFT JOIN dbo.tblUnitaMisura u ON art.IdUnitaMisura = u.Id
		ORDER BY c.Nome;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO

PRINT 'uspMagazziniGiacenze_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Giacenze di magazzino (viste per articolo e per lotto): righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspMagazziniGiacenze_get_List (che controlla anche permesso e sede del contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspMagazziniGiacenze_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);
		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');
		DECLARE @righe INT = @MaxRighe + 1;

		CREATE TABLE #righe (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			StatoValore INT NULL,
			StatoDescrizione VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			Nome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			ArticoloNome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			UnitaMisuraNome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			IsNumero BIT NULL,
			QuantitaMax DECIMAL(18, 2) NULL,
			Quantita DECIMAL(38, 2) NULL,
			GiacenzaGiorni INT NULL,
			CapacitaResidua DECIMAL(38, 2) NULL,
			CarichiNumero INT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, StatoValore, StatoDescrizione, Nome, ArticoloNome, UnitaMisuraNome, IsNumero, QuantitaMax, Quantita, GiacenzaGiorni, CapacitaResidua, CarichiNumero, RowsCount)
		EXEC dbo.uspMagazziniGiacenze_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@Vista = @Vista,
			@Search = @Search;

		-- Stesso ordine dell'elenco
		IF @Vista = 'A'
			SELECT
				[Articolo] = c.Nome,
				[Codice] = art.Codice,
				[Giacenza] = c.Quantita,
				[Unità di misura] = c.UnitaMisuraNome,
				[Giorni in giacenza] = c.GiacenzaGiorni,
				[Carichi] = c.CarichiNumero
			FROM
				#righe c
				LEFT JOIN dbo.tblMagazziniArticoli art ON c.Id = art.Id
			ORDER BY c.Nome;
		ELSE
			SELECT
				[Lotto] = c.Nome,
				[Articolo] = c.ArticoloNome,
				[Giacenza] = c.Quantita,
				[Unità di misura] = c.UnitaMisuraNome,
				[Giorni in giacenza] = c.GiacenzaGiorni,
				[Carichi] = c.CarichiNumero,
				[Quantità max] = c.QuantitaMax,
				[Capacità residua] = c.CapacitaResidua
			FROM #righe c
			ORDER BY c.Nome;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO

PRINT 'uspMagazziniGiacenze_get_Carichi_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Giacenze di magazzino, carichi in giacenza: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspMagazziniGiacenze_get_Carichi_List (che controlla anche permesso e sede del contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspMagazziniGiacenze_get_Carichi_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Id CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);
		DECLARE @righe INT = @MaxRighe + 1;

		-- Ordine: la posizione della riga nel movimento non è tra le colonne dell'elenco, la conserva
		-- l'ordine di arrivo delle righe
		CREATE TABLE #righe (
			Ordine INT IDENTITY(1, 1) NOT NULL,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdMovimento CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Numero INT NULL,
			[Data] DATE NULL,
			ArticoloNome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			LottoNome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			UnitaMisuraNome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			IsNumero BIT NULL,
			Quantita DECIMAL(18, 2) NULL,
			Scaricata DECIMAL(38, 2) NULL,
			Residuo DECIMAL(38, 2) NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, IdMovimento, Numero, [Data], ArticoloNome, LottoNome, UnitaMisuraNome, IsNumero, Quantita, Scaricata, Residuo, RowsCount)
		EXEC dbo.uspMagazziniGiacenze_get_Carichi_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@Vista = @Vista,
			@Id = @Id,
			@Search = @Search;

		SELECT
			[Numero] = c.Numero,
			[Data] = c.[Data],
			[Articolo] = c.ArticoloNome,
			[Lotto] = c.LottoNome,
			[Q.tà caricata] = c.Quantita,
			[Q.tà scaricata] = c.Scaricata,
			[Q.tà residua] = c.Residuo,
			[Unità di misura] = c.UnitaMisuraNome
		FROM #righe c
		ORDER BY c.[Data] DESC, c.Numero DESC, c.Ordine;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO
