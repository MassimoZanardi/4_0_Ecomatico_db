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
