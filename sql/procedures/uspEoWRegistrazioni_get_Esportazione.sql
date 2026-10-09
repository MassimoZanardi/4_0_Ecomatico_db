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
