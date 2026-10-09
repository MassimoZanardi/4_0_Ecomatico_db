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
