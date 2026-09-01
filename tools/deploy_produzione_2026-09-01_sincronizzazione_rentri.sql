/*
	Deploy produzione - 2026-09-01 - Sincronizzazione registrazioni con RENTRI (checkbox in Invio registrazioni)

	Contenuto di questo script (solo 4_0_ecomatico, verificato su dev con dati reali,
	idempotente):

	1) Rinomina uspRifiutiRegistrazioni_get_InvioControllo -> dbo.uspRentriRegistrazioni_get_InvioControllo
	   (coerenza col prefisso Rentri delle altre SP dedicate al RENTRI). Comportamento invariato.

	2) Rinomina uspRifiutiRegistrazioni_get_InvioDefault -> dbo.uspRentriRegistrazioni_get_InvioDefault
	   (stessa coerenza). Comportamento invariato.

	3) dbo.uspRentriRegistrazioni_get_Invio (nuova)
	   - Stessa identica selezione/filtro di uspRentriRegistrazioni_get_InvioControllo (stesso calcolo
	     @DataInizioRegistrazioni, stesso WHERE), ma restituisce le righe (Numero, Anno, Data) invece
	     di validare - usata per confrontare l'elenco locale non ancora inviato con quello reale
	     restituito da RENTRI durante la sincronizzazione.

	4) dbo.uspRentriRegistrazioni_upd (nuova)
	   - Sincronizza una singola registrazione (RentriIdentificativo/RentriData) con un dato già
	     presente su RENTRI ma non ancora confermato lato app (invio asincrono: RENTRI ha
	     ricevuto/elaborato la registrazione ma la conferma non è mai arrivata sull'app). Salvaguardie:
	     Lock=0 AND RentriIdentificativo IS NULL AND RentriData IS NULL.

	Contesto: nuova checkbox 'sincronizza' in Rifiuti/Registrazioni/Index, modale 'Conferma invio' -
	prima dell'invio vero e proprio, l'app confronta l'elenco locale con quello di RENTRI (endpoint hub
	GET /registro/{app}/registrazioni/{id}, già esistente, non toccato) e sincronizza le corrispondenze
	trovate per Numero+Anno, così che l'invio (endpoint hub POST /registro/{app}/registrazioni-lista/{id},
	anch'esso già esistente e non toccato) processi solo il blocco realmente mancante. Nessuna modifica
	all'hub 1_0_RentriApi - tutta l'orchestrazione è lato app (commit app 251cba4).

	Verificato su DB dev: build pulita, header ANSI_NULLS/QUOTED_IDENTIFIER su tutte e 4 le SP, test
	funzionale su dati reali con un collegamento RENTRI fittizio temporaneo (poi ripulito) - get_Invio
	restituisce l'elenco corretto, upd scrive correttamente e blocca un secondo tentativo sulla stessa
	riga (salvaguardia confermata).

	IMPORTANTE: eseguire le DROP dei vecchi nomi DOPO aver verificato che le nuove CREATE siano andate
	a buon fine (già in quest'ordine nello script).

	Eseguire con:
	  sqlcmd -S <server_produzione> -d "4_0_ecomatico" -E -f 65001 -i deploy_produzione_2026-09-01_sincronizzazione_rentri.sql
	(il flag -f 65001 e' obbligatorio per non corrompere gli accenti italiani)
*/

--------------------------------------------------------------------------------
-- 1) dbo.uspRentriRegistrazioni_get_InvioControllo (rinominata da uspRifiutiRegistrazioni_get_InvioControllo)
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Pre-controllo di coerenza prima dell'invio al RENTRI, adattata dalla SP di riferimento
-- 3_1_ecomatico.uspRentriRegistrazioni_get_InvioControllo (fornita dall'utente). Si ferma al
-- primo problema trovato (non un elenco cumulativo). Riusa dbo.viewRentriRegistrazioni: stessa
-- vista consumata dall'hub, quindi valida esattamente ciò che verrà davvero inviato.
-- Rinominata da uspRifiutiRegistrazioni_get_InvioControllo (2026-09-01) per coerenza col
-- prefisso Rentri delle altre SP dedicate al RENTRI (uspRentriSedi_*, uspRentriRegistri_*, ecc.).
-- exec dbo.uspRentriRegistrazioni_get_InvioControllo @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @AllaData='20501231'
-- exec dbo.uspRentriRegistrazioni_get_InvioControllo @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @AlNumero=10, @Anno=2026
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_get_InvioControllo]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@AllaData DATE = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
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

		DECLARE @IsData BIT = CAST(IIF(@AllaData IS NOT NULL, 1, 0) AS BIT);

		IF @IsData = 0 AND (@AlNumero IS NULL OR @Anno IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Specificare una data oppure un numero e un anno';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistri WHERE Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro non è associato al rispettivo sul RENTRI';
			GOTO BRANCH_END;
		END

		DECLARE @DataInizioRegistrazioni DATE;

		IF EXISTS (
			SELECT 1
			FROM dbo.viewRentriRegistrazioni WITH (NOLOCK)
			WHERE IDRegistro = @IdRegistro AND RentriIdentificativo IS NOT NULL AND Lock < 2
		)
			SELECT @DataInizioRegistrazioni = MAX(Data)
			FROM dbo.viewRentriRegistrazioni WITH (NOLOCK)
			WHERE IDRegistro = @IdRegistro AND RentriIdentificativo IS NOT NULL AND Lock < 2;
		ELSE
			SELECT @DataInizioRegistrazioni = z.DataInizioInvio
			FROM
				dbo.tblRentriRegistri                    g
				LEFT JOIN [1_0_rentri]..tblRegistri z ON g.IdRentri = z.Id COLLATE DATABASE_DEFAULT
			WHERE g.Id = @IdRegistro;

		DECLARE
			@Numero INT, @Data DATE, @NumeroBak INT = 0, @DataBak DATE,
			@Operazione VARCHAR(10), @Quantita DECIMAL(18, 3), @Anno_ CHAR(4),
			@IsTrasportatore BIT, @TrasportatoreAutorizzazione VARCHAR(20),
			@IsDestinatario BIT, @DestinatarioAutorizzazione VARCHAR(20),
			@IsIntermediario BIT, @IntermediarioAutorizzazione VARCHAR(20),
			@IsProduttore BIT, @ProduttoreIdComune CHAR(6), @ProduttoreNazione CHAR(2),
			@RecLock TINYINT, @Count INT = 0, @CountMax INT = 100;

		DECLARE c CURSOR LOCAL FAST_FORWARD FOR
		SELECT
			r.Numero, r.Data, r.Operazione, r.Quantita,
			r.IsTrasportatore, r.TrasportatoreAutorizzazione,
			r.IsDestinatario, r.DestinatarioAutorizzazione,
			r.IsIntermediario, r.IntermediarioAutorizzazione,
			r.IsProduttore, r.ProduttoreIdComune, r.ProduttoreNazione,
			r.Lock
		FROM dbo.viewRentriRegistrazioni r WITH (NOLOCK)
		WHERE
			r.IDRegistro = @IdRegistro
			AND r.RentriIdentificativo IS NULL
			AND r.Lock < 2
			AND (@DataInizioRegistrazioni IS NULL OR r.Data >= @DataInizioRegistrazioni)
			AND (
				(@IsData = 1 AND r.Data <= @AllaData)
				OR (@IsData = 0 AND ((r.Anno < @Anno) OR (r.Anno = @Anno AND r.Numero BETWEEN 1 AND @AlNumero)))
			)
		ORDER BY r.Data, r.Numero;

		OPEN c;
		FETCH c INTO @Numero, @Data, @Operazione, @Quantita, @IsTrasportatore, @TrasportatoreAutorizzazione, @IsDestinatario, @DestinatarioAutorizzazione, @IsIntermediario, @IntermediarioAutorizzazione, @IsProduttore, @ProduttoreIdComune, @ProduttoreNazione, @RecLock;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF @Count >= @CountMax
			BEGIN
				SET @returnMessage = 'Il numero massimo di registrazioni inviabile è ' + CAST(@CountMax AS VARCHAR(20));
				BREAK;
			END
			ELSE IF (@IsData = 1 AND YEAR(@Data) <> YEAR(@AllaData)) OR (@IsData = 0 AND YEAR(@Data) <> @Anno)
			BEGIN
				SET @returnMessage = 'Le registrazioni devono appartenere allo stesso anno, registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF @Operazione IS NULL
			BEGIN
				SET @returnMessage = 'Causale non valida, registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF @Quantita < 0
			BEGIN
				SET @returnMessage = 'Q.tà negativa non valida, registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF ISNULL(@RecLock, 0) <> 0
			BEGIN
				SET @returnMessage = 'Registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy') + ' non confermata';
				BREAK;
			END
			ELSE IF (@NumeroBak > 0 AND @Numero - @NumeroBak <> 1)
			BEGIN
				SET @returnMessage = 'Salto di numerazione registrazione N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF (@NumeroBak > 0 AND @Data < @DataBak)
			BEGIN
				SET @returnMessage = 'Data inferiore alla precedente reg. N. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yyyy');
				BREAK;
			END
			ELSE IF (ISNULL(@IsTrasportatore, 0) = 1 AND @TrasportatoreAutorizzazione IS NOT NULL AND @TrasportatoreAutorizzazione NOT LIKE '[A-Z][A-Z]/[0-9][0-9][0-9][0-9][0-9][0-9]')
			BEGIN
				SET @returnMessage = 'Il nr. di autoriz. del trasportatore deve essere indicato nel formato "AA/123456". Reg. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yy');
				BREAK;
			END
			ELSE IF (ISNULL(@IsDestinatario, 0) = 1 AND (@DestinatarioAutorizzazione IS NULL OR LEN(@DestinatarioAutorizzazione) = 0 OR LEN(@DestinatarioAutorizzazione) > 20))
			BEGIN
				SET @returnMessage = 'Nr. errato autoriz. destinatario. Reg. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yy');
				BREAK;
			END
			ELSE IF (ISNULL(@IsIntermediario, 0) = 1 AND @IntermediarioAutorizzazione IS NOT NULL AND @IntermediarioAutorizzazione NOT LIKE '[A-Z][A-Z]/[0-9][0-9][0-9][0-9][0-9][0-9]')
			BEGIN
				SET @returnMessage = 'Il nr. di autoriz. dell''intermediario deve essere indicato nel formato "AA/123456". Reg. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yy');
				BREAK;
			END
			ELSE IF (ISNULL(@IsProduttore, 0) = 1 AND @ProduttoreNazione = 'IT' AND @ProduttoreIdComune IS NULL)
			BEGIN
				SET @returnMessage = 'Comune del Produttore non valido. Aggiornare l''anagrafica. Reg. ' + FORMAT(@Numero, 'N0') + ' del ' + FORMAT(@Data, 'dd/MM/yy');
				BREAK;
			END

			SET @Count = @Count + 1;
			SET @NumeroBak = @Numero;
			SET @DataBak = @Data;

			FETCH c INTO @Numero, @Data, @Operazione, @Quantita, @IsTrasportatore, @TrasportatoreAutorizzazione, @IsDestinatario, @DestinatarioAutorizzazione, @IsIntermediario, @IntermediarioAutorizzazione, @IsProduttore, @ProduttoreIdComune, @ProduttoreNazione, @RecLock;
		END
		CLOSE c;
		DEALLOCATE c;

		IF @returnMessage IS NULL AND @Count = 0
			SET @returnMessage = 'Nessuna registrazione trovata nell''intervallo indicato';

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

	SELECT Count = @Count, Messaggio = @returnMessage;

END
GO

--------------------------------------------------------------------------------
-- 2) dbo.uspRentriRegistrazioni_get_InvioDefault (rinominata da uspRifiutiRegistrazioni_get_InvioDefault)
--------------------------------------------------------------------------------

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Valori di default per la modale "Invio registrazioni" (Rifiuti/Registrazioni/Index): data e
-- numero/anno dell'ultima registrazione non ancora inviata al RENTRI del Registro indicato.
-- Nessuna riga se il Registro non ha ancora registrazioni non inviate (Lock=0, RentriIdentificativo NULL).
-- Rinominata da uspRifiutiRegistrazioni_get_InvioDefault (2026-09-01) per coerenza col prefisso
-- Rentri delle altre SP dedicate al RENTRI (uspRentriSedi_*, uspRentriRegistri_*, ecc.).
-- exec dbo.uspRentriRegistrazioni_get_InvioDefault @IdRegistro='fd73e743a19b44c0', @IdSessione='...'
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_get_InvioDefault]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
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

		-- OUTER APPLY su una riga fittizia: garantisce sempre esattamente 1 riga in output
		-- (con colonne NULL se non ci sono registrazioni non inviate), richiesto da QuerySingleAsync lato C#.
		SELECT
			UltimaData = t.Data,
			UltimoNumero = t.Numero,
			UltimoAnno = t.Anno
		FROM
			(SELECT 1 AS Dummy) d
			OUTER APPLY (
				SELECT TOP 1
					r.Data, r.Numero, r.Anno
				FROM
					dbo.viewRentriRegistrazioni r WITH (NOLOCK)
				WHERE
					r.IDRegistro = @IdRegistro
					AND r.RentriIdentificativo IS NULL
					AND r.Lock = 0
				ORDER BY
					r.Data DESC, r.Numero DESC
			) t;

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

END
GO

--------------------------------------------------------------------------------
-- 3) dbo.uspRentriRegistrazioni_get_Invio (nuova)
--------------------------------------------------------------------------------

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Elenco grezzo (Numero, Anno, Data) delle registrazioni non ancora inviate al RENTRI
-- nell'intervallo scelto - stessa identica selezione/filtro di uspRentriRegistrazioni_get_InvioControllo
-- (stesso calcolo di @DataInizioRegistrazioni, stesso WHERE), ma senza i controlli di business
-- (causale, quantità, autorizzazioni, ecc.): usata per il confronto con l'elenco restituito da
-- RENTRI durante la sincronizzazione (Rifiuti/Registrazioni/Index, checkbox "sincronizza" in
-- modale 2), non per validare cosa può essere inviato.
-- exec dbo.uspRentriRegistrazioni_get_Invio @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @AllaData='20501231'
-- exec dbo.uspRentriRegistrazioni_get_Invio @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @AlNumero=10, @Anno=2026
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_get_Invio]
	@IdRegistro CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@AllaData DATE = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdRegistro non può essere vuoto';
			GOTO BRANCH_END;
		END

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
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

		DECLARE @IsData BIT = CAST(IIF(@AllaData IS NOT NULL, 1, 0) AS BIT);

		IF @IsData = 0 AND (@AlNumero IS NULL OR @Anno IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Specificare una data oppure un numero e un anno';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistri WHERE Id = @IdRegistro)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro non è associato al rispettivo sul RENTRI';
			GOTO BRANCH_END;
		END

		DECLARE @DataInizioRegistrazioni DATE;

		IF EXISTS (
			SELECT 1
			FROM dbo.viewRentriRegistrazioni WITH (NOLOCK)
			WHERE IDRegistro = @IdRegistro AND RentriIdentificativo IS NOT NULL AND Lock < 2
		)
			SELECT @DataInizioRegistrazioni = MAX(Data)
			FROM dbo.viewRentriRegistrazioni WITH (NOLOCK)
			WHERE IDRegistro = @IdRegistro AND RentriIdentificativo IS NOT NULL AND Lock < 2;
		ELSE
			SELECT @DataInizioRegistrazioni = z.DataInizioInvio
			FROM
				dbo.tblRentriRegistri                    g
				LEFT JOIN [1_0_rentri]..tblRegistri z ON g.IdRentri = z.Id COLLATE DATABASE_DEFAULT
			WHERE g.Id = @IdRegistro;

		SELECT
			r.Numero,
			Anno = YEAR(r.Data),
			r.Data
		FROM dbo.viewRentriRegistrazioni r WITH (NOLOCK)
		WHERE
			r.IDRegistro = @IdRegistro
			AND r.RentriIdentificativo IS NULL
			AND r.Lock < 2
			AND (@DataInizioRegistrazioni IS NULL OR r.Data >= @DataInizioRegistrazioni)
			AND (
				(@IsData = 1 AND r.Data <= @AllaData)
				OR (@IsData = 0 AND ((r.Anno < @Anno) OR (r.Anno = @Anno AND r.Numero BETWEEN 1 AND @AlNumero)))
			)
		ORDER BY r.Data, r.Numero;

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

END
GO

--------------------------------------------------------------------------------
-- 4) dbo.uspRentriRegistrazioni_upd (nuova)
--------------------------------------------------------------------------------

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
-- exec dbo.uspRentriRegistrazioni_upd @IdRegistro='fd73e743a19b44c0', @IdSessione='...', @Numero=3, @Anno=2026, @RentriIdentificativo='...', @RentriData='2026-08-15 10:30:00'
CREATE OR ALTER PROCEDURE [dbo].[uspRentriRegistrazioni_upd]
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
			RentriData = @RentriData
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

--------------------------------------------------------------------------------
-- DROP dei vecchi nomi (dopo aver verificato che le CREATE sopra siano andate a buon fine)
--------------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS dbo.uspRifiutiRegistrazioni_get_InvioControllo;
GO
DROP PROCEDURE IF EXISTS dbo.uspRifiutiRegistrazioni_get_InvioDefault;
GO
