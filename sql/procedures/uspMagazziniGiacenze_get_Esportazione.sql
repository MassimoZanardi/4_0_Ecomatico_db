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
