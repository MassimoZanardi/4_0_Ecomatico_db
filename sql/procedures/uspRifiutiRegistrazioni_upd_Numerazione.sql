SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rinumera le registrazioni del registro del contesto (tblSessioni.IdRegistro) con data nell'anno @Anno e
-- numero tra @DalNumero e @AlNumero: ricevono numeri consecutivi a partire da @PrimoNumero, nell'ordine di
-- data e numero attuali. Un intervallo che contiene registrazioni già inviate al RENTRI non si rinumera, e i
-- nuovi numeri non possono sovrapporsi né essere incoerenti con le date delle registrazioni fuori dall'intervallo.
-- Restituisce il numero di registrazioni rinumerate.
CREATE OR ALTER PROCEDURE dbo.uspRifiutiRegistrazioni_upd_Numerazione
	@IdSessione CHAR(16) = NULL,
	@DalNumero INT = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL,
	@PrimoNumero INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DalNumero IS NULL OR @AlNumero IS NULL OR @Anno IS NULL OR @PrimoNumero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare l''intervallo dei numeri, l''anno e il primo numero';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: registro corrente della sessione. Un anno fuori dall'intervallo delle date non ha registrazioni
		DECLARE @idRegistro CHAR(16) = (SELECT IdRegistro FROM dbo.tblSessioni WHERE Id = @IdSessione);

		IF @idRegistro IS NULL OR @Anno < 1900 OR @Anno > 2100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non ci sono registrazioni nell''intervallo indicato';
			GOTO BRANCH_END;
		END

		DECLARE @annoInizio DATE = DATEFROMPARTS(@Anno, 1, 1);
		DECLARE @annoFine DATE = DATEFROMPARTS(@Anno + 1, 1, 1);
		DECLARE @totaleDaRinumerare INT;

		BEGIN TRANSACTION;

			-- Numerazione: il registro viene bloccato per tutta la transazione (UPDLOCK/HOLDLOCK sulla sua sola
			-- riga), come in uspRifiutiRegistrazioni_upd: un salvataggio contemporaneo sullo stesso registro
			-- attende la fine della rinumerazione e non può prendere un numero dell'intervallo in corso di modifica
			DECLARE @registroBloccato CHAR(16) = (
				SELECT Id
				FROM dbo.tblRifiutiRegistri WITH (UPDLOCK, HOLDLOCK)
				WHERE Id = @idRegistro);

			SELECT @totaleDaRinumerare = COUNT(*)
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			WHERE
				m.IdRegistro = @idRegistro
				AND r.Lock < 2
				AND r.[Data] >= @annoInizio
				AND r.[Data] < @annoFine
				AND r.Numero BETWEEN @DalNumero AND @AlNumero;

			-- Se non c'è nulla da rinumerare
			IF @totaleDaRinumerare = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Non ci sono registrazioni nell''intervallo indicato';
				GOTO BRANCH_END;
			END

			-- Se l'intervallo contiene registrazioni già inviate a RENTRI: il Numero/Anno trasmesso
			-- non può più essere modificato, pena il disallineamento con quanto RENTRI ha registrato
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					m.IdRegistro = @idRegistro
					AND r.Lock < 2
					AND r.[Data] >= @annoInizio
					AND r.[Data] < @annoFine
					AND r.Numero BETWEEN @DalNumero AND @AlNumero
					AND (r.RentriIdentificativo IS NOT NULL OR r.RentriData IS NOT NULL)
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'L''intervallo contiene registrazioni già inviate al RENTRI: non possono essere rinumerate';
				GOTO BRANCH_END;
			END

			-- Ultimo numero assegnato dalla rinumerazione
			DECLARE @ultimoNumero INT = @PrimoNumero + @totaleDaRinumerare - 1;

			-- Se la numerazione finale supera 999.999
			IF @ultimoNumero > 999999
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La rinumerazione non può assegnare numeri maggiori di 999.999';
				GOTO BRANCH_END;
			END

			-- Se la nuova rinumerazione entra in conflitto con altre registrazioni al di fuori del gruppo che sarà rinumerato
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRifiutiRegistrazioni r
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					m.IdRegistro = @idRegistro
					AND r.Lock < 2
					AND r.[Data] >= @annoInizio
					AND r.[Data] < @annoFine
					AND r.Numero NOT BETWEEN @DalNumero AND @AlNumero
					AND r.Numero BETWEEN @PrimoNumero AND @ultimoNumero
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La nuova numerazione è in conflitto con quella di altre registrazioni';
				GOTO BRANCH_END;
			END

			-- Nuovi numeri, nell'ordine di data e numero attuali
			DECLARE @nuovi TABLE (
				Id CHAR(16) PRIMARY KEY,
				[Data] DATE,
				NumeroNuovo INT);

			INSERT @nuovi (Id, [Data], NumeroNuovo)
			SELECT
				r.Id,
				r.[Data],
				ROW_NUMBER() OVER (ORDER BY r.[Data], r.Numero) + @PrimoNumero - 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			WHERE
				m.IdRegistro = @idRegistro
				AND r.Lock < 2
				AND r.[Data] >= @annoInizio
				AND r.[Data] < @annoFine
				AND r.Numero BETWEEN @DalNumero AND @AlNumero;

			-- I nuovi numeri devono restare coerenti con le date delle registrazioni fuori dall'intervallo (come in
			-- uspRifiutiRegistrazioni_upd): nessuna con numero minore e data successiva, o numero maggiore e data precedente
			IF EXISTS (
				SELECT 1
				FROM
					@nuovi n
					INNER JOIN dbo.tblRifiutiRegistrazioni r ON
						(
						r.Numero < n.NumeroNuovo
						AND r.[Data] > n.[Data]
						)
						OR
						(
						r.Numero > n.NumeroNuovo
						AND r.[Data] < n.[Data]
						)
					INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				WHERE
					m.IdRegistro = @idRegistro
					AND r.Lock < 2
					AND r.[Data] >= @annoInizio
					AND r.[Data] < @annoFine
					AND r.Numero NOT BETWEEN @DalNumero AND @AlNumero
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La nuova numerazione non è coerente con le date di altre registrazioni del registro';
				GOTO BRANCH_END;
			END

			UPDATE r
			SET Numero = n.NumeroNuovo
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN @nuovi n ON r.Id = n.Id;

			SET @returnValue = @@ROWCOUNT;

		COMMIT TRANSACTION;

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
END;
GO
