SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Genera le rate della fattura dalle condizioni di pagamento salvate sulla testata, sostituendo quelle
-- presenti. Numero di rate e mesi della prima vengono dalla rateizzazione (tblPagamentiRate: Numero,
-- PrimaMesi; le successive a un mese l'una dall'altra); senza rateizzazione una sola rata alla data
-- della fattura. Decorrenza DF: scadenza = data della fattura + mesi. Decorrenza FM: fine del mese
-- di (data della fattura + mesi) e, con il giorno del mese indicato, quel giorno del mese successivo.
-- Importo: netto a pagare diviso in parti uguali, con il resto degli arrotondamenti sull'ultima rata.
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_ins_Genera
	@IdFattura CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdFattura = NULLIF(LTRIM(RTRIM(@IdFattura)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdFattura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdFattura non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
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

		-- La fattura deve esistere (in bozza o attiva, non eliminata), appartenere all'azienda interna
		-- corrente della sessione e non essere in sola lettura
		DECLARE @idAzienda CHAR(16);
		DECLARE @solaLettura BIT;
		DECLARE @dataEmissione DATE;
		DECLARE @idRataInizio CHAR(2);
		DECLARE @giorno INT;
		DECLARE @numero INT;
		DECLARE @primaMesi INT;
		SELECT
			@idAzienda = f.IdSede,
			@solaLettura = ISNULL(f.SolaLettura, 0),
			@dataEmissione = f.DataEmissione,
			@idRataInizio = ISNULL(f.IdRataInizio, 'DF'),
			@giorno = ISNULL(f.RataGiorniInizio, 0),
			@numero = ISNULL(r.Numero, 1),
			@primaMesi = ISNULL(r.PrimaMesi, 0)
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblPagamentiRate r ON f.IdRata = r.Id
		WHERE
			f.Id = @IdFattura
			AND e.Id = @IdSessione
			AND f.Lock IN (0, 2);

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END
		IF @solaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura e salvare';
			GOTO BRANCH_END;
		END
		IF @dataEmissione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data della fattura prima di generare le rate';
			GOTO BRANCH_END;
		END
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblFattureRate r
				INNER JOIN dbo.tblFattureRatePagamenti p ON r.Id = p.IdRata
			WHERE r.IdFattura = @IdFattura)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le rate hanno già dei pagamenti: non si possono rigenerare';
			GOTO BRANCH_END;
		END

		DECLARE @netto DECIMAL(18, 2);
		SELECT @netto = NettoAPagare
		FROM dbo.ufnFatture_get_Totali(@IdFattura);

		IF ISNULL(@netto, 0) <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura non ha un importo da pagare: inserire prima le righe';
			GOTO BRANCH_END;
		END
		IF @numero < 1 SET @numero = 1;

		-- Scadenze e importi; gli Id (uspId_get) FUORI dalla transazione
		DECLARE @rate TABLE (
			N INT NOT NULL PRIMARY KEY,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			DataScadenza DATE NOT NULL,
			Importo DECIMAL(18, 2) NOT NULL
		);
		DECLARE @quota DECIMAL(18, 2) = ROUND(@netto / @numero, 2, 1);
		DECLARE @n INT = 1;
		DECLARE @scadenza DATE;
		DECLARE @fineMese DATE;
		DECLARE @id CHAR(16);

		WHILE @n <= @numero
		BEGIN
			SET @scadenza = DATEADD(MONTH, @primaMesi + @n - 1, @dataEmissione);
			IF @idRataInizio = 'FM'
			BEGIN
				SET @scadenza = EOMONTH(@scadenza);
				IF @giorno > 0
				BEGIN
					-- Giorno del mese successivo, non oltre la sua fine (31 in un mese di 30 giorni)
					SET @fineMese = EOMONTH(DATEADD(DAY, 1, @scadenza));
					SET @scadenza = DATEADD(DAY, IIF(@giorno > DAY(@fineMese), DAY(@fineMese), @giorno), @scadenza);
				END
			END

			SET @id = NULL;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @id OUTPUT;

			INSERT @rate (N, Id, DataScadenza, Importo)
			VALUES (@n, @id, @scadenza, IIF(@n = @numero, @netto - @quota * (@numero - 1), @quota));

			SET @n += 1;
		END

		DECLARE @vecchie TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);

		BEGIN TRANSACTION;
			INSERT @vecchie (Id)
			SELECT Id
			FROM dbo.tblFattureRate WITH (UPDLOCK, HOLDLOCK)
			WHERE IdFattura = @IdFattura;

			DELETE dbo.tblFattureRate
			WHERE IdFattura = @IdFattura;
			DELETE dbo.tblIdLog
			WHERE Id IN (SELECT Id FROM @vecchie);
			DELETE dbo.tblId
			WHERE Id IN (SELECT Id FROM @vecchie);

			INSERT dbo.tblFattureRate (Id, IdFattura, Importo, Abbuono, DataScadenza)
			SELECT Id, @IdFattura, Importo, 0, DataScadenza
			FROM @rate;
		COMMIT TRANSACTION;

		SELECT ReturnValue = @numero;

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
