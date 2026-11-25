SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Modulo Email (EML): un lotto del giro dell'invio (operazione pianificata ogni 5 minuti, POST /api/email/elabora: il
-- giro prende lotti finche' la coda e' vuota o finisce il suo tempo). Prende fino a @Max email da inviare (stato D,
-- ProssimoTentativo passato), le segna in invio (P) e le restituisce; l'app le invia e scrive l'esito con
-- uspEmail_upd_Esito (anche per quelle che rimette in coda senza inviarle, @Rilascia = 1). Il blocco sp_getapplock fa
-- prendere un lotto alla volta: due chiamate sovrapposte non prendono mai la stessa email e non superano la quota.
-- Ordine: prima le email di servizio, poi gli avvisi agli utenti, poi le comunicazioni ai clienti, dalla piu' vecchia.
-- Avvisi e comunicazioni (Tipo U e C):
-- - senza il modulo Email sul dominio, o con il massimo del giorno o del mese vuoto o 0, non partono (stato E);
-- - con il massimo del mese raggiunto aspettano il primo del mese dopo, con quello del giorno il giorno dopo (restano
--   D con la Nota che lo spiega); le email non usate non passano al mese dopo;
-- - prese, contano nella quota del giorno (tblEmailConsumi, QuotaGiorno): se poi non partono il posto torna libero.
-- Le email di servizio (Tipo S: email di prova, avvisi sulla quota) non contano e non chiedono il modulo.
-- @GiornoMaxGlobale (EmailSettings:GiornoMax nel web.config, NULL o 0 = nessuno): tetto di sicurezza sulle email prese
-- oggi da tutti i domini, anche di servizio; raggiunto, il giro si ferma e le email aspettano.
-- Prima del lotto, le email in invio da oltre 15 minuti (app fermata a meta': un giro dura al massimo 4 minuti)
-- passano a E: non e' noto se siano partite e rimandarle potrebbe farle arrivare due volte.
CREATE OR ALTER PROCEDURE [dbo].[uspEmail_upd_Prendi]
	@Max INT = 50,
	@GiornoMaxGlobale INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		IF @Max IS NULL OR @Max < 1
			SET @Max = 1;
		IF @Max > 200
			SET @Max = 200;

		DECLARE @ora DATETIME2(0) = GETDATE();
		DECLARE @oggi DATE = CAST(@ora AS DATE);
		DECLARE @inizioMese DATE = DATEFROMPARTS(YEAR(@oggi), MONTH(@oggi), 1);
		DECLARE @domani DATETIME2(0) = DATEADD(DAY, 1, CAST(@oggi AS DATETIME2(0)));
		DECLARE @meseDopo DATETIME2(0) = DATEADD(MONTH, 1, CAST(@inizioMese AS DATETIME2(0)));

		DECLARE @prese TABLE (Id CHAR(16) COLLATE Latin1_General_CI_AS PRIMARY KEY, Ordine INT);
		DECLARE @n INT = 0;

		BEGIN TRANSACTION;

			DECLARE @blocco INT;
			EXEC @blocco = sp_getapplock @Resource = 'tblEmail_Prendi', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 30000;

			IF @blocco >= 0
			BEGIN
				UPDATE dbo.tblEmail
				SET
					IdStato = 'E',
					Nota = N'Invio interrotto: non è noto se l''email sia partita, quindi non viene rimandata'
				WHERE
					IdStato = 'P'
					AND Presa < DATEADD(MINUTE, -15, @ora);

				DECLARE @globali INT = (SELECT COUNT(*) FROM dbo.tblEmail WHERE Presa >= @oggi);

				DECLARE @id CHAR(16), @idDominio CHAR(16), @tipo CHAR(1);
				DECLARE @giornoMax INT, @meseMax INT, @giorno INT, @mese INT, @modulo BIT;

				DECLARE coda CURSOR LOCAL FAST_FORWARD FOR
					SELECT TOP (500) Id, IdDominio, Tipo
					FROM dbo.tblEmail
					WHERE
						IdStato = 'D'
						AND ProssimoTentativo <= @ora
					ORDER BY
						CASE Tipo WHEN 'S' THEN 0 WHEN 'U' THEN 1 ELSE 2 END,
						Creazione,
						Id;

				OPEN coda;
				FETCH NEXT FROM coda INTO @id, @idDominio, @tipo;

				WHILE @@FETCH_STATUS = 0 AND @n < @Max
					AND (ISNULL(@GiornoMaxGlobale, 0) <= 0 OR @globali < @GiornoMaxGlobale)
				BEGIN
					IF @tipo = 'S'
					BEGIN
						UPDATE dbo.tblEmail
						SET IdStato = 'P', Presa = @ora, Nota = NULL
						WHERE Id = @id AND IdStato = 'D';

						INSERT INTO @prese (Id, Ordine) VALUES (@id, @n);
						SET @n += 1;
						SET @globali += 1;
					END
					ELSE
					BEGIN
						SET @modulo = IIF(EXISTS (SELECT 1 FROM dbo.tblDominiModuli WHERE Id = @idDominio AND IdModulo = 'EML'), 1, 0);
						SELECT @giornoMax = GiornoMax, @meseMax = MeseMax, @giorno = Giorno, @mese = Mese
						FROM dbo.ufnEmail_get_Consumi(@idDominio);

						IF @modulo = 0
							UPDATE dbo.tblEmail
							SET IdStato = 'E', Nota = N'Il modulo Email non è attivo'
							WHERE Id = @id;
						ELSE IF ISNULL(@giornoMax, 0) <= 0 OR ISNULL(@meseMax, 0) <= 0
							UPDATE dbo.tblEmail
							SET IdStato = 'E', Nota = N'Le email non sono attive: manca il numero massimo del giorno o del mese'
							WHERE Id = @id;
						ELSE IF @mese >= @meseMax
							UPDATE dbo.tblEmail
							SET ProssimoTentativo = @meseDopo, Nota = N'In attesa: raggiunto il numero massimo di email del mese'
							WHERE Id = @id;
						ELSE IF @giorno >= @giornoMax
							UPDATE dbo.tblEmail
							SET ProssimoTentativo = @domani, Nota = N'In attesa: raggiunto il numero massimo di email del giorno'
							WHERE Id = @id;
						ELSE
						BEGIN
							UPDATE dbo.tblEmailConsumi
							SET Numero += 1
							WHERE IdDominio = @idDominio AND Giorno = @oggi;
							IF @@ROWCOUNT = 0
								INSERT INTO dbo.tblEmailConsumi (IdDominio, Giorno, Numero) VALUES (@idDominio, @oggi, 1);

							UPDATE dbo.tblEmail
							SET IdStato = 'P', Presa = @ora, Nota = NULL, QuotaGiorno = @oggi
							WHERE Id = @id AND IdStato = 'D';

							INSERT INTO @prese (Id, Ordine) VALUES (@id, @n);
							SET @n += 1;
							SET @globali += 1;
						END
					END

					FETCH NEXT FROM coda INTO @id, @idDominio, @tipo;
				END

				CLOSE coda;
				DEALLOCATE coda;
			END

		COMMIT TRANSACTION;

		SELECT
			e.Id,
			e.Indirizzo,
			e.Mittente,
			e.RispondiA,
			e.Oggetto,
			e.Contenuto
		FROM
			dbo.tblEmail e
			INNER JOIN @prese p ON e.Id = p.Id
		ORDER BY p.Ordine;

	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION;
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;
END;
GO
