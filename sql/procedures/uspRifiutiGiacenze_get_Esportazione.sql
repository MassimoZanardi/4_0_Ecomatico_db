SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Giacenze dei rifiuti (viste per EER, per materiale e per etichette): righe per l'esportazione dell'elenco in
-- Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV). Il nome di ogni colonna è l'intestazione che
-- finisce nel file: l'applicazione (ExcelService, CsvService) scrive le colonne così come arrivano, nello
-- stesso ordine. Per cambiare che cosa si esporta si modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo della giacenza NON è ricopiato. La SP chiama
-- uspRifiutiGiacenze_get_List (che controlla anche permesso e titolarità del registro) e ne rinomina le
-- colonne: se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiGiacenze_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Data DATE = NULL,
	@Vista CHAR(1) = 'E',
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
			TipoCodice CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			Tipo VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			Id VARCHAR(6) COLLATE DATABASE_DEFAULT NULL,
			Nome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			Descrizione VARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
			IdStatoFisico CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			StatoFisico VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			Etichette VARCHAR(2000) COLLATE DATABASE_DEFAULT NULL,
			Quantita DECIMAL(38, 2) NULL,
			GiacenzaGiorni INT NULL,
			MovimentiNumero INT NULL,
			StatoValore INT NULL,
			StatoDescrizione VARCHAR(100) COLLATE DATABASE_DEFAULT NULL
		);

		INSERT INTO #righe (TipoCodice, Tipo, Id, Nome, Descrizione, IdStatoFisico, StatoFisico, Etichette, Quantita, GiacenzaGiorni, MovimentiNumero, StatoValore, StatoDescrizione)
		EXEC dbo.uspRifiutiGiacenze_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@IdRegistro = @IdRegistro,
			@Data = @Data,
			@Vista = @Vista,
			@Search = @Search;

		-- Stesso ordine dell'elenco
		IF @Vista = 'M'
			SELECT
				[Materiale] = Nome,
				[Quantità] = Quantita,
				[Giorni in giacenza] = GiacenzaGiorni,
				[Movimenti] = MovimentiNumero
			FROM #righe
			ORDER BY GiacenzaGiorni DESC, Nome, StatoFisico, Tipo, Etichette;
		ELSE IF @Vista = 'T'
			SELECT
				[Tipo] = Tipo,
				[Etichette] = (SELECT STRING_AGG(j.Nome, ', ') FROM OPENJSON(Etichette) WITH (Nome VARCHAR(50) '$.Nome') j),
				[Quantità] = Quantita,
				[Giorni in giacenza] = GiacenzaGiorni,
				[Movimenti] = MovimentiNumero
			FROM #righe
			ORDER BY GiacenzaGiorni DESC, Nome, StatoFisico, Tipo, Etichette;
		ELSE
			SELECT
				[Tipo] = Tipo,
				[Codice EER] = Nome,
				[Descrizione] = Descrizione,
				[Stato fisico] = StatoFisico,
				[Quantità] = Quantita,
				[Giorni in giacenza] = GiacenzaGiorni,
				[Movimenti] = MovimentiNumero
			FROM #righe
			ORDER BY GiacenzaGiorni DESC, Nome, StatoFisico, Tipo, Etichette;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO
