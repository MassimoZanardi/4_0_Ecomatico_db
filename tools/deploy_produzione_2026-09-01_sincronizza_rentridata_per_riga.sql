/*
	Deploy produzione - 2026-09-01 - RentriData per riga nella sincronizzazione

	uspRentriRegistrazioni_upd_Sincronizza: la data di registrazione su RENTRI (RentriData)
	non e' piu' un unico parametro condiviso per l'intero blocco sincronizzato, ma viene
	letta per ogni singola riga del JSON (@Registrazioni). Necessario perche' la
	sincronizzazione puo' recuperare invii confermati da RENTRI in momenti diversi tra loro,
	non un unico invio recente - la data reale di ciascuna registrazione puo' quindi
	differire da riga a riga all'interno dello stesso blocco.

	Questo script NON tocca la tabella e non modifica le 2 funzioni schema-bound (gia'
	corrette e invariate dal deploy precedente) - si limita a riscrivere con CREATE OR ALTER
	il corpo della SP con la nuova firma (rimosso il parametro @RentriData, aggiunto il campo
	"rentriData" dentro ogni elemento del JSON @Registrazioni).

	Verificato su dev: firma SP con 3 soli parametri (IdRegistro, IdSessione, Registrazioni),
	test funzionale in transazione con rollback (2 corrispondenze reali con RentriData
	distinte + 1 riga senza corrispondenza correttamente saltata, nessun blocco delle altre).

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-01_sincronizza_rentridata_per_riga.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- dbo.uspRentriRegistrazioni_upd_Sincronizza
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Sincronizza in blocco un elenco di registrazioni con un dato già presente su RENTRI ma non
-- ancora confermato lato app (invio asincrono: RENTRI ha ricevuto/elaborato le registrazioni
-- ma la conferma non è mai arrivata/stata scritta sull'app, es. per un problema di rete o un
-- crash durante l'attesa). Usata da Rifiuti/Registrazioni/Index (checkbox "sincronizza" in
-- modale 2) dopo un confronto con l'elenco reale restituito da RENTRI - non chiamata
-- direttamente dall'utente, nessuna registrazione "nuova" viene mai creata qui, solo
-- aggiornati RentriIdentificativo/RentriData su righe già esistenti e mai confermate prima.
-- RentriSincronizzata = 1 marca esplicitamente che la conferma è arrivata da questa
-- sincronizzazione e non da un invio normale, per tracciabilità.
-- @Registrazioni: JSON array [{numero, anno, identificativo, rentriData}, ...] - rentriData e'
-- la data/ora reale della registrazione su RENTRI (non "adesso"/il momento della
-- sincronizzazione, che potrebbe essere molto successivo al vero invio: la sincronizzazione
-- serve proprio a recuperare un invio confermato da RENTRI molto prima ma mai scritto
-- sull'app), quindi per riga e non condivisa per l'intero blocco. Comportamento best-effort:
-- una riga del JSON senza corrispondenza (già sincronizzata, Lock diverso da 0, ecc.) viene
-- semplicemente saltata, non blocca le altre - il chiamante ha già verificato l'elenco
-- momenti prima, un singolo mancato match non deve interrompere il resto del blocco.
-- Ritorna il conteggio delle righe aggiornate.
-- Rinominata da uspRentriRegistrazioni_upd (2026-09-01) per distinguerla chiaramente da un
-- generico update della registrazione - lega nome SP, checkbox "sincronizza" e campo
-- RentriSincronizzata. Passata da chiamata singola a blocco JSON lo stesso giorno, per
-- evitare N round-trip separati quando ci sono più registrazioni da sincronizzare.
-- exec dbo.uspRentriRegistrazioni_upd_Sincronizza @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @Registrazioni='[{"numero":3,"anno":2026,"identificativo":"...","rentriData":"2026-08-15 10:30:00"}]'
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_upd_Sincronizza]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Registrazioni NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @sincronizzate INT = 0;

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistro IS NULL OR @IdSessione IS NULL OR @Registrazioni IS NULL
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

		DECLARE @Numero INT, @Anno INT, @Identificativo VARCHAR(50), @RentriData DATETIME2(0);

		DECLARE c CURSOR LOCAL FAST_FORWARD FOR
		SELECT Numero, Anno, Identificativo, RentriData
		FROM OPENJSON(@Registrazioni) WITH (
			Numero INT '$.numero',
			Anno INT '$.anno',
			Identificativo VARCHAR(50) '$.identificativo',
			RentriData DATETIME2(0) '$.rentriData'
		);

		OPEN c;
		FETCH c INTO @Numero, @Anno, @Identificativo, @RentriData;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF @Identificativo IS NOT NULL AND @RentriData IS NOT NULL
			BEGIN
				UPDATE r
				SET
					RentriIdentificativo = @Identificativo,
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

				SET @sincronizzate = @sincronizzate + @@ROWCOUNT;
			END

			FETCH c INTO @Numero, @Anno, @Identificativo, @RentriData;
		END

		CLOSE c;
		DEALLOCATE c;

	END TRY
	BEGIN CATCH
		IF CURSOR_STATUS('local', 'c') >= -1
		BEGIN
			CLOSE c;
			DEALLOCATE c;
		END;
		THROW;
	END CATCH

	BRANCH_END:

	SET NOCOUNT, XACT_ABORT OFF;

	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

	SELECT Sincronizzate = @sincronizzate;

END
GO
