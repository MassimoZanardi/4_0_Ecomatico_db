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
