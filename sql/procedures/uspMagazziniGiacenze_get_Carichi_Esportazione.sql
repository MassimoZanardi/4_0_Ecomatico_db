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
