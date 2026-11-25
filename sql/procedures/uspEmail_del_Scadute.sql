SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Modulo Email (EML, docs/regole/email.md E3.8): pulizia del registro, chiamata alla fine di ogni giro dell'invio.
-- Cancella definitivamente le email chiuse (inviate I o non inviate E) da oltre @Giorni giorni (decisione dell'utente
-- del 2026-11-25: il registro serve solo per le verifiche recenti, e le email contengono dati personali). I giorni si
-- contano dall'invio, o dalla creazione per quelle non inviate. Le email ancora da inviare o in invio non si cancellano
-- mai (un'email in attesa del massimo del mese puo' aspettare un mese intero). Al massimo @Max email per volta, cosi'
-- una cancellazione grande non blocca la tabella: il resto lo fanno i giri successivi.
-- Toglie anche i consumi (tblEmailConsumi) di oltre 13 mesi prima: per le quote serve solo il mese in corso.
-- Restituisce il numero di email cancellate.
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_del_Scadute]
	@Giorni INT = 30,
	@Max INT = 500
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		IF @Giorni IS NULL OR @Giorni < 1
			SET @Giorni = 30;
		IF @Max IS NULL OR @Max < 1
			SET @Max = 500;

		DECLARE @limite DATETIME2(0) = DATEADD(DAY, -@Giorni, CAST(GETDATE() AS DATETIME2(0)));
		DECLARE @limiteConsumi DATE = DATEADD(MONTH, -13, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
		DECLARE @cancellate INT;

		-- Creazione < @limite (colonna inclusa in IX_tblEmail_Coda) riduce le righe da leggere a quelle vecchie;
		-- Invio decide per quelle inviate
		DELETE TOP (@Max)
		FROM dbo.tblEmail
		WHERE
			IdStato IN ('I', 'E')
			AND Creazione < @limite
			AND ISNULL(Invio, Creazione) < @limite;

		SET @cancellate = @@ROWCOUNT;

		DELETE FROM dbo.tblEmailConsumi
		WHERE Giorno < @limiteConsumi;

		SELECT @cancellate AS Cancellate;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO
