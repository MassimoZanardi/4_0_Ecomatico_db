/*
Deploy produzione 2026-10-09 - Esportazione in Excel e CSV degli elenchi del modulo EoW

Indipendente dagli altri script del 2026-10-09: usa solo tabelle e SP già in produzione. Rieseguibile.
Eseguire con sqlcmd -f 65001 -I.

SP di esportazione, una per elenco: stesse righe e stesso ordine della SP dell'elenco, colonne con il nome
dell'intestazione, al massimo @MaxRighe + 1 righe.
1. uspEoWMagazzini_get_Esportazione: magazzini.
2. uspEoWAllocazioni_get_Esportazione: allocazioni.
3. uspEoWLotti_get_Esportazione: lotti (chiama uspEoWLotti_get_List).
4. uspEoWRegistrazioni_get_Esportazione: registrazioni e loro allocazione ai lotti (chiama
   uspEoWRegistrazioni_get_List).
5. uspEoWGiacenze_get_Esportazione: giacenze per lotto e per magazzino (chiama uspEoWGiacenze_get_List).
6. uspEoWGiacenze_get_Carichi_Esportazione: carichi in giacenza (chiama uspEoWGiacenze_get_Carichi_List).

Nessuna modifica alle tabelle né alle SP degli elenchi. Va deployato insieme all'app.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/


PRINT 'uspEoWMagazzini_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Magazzini EoW: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspEoWMagazzini_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspEoWMagazzini_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@Disabilitato BIT = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
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
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: sedi interne visibili alla sessione
		SELECT TOP (@MaxRighe + 1)
			[Nome] = g.Nome,
			[Sede] = s.Nome,
			[Disabilitato] = IIF(g.Disabilitato = 1, 'Sì', 'No')
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

PRINT 'uspEoWAllocazioni_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Allocazioni EoW: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: permesso, scope e criteri di ricerca sono ricopiati da
-- uspEoWAllocazioni_get_List e vanno tenuti allineati a quella. Tutte le righe, senza paginazione: al massimo
-- @MaxRighe + 1 (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspEoWAllocazioni_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdMateriale = NULLIF(LTRIM(RTRIM(@IdMateriale)), '');
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
			@IdFunzione = 'EWC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La sede è quella del contesto della sessione (tblSessioni.IdSede); contesto "tutte le sedi" = nessuna riga
		DECLARE @idSede CHAR(16);
		SELECT @idSede = NULLIF(IdSede, REPLICATE('0', 16))
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT TOP (@MaxRighe + 1)
			[Nome] = a.Nome,
			[Tipo] = t.Nome,
			[Materiale] = mat.MaterialeNome,
			[Lotti] = (SELECT STRING_AGG(l.Nome, ', ') WITHIN GROUP (ORDER BY l.Nome) FROM dbo.tblEoWLottiAllocazioni la INNER JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id WHERE la.IdAllocazione = a.Id)
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

PRINT 'uspEoWLotti_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Lotti EoW: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspEoWLotti_get_List (che controlla anche permesso e sede del contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspEoWLotti_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdMagazzino CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@Aperto BIT = NULL,
	@Disabilitato BIT = NULL,
	@DataAperturaDa DATE = NULL,
	@DataAperturaA DATE = NULL,
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
			StatoDescrizione NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
			NumeroRegistrazioni INT NULL,
			Nome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			MaterialeNome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			MagazzinoNome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			DataApertura DATE NULL,
			DataChiusura DATE NULL,
			QuantitaMax DECIMAL(18, 2) NULL,
			QuantitaAllocata DECIMAL(38, 2) NULL,
			CapacitaResidua DECIMAL(38, 2) NULL,
			Disabilitato BIT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, StatoValore, StatoDescrizione, NumeroRegistrazioni, Nome, MaterialeNome, MagazzinoNome, DataApertura, DataChiusura, QuantitaMax, QuantitaAllocata, CapacitaResidua, Disabilitato, RowsCount)
		EXEC dbo.uspEoWLotti_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@IdMagazzino = @IdMagazzino,
			@IdMateriale = @IdMateriale,
			@Aperto = @Aperto,
			@Disabilitato = @Disabilitato,
			@DataAperturaDa = @DataAperturaDa,
			@DataAperturaA = @DataAperturaA,
			@Search = @Search;

		-- Stesso ordine dell'elenco
		SELECT
			[Nome] = Nome,
			[Materiale] = MaterialeNome,
			[Magazzino] = MagazzinoNome,
			[Data apertura] = DataApertura,
			[Data chiusura] = DataChiusura,
			[Q.tà max] = QuantitaMax,
			[Allocata] = QuantitaAllocata,
			[Registrazioni] = NumeroRegistrazioni,
			[Disponibilità] = CapacitaResidua,
			[Disabilitato] = IIF(Disabilitato = 1, 'Sì', 'No'),
			[Stato] = StatoDescrizione
		FROM #righe
		ORDER BY Nome;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO

PRINT 'uspEoWRegistrazioni_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Registrazioni EoW (registrazioni dei materiali e loro allocazione ai lotti): righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspEoWRegistrazioni_get_List (che controlla anche permesso e sede del contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspEoWRegistrazioni_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdLotto CHAR(16) = NULL,
	@IdMateriale CHAR(2) = NULL,
	@DallaData DATE = NULL,
	@AllaData DATE = NULL,
	@Allocazione CHAR(1) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);
		DECLARE @righe INT = @MaxRighe + 1;

		-- Ordine: la posizione della quota nel lotto non è tra le colonne dell'elenco, la conserva
		-- l'ordine di arrivo delle righe
		CREATE TABLE #righe (
			Ordine INT IDENTITY(1, 1) NOT NULL,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			StatoValore INT NULL,
			StatoDescrizione NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
			RegistroNome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			Numero INT NULL,
			[Data] DATE NULL,
			MaterialeNome VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			IdLotto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			LottoNome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			QuantitaAllocata DECIMAL(38, 2) NULL,
			QuantitaDaAllocare DECIMAL(38, 2) NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, StatoValore, StatoDescrizione, RegistroNome, Numero, [Data], MaterialeNome, IdLotto, LottoNome, QuantitaAllocata, QuantitaDaAllocare, RowsCount)
		EXEC dbo.uspEoWRegistrazioni_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@IdLotto = @IdLotto,
			@IdMateriale = @IdMateriale,
			@DallaData = @DallaData,
			@AllaData = @AllaData,
			@Allocazione = @Allocazione;

		SELECT
			[Registro] = RegistroNome,
			[Nr.] = Numero,
			[Data] = [Data],
			[Materiale] = MaterialeNome,
			[Q.tà allocata] = QuantitaAllocata,
			[Lotto] = LottoNome,
			[Q.tà da allocare] = QuantitaDaAllocare,
			[Stato] = StatoDescrizione
		FROM #righe
		ORDER BY [Data] DESC, Numero DESC, Ordine;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO

PRINT 'uspEoWGiacenze_get_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Giacenze EoW (viste per lotto e per magazzino): righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspEoWGiacenze_get_List (che controlla anche permesso e sede del contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspEoWGiacenze_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Vista CHAR(1) = NULL,
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);
		DECLARE @righe INT = @MaxRighe + 1;

		SET @Vista = NULLIF(LTRIM(RTRIM(@Vista)), '');

		CREATE TABLE #righe (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			StatoValore INT NULL,
			StatoDescrizione NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
			Nome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			MaterialeNome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			QuantitaMax DECIMAL(18, 2) NULL,
			QuantitaAllocata DECIMAL(38, 2) NULL,
			Quantita DECIMAL(38, 2) NULL,
			GiacenzaGiorni INT NULL,
			CapacitaResidua DECIMAL(38, 2) NULL,
			CarichiNumero INT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, StatoValore, StatoDescrizione, Nome, MaterialeNome, QuantitaMax, QuantitaAllocata, Quantita, GiacenzaGiorni, CapacitaResidua, CarichiNumero, RowsCount)
		EXEC dbo.uspEoWGiacenze_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@Vista = @Vista,
			@Search = @Search;

		-- Stesso ordine dell'elenco
		IF @Vista = 'M'
			SELECT
				[Magazzino] = Nome,
				[Quantità] = Quantita,
				[Giorni in giacenza] = GiacenzaGiorni,
				[Carichi] = CarichiNumero,
				[Stato] = StatoDescrizione
			FROM #righe
			ORDER BY Nome;
		ELSE
			SELECT
				[Lotto] = Nome,
				[Materiale] = MaterialeNome,
				[Quantità] = Quantita,
				[Giorni in giacenza] = GiacenzaGiorni,
				[Carichi] = CarichiNumero,
				[Quantità max] = QuantitaMax,
				[Allocata] = QuantitaAllocata,
				[Disponibilità] = CapacitaResidua,
				[Stato] = StatoDescrizione
			FROM #righe
			ORDER BY Nome;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO

PRINT 'uspEoWGiacenze_get_Carichi_Esportazione';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Giacenze EoW, carichi in giacenza: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspEoWGiacenze_get_Carichi_List (che controlla anche permesso e sede del contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspEoWGiacenze_get_Carichi_Esportazione
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

		-- Ordine: a parità di data e numero vale l'ordine di arrivo delle righe
		CREATE TABLE #righe (
			Ordine INT IDENTITY(1, 1) NOT NULL,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			RegistroNome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			Numero INT NULL,
			[Data] DATE NULL,
			MaterialeNome VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			LottoNome VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			QuantitaComplessiva DECIMAL(38, 2) NULL,
			QuantitaAllocata DECIMAL(38, 2) NULL,
			ResiduoLotto DECIMAL(38, 2) NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, RegistroNome, Numero, [Data], MaterialeNome, LottoNome, QuantitaComplessiva, QuantitaAllocata, ResiduoLotto, RowsCount)
		EXEC dbo.uspEoWGiacenze_get_Carichi_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@Vista = @Vista,
			@Id = @Id,
			@Search = @Search;

		SELECT
			[Registro] = RegistroNome,
			[Numero] = Numero,
			[Data] = [Data],
			[Materiale] = MaterialeNome,
			[Lotto] = LottoNome,
			[Quantità complessiva] = QuantitaComplessiva,
			[Quantità allocata] = QuantitaAllocata,
			[Giacenza lotto] = ResiduoLotto
		FROM #righe
		ORDER BY [Data] DESC, Numero DESC, Ordine;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO
