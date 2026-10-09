SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Registri RENTRI: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in CSV).
-- Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService, CsvService)
-- scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si modifica solo
-- questa SP.
-- Stesse righe e stesso ordine dell'elenco: qui il calcolo NON è ricopiato. La SP chiama
-- uspRentriRegistri_get_List (che controlla anche permesso e contesto) e ne rinomina le colonne:
-- se a quella SP si aggiunge o si toglie una colonna, va aggiornata la tabella #righe qui sotto.
-- Al massimo @MaxRighe + 1 righe (la riga in più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspRentriRegistri_get_Esportazione
	@IdSessione CHAR(16) = NULL,
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
			SedeNome VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			IndirizzoCompleto VARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
			Identificativo VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			BloccoFormulari VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			CredenzialePrimariaNome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			AccreditamentoNome VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			IsCollegato BIT NULL,
			RowsCount INT NULL
		);

		INSERT INTO #righe (Id, StatoValore, StatoDescrizione, Nome, SedeNome, IndirizzoCompleto, Identificativo, BloccoFormulari, CredenzialePrimariaNome, AccreditamentoNome, IsCollegato, RowsCount)
		EXEC dbo.uspRentriRegistri_get_List
			@PageNumber = 1,
			@RowsPerPage = @righe,
			@IdSessione = @IdSessione,
			@Search = @Search;

		-- Stesso ordine dell'elenco
		SELECT
			[Registro] = Nome,
			[Sede] = SedeNome,
			[Indirizzo] = IndirizzoCompleto,
			[Identificativo] = Identificativo,
			[Blocco formulari] = BloccoFormulari,
			[Credenziale primaria] = CredenzialePrimariaNome,
			[Accreditamento] = AccreditamentoNome,
			[Collegato a RENTRI] = IIF(IsCollegato = 1, 'Sì', 'No'),
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
