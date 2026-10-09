SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Servizi assegnati: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspServiziAssegnati_get_List (che controlla anche permesso e contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspServiziAssegnati_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@IdIntervallo CHAR(2) = NULL,
	@DallaData SMALLDATETIME = NULL,
	@Stato CHAR(1) = 'T',
	@Search VARCHAR(50) = NULL,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);
		DECLARE @righe INT = @MaxRighe + 1;

		-- Ordine: a parità di data vale l'ordine di arrivo delle righe
		CREATE TABLE #righe (
			Ordine INT IDENTITY(1, 1) NOT NULL,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdEvento CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			[Data] SMALLDATETIME NULL,
			StatoValore INT NULL,
			StatoDescrizione VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			Tipo VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			Descrizione VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
			Richiedente VARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
			Etichette VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, IdEvento, [Data], StatoValore, StatoDescrizione, Tipo, Descrizione, Richiedente, Etichette, RowsCount)
		EXEC dbo.uspServiziAssegnati_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@IdIntervallo = @IdIntervallo,
			@DallaData = @DallaData,
			@Stato = @Stato,
			@Search = @Search;

		SELECT
			[Data] = [Data],
			[Servizio] = Tipo,
			[Richiedente] = Richiedente,
			[Descrizione] = Descrizione,
			[Stato] = StatoDescrizione,
			[Etichette] =(SELECT STRING_AGG(j.Nome, ', ') FROM OPENJSON(IIF(ISJSON(Etichette) = 1, Etichette, NULL)) WITH (Nome VARCHAR(50) '$.Nome') j)
		FROM #righe
		ORDER BY [Data], Ordine;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO
