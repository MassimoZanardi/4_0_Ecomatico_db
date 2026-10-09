SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Giacenze dei rifiuti, carichi in giacenza: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni >
-- Esporta in Excel, Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file:
-- l'applicazione (ExcelService, CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per
-- cambiare che cosa si esporta si modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo della giacenza NON è ricopiato. La SP chiama
-- uspRifiutiGiacenze_get_Carichi_List (che controlla anche permesso e titolarità del registro) e ne rinomina
-- le colonne: se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRifiutiGiacenze_get_Carichi_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Data DATE = NULL,
	@Vista CHAR(1) = 'E',
	@Tipo CHAR(1) = NULL,
	@Id CHAR(6) = NULL,
	@IdStatoFisico CHAR(1) = NULL,
	@Etichette VARCHAR(2000) = NULL,
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
			Numero INT NULL,
			[Data] DATE NULL,
			IdEer VARCHAR(6) COLLATE DATABASE_DEFAULT NULL,
			EerNome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			IdStatoFisico CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			StatoFisico VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			Etichette VARCHAR(2000) COLLATE DATABASE_DEFAULT NULL,
			IdUnitaMisura CHAR(2) COLLATE DATABASE_DEFAULT NULL,
			Quantita DECIMAL(38, 2) NULL,
			QuantitaAssegnata DECIMAL(38, 2) NULL,
			QuantitaResidua DECIMAL(38, 2) NULL,
			GiacenzaGiorni INT NULL,
			StatoValore INT NULL,
			StatoDescrizione VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, Numero, [Data], IdEer, EerNome, IdStatoFisico, StatoFisico, Etichette, IdUnitaMisura, Quantita, QuantitaAssegnata, QuantitaResidua, GiacenzaGiorni, StatoValore, StatoDescrizione, RowsCount)
		EXEC dbo.uspRifiutiGiacenze_get_Carichi_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@IdRegistro = @IdRegistro,
			@Data = @Data,
			@Vista = @Vista,
			@Tipo = @Tipo,
			@Id = @Id,
			@IdStatoFisico = @IdStatoFisico,
			@Etichette = @Etichette,
			@Search = @Search;

		-- Stesso ordine dell'elenco
		SELECT
			[Numero] = c.Numero,
			[Data] = c.[Data],
			[Codice] = c.EerNome,
			[Stato fisico] = c.StatoFisico,
			[Etichette] = (SELECT STRING_AGG(j.Nome, ', ') FROM OPENJSON(c.Etichette) WITH (Nome VARCHAR(50) '$.Nome') j),
			[Quantità] = c.Quantita,
			[Assegnata] = c.QuantitaAssegnata,
			[Residua] = c.QuantitaResidua,
			[Unità di misura] = um.Codice,
			[Giorni in giacenza] = c.GiacenzaGiorni
		FROM
			#righe c
			LEFT JOIN dbo.tblUnitaMisura um ON c.IdUnitaMisura = um.Id
		ORDER BY c.GiacenzaGiorni DESC, c.EerNome, c.Numero;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO
