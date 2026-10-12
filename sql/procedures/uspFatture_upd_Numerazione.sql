SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture clienti / fornitori > Azioni > Rinumera le fatture. Rinumera le fatture attive dell'azienda interna
-- corrente della sessione, del tipo @Tipo (C clienti, F fornitori), dell'anno @Anno e del sezionale @Sezionale
-- (NULL = senza sezionale), con numero tra @DalNumero e @AlNumero: ricevono numeri consecutivi a partire da
-- @PrimoNumero, nell'ordine di data e numero attuali. Stesso schema di uspRifiutiRegistrazioni_upd_Numerazione.
-- La numerazione è quella della fattura (fatturazione.md, F3): per anno e sezionale; l'anno è quello della data
-- di emissione per le fatture cliente e della data di registrazione per le fatture fornitore (protocollo
-- interno). Le pre-fatture non hanno numero e non entrano; le bozze e le fatture cancellate nemmeno.
-- Fatture in sola lettura: con @AncheSolaLettura = 0 un intervallo che ne contiene almeno una non si rinumera;
-- con @AncheSolaLettura = 1 vengono rinumerate anche quelle, e restano in sola lettura.
-- Controlli e aggiornamento in un'unica transazione, con la stessa lettura con blocco di uspFatture_upd: un
-- salvataggio contemporaneo attende la fine della rinumerazione. Restituisce il numero di fatture rinumerate.
CREATE OR ALTER PROCEDURE dbo.uspFatture_upd_Numerazione
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@DalNumero INT = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL,
	@Sezionale VARCHAR(5) = NULL,
	@PrimoNumero INT = NULL,
	@AncheSolaLettura BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = NULLIF(UPPER(LTRIM(RTRIM(@Tipo))), '');
		SET @Sezionale = NULLIF(UPPER(LTRIM(RTRIM(@Sezionale))), '');
		SET @AncheSolaLettura = ISNULL(@AncheSolaLettura, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'F')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (cliente) o F (fornitore)';
			GOTO BRANCH_END;
		END
		IF @DalNumero IS NULL OR @AlNumero IS NULL OR @Anno IS NULL OR @PrimoNumero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare l''intervallo dei numeri, l''anno e il primo numero';
			GOTO BRANCH_END;
		END
		IF @DalNumero < 1 OR @AlNumero < @DalNumero
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''intervallo dei numeri non è valido';
			GOTO BRANCH_END;
		END
		IF @PrimoNumero < 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il nuovo numero deve essere maggiore di zero';
			GOTO BRANCH_END;
		END
		IF @Anno < 1900 OR @Anno > 2999
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''anno indicato non è valido';
			GOTO BRANCH_END;
		END
		IF @Sezionale IS NOT NULL AND (LEN(@Sezionale) > 1 OR @Sezionale NOT LIKE '[A-Z]')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il sezionale è una lettera da A a Z';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		DECLARE @annoInizio DATE = DATEFROMPARTS(@Anno, 1, 1);
		DECLARE @annoFine DATE = DATEADD(YEAR, 1, @annoInizio);

		-- Fatture dell'anno e del sezionale: Id, numero attuale, data che decide l'anno, sola lettura
		DECLARE @fatture TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			Numero INT NOT NULL,
			[Data] DATE NOT NULL,
			SolaLettura BIT NOT NULL
		);

		BEGIN TRANSACTION;

			-- Lettura con blocco separata per tipo, con il filtro sulla colonna della data, come in
			-- uspFatture_upd: per le fatture cliente il blocco copre l'anno dell'azienda
			IF @Tipo = 'C'
				INSERT @fatture (Id, Numero, [Data], SolaLettura)
				SELECT Id, Numero, DataEmissione, ISNULL(SolaLettura, 0)
				FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
				WHERE
					IdSede = @idAzienda
					AND Tipo = 'C'
					AND Lock = 0
					AND Numero IS NOT NULL
					AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
					AND DataEmissione >= @annoInizio
					AND DataEmissione < @annoFine;
			ELSE
				INSERT @fatture (Id, Numero, [Data], SolaLettura)
				SELECT Id, Numero, DataRegistrazione, ISNULL(SolaLettura, 0)
				FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
				WHERE
					IdSede = @idAzienda
					AND Tipo = 'F'
					AND Lock = 0
					AND Numero IS NOT NULL
					AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
					AND DataRegistrazione >= @annoInizio
					AND DataRegistrazione < @annoFine;

			DECLARE @totaleDaRinumerare INT = (SELECT COUNT(*) FROM @fatture WHERE Numero BETWEEN @DalNumero AND @AlNumero);

			-- Se non c'è nulla da rinumerare
			IF @totaleDaRinumerare = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Non ci sono fatture nell''intervallo indicato';
				GOTO BRANCH_END;
			END

			-- Fatture in sola lettura: si rinumerano solo se richiesto
			IF @AncheSolaLettura = 0 AND EXISTS (SELECT 1 FROM @fatture WHERE Numero BETWEEN @DalNumero AND @AlNumero AND SolaLettura = 1)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'L''intervallo contiene fatture in sola lettura: per rinumerarle spuntare "Rinumera anche le fatture in Sola lettura"';
				GOTO BRANCH_END;
			END

			-- Se la numerazione finale supera 999.999
			IF @PrimoNumero + @totaleDaRinumerare - 1 > 999999
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La rinumerazione non può assegnare numeri maggiori di 999.999';
				GOTO BRANCH_END;
			END

			-- Se la nuova numerazione entra in conflitto con fatture fuori dal gruppo che sarà rinumerato
			IF EXISTS (
				SELECT 1
				FROM @fatture
				WHERE
					Numero NOT BETWEEN @DalNumero AND @AlNumero
					AND Numero BETWEEN @PrimoNumero AND @PrimoNumero + @totaleDaRinumerare - 1
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La nuova numerazione è in conflitto con quella di altre fatture';
				GOTO BRANCH_END;
			END

			UPDATE f
			SET Numero = t.NumeroNuovo
			FROM
				dbo.tblFatture f
				INNER JOIN
					(
						SELECT
							Id,
							Numero,
							NumeroNuovo = ROW_NUMBER() OVER (ORDER BY [Data], Numero, Id) + @PrimoNumero - 1
						FROM @fatture
						WHERE Numero BETWEEN @DalNumero AND @AlNumero
					) t ON f.Id = t.Id
			WHERE t.Numero <> t.NumeroNuovo;

			SET @returnValue = @@ROWCOUNT;

		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO
