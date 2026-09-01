SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Sincronizza una singola registrazione con un dato già presente su RENTRI ma non ancora
-- confermato lato app (invio asincrono: RENTRI ha ricevuto/elaborato la registrazione ma la
-- conferma non è mai arrivata/stata scritta sull'app, es. per un problema di rete o un crash
-- durante l'attesa). Usata da Rifiuti/Registrazioni/Index (checkbox "sincronizza" in modale 2)
-- dopo un confronto con l'elenco reale restituito da RENTRI - non chiamata direttamente
-- dall'utente, nessuna registrazione "nuova" viene mai creata qui, solo aggiornati
-- RentriIdentificativo/RentriData su una riga già esistente e mai confermata prima.
-- RentriSincronizzata = 1 marca esplicitamente che la conferma è arrivata da questa
-- sincronizzazione e non da un invio normale, per tracciabilità.
-- Rinominata da uspRentriRegistrazioni_upd (2026-09-01) per distinguerla chiaramente da un
-- generico update della registrazione - lega nome SP, checkbox "sincronizza" e campo
-- RentriSincronizzata.
-- exec dbo.uspRentriRegistrazioni_upd_Sincronizza @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @Numero=3, @Anno=2026, @RentriIdentificativo='...', @RentriData='2026-08-15 10:30:00'
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_upd_Sincronizza]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Numero INT = NULL,
	@Anno INT = NULL,
	@RentriIdentificativo VARCHAR(50) = NULL,
	@RentriData DATETIME2(0) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @RentriIdentificativo = NULLIF(LTRIM(RTRIM(@RentriIdentificativo)), '');

		IF @IdRegistro IS NULL OR @IdSessione IS NULL OR @Numero IS NULL OR @Anno IS NULL OR @RentriIdentificativo IS NULL OR @RentriData IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Parametri mancanti';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;

		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		UPDATE r
		SET
			RentriIdentificativo = @RentriIdentificativo,
			RentriData = @RentriData,
			RentriSincronizzata = 1
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
		WHERE
			m.IdRegistro = @IdRegistro
			AND r.Numero = @Numero
			AND YEAR(r.[Data]) = @Anno
			AND r.Lock = 0
			AND r.RentriIdentificativo IS NULL
			AND r.RentriData IS NULL;

		IF @@ROWCOUNT = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Registrazione N. ' + CAST(@Numero AS VARCHAR(20)) + '/' + CAST(@Anno AS VARCHAR(4)) + ' non trovata o già sincronizzata';
			GOTO BRANCH_END;
		END

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:

	SET NOCOUNT, XACT_ABORT OFF;

	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

	SELECT ReturnValue = @returnValue;

END
GO
