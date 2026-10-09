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
