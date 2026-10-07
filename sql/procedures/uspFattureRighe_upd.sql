SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva una riga della fattura: con @Id vuoto la aggiunge in coda a @IdFattura, altrimenti la modifica.
-- Una riga senza quantità né importo è di sola descrizione (nessuna riga in tblFattureRigheImporti).
-- Le righe si salvano subito, anche sulla fattura in bozza. Restituisce l'Id della riga.
CREATE OR ALTER PROCEDURE dbo.uspFattureRighe_upd
	@Id CHAR(16) = NULL,
	@IdFattura CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Descrizione VARCHAR(1000) = NULL,
	@Quantita DECIMAL(18, 4) = NULL,
	@Importo DECIMAL(18, 4) = NULL,
	@IdUnitaMisura CHAR(2) = NULL,
	@IdAliquotaIva CHAR(16) = NULL,
	@IdConto CHAR(16) = NULL,
	@RitenutaAcconto INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdFattura = NULLIF(LTRIM(RTRIM(@IdFattura)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Descrizione = NULLIF(LTRIM(RTRIM(@Descrizione)), '');
		SET @IdUnitaMisura = NULLIF(NULLIF(LTRIM(RTRIM(@IdUnitaMisura)), ''), REPLICATE('0', 2));
		SET @IdAliquotaIva = NULLIF(NULLIF(LTRIM(RTRIM(@IdAliquotaIva)), ''), REPLICATE('0', 16));
		SET @IdConto = NULLIF(NULLIF(LTRIM(RTRIM(@IdConto)), ''), REPLICATE('0', 16));

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

		-- Riga esistente: la fattura è quella della riga
		DECLARE @idAliquotaIvaAttuale CHAR(16);
		DECLARE @idContoAttuale CHAR(16);
		IF @Id IS NOT NULL
		BEGIN
			SET @IdFattura = NULL;
			SELECT
				@IdFattura = r.IdFattura,
				@idAliquotaIvaAttuale = i.IdAliquotaIva,
				@idContoAttuale = i.IdConto
			FROM
				dbo.tblFattureRighe r
				LEFT JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
			WHERE r.Id = @Id;
		END

		-- La fattura deve esistere (in bozza o attiva, non eliminata), appartenere all'azienda interna
		-- corrente della sessione e non essere in sola lettura
		DECLARE @idAzienda CHAR(16);
		DECLARE @solaLettura BIT;
		SELECT
			@idAzienda = f.IdSede,
			@solaLettura = ISNULL(f.SolaLettura, 0)
		FROM
			dbo.tblFatture f
			INNER JOIN dbo.tblSessioni e ON f.IdSede = e.IdAzienda
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

		IF @Descrizione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la descrizione della riga';
			GOTO BRANCH_END;
		END

		-- Riga con importi: importo (prezzo unitario) e aliquota IVA obbligatori; quantità 1 se non indicata.
		-- L'importo può essere negativo (sconti, storni)
		DECLARE @conImporti BIT = IIF(@Quantita IS NULL AND @Importo IS NULL, 0, 1);
		IF @conImporti = 1
		BEGIN
			SET @Quantita = ISNULL(@Quantita, 1);
			SET @RitenutaAcconto = ISNULL(@RitenutaAcconto, 0);

			IF @Importo IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare l''importo unitario della riga';
				GOTO BRANCH_END;
			END
			IF @Quantita <= 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La quantità deve essere maggiore di zero';
				GOTO BRANCH_END;
			END
			IF @IdAliquotaIva IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Selezionare l''aliquota IVA della riga';
				GOTO BRANCH_END;
			END
			-- Aliquota IVA: di sistema (IdSede NULL) o dell'azienda; quella già sulla riga resta valida
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblAliquoteIva
				WHERE
					Id = @IdAliquotaIva
					AND (IdSede IS NULL OR IdSede = @idAzienda)
					AND (Lock = 0 OR Id = @idAliquotaIvaAttuale)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''aliquota IVA indicata non esiste';
				GOTO BRANCH_END;
			END
			-- Conto: facoltativo, dell'azienda; quello già sulla riga resta valido
			IF @IdConto IS NOT NULL AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblFattureConti
				WHERE
					Id = @IdConto
					AND IdSede = @idAzienda
					AND (Lock = 0 OR Id = @idContoAttuale)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il conto indicato non esiste';
				GOTO BRANCH_END;
			END
			IF @IdUnitaMisura IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblUnitaMisura WHERE Id = @IdUnitaMisura)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''unità di misura indicata non esiste';
				GOTO BRANCH_END;
			END
			IF @RitenutaAcconto < 0 OR @RitenutaAcconto > 100
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La ritenuta d''acconto deve essere compresa tra 0 e 100';
				GOTO BRANCH_END;
			END
		END

		-- Nuova riga: uspId_get FUORI dalla transazione
		DECLARE @nuova BIT = IIF(@Id IS NULL, 1, 0);
		IF @nuova = 1
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @Id OUTPUT;

		BEGIN TRANSACTION;
			IF @nuova = 1
			BEGIN
				-- In coda alle righe della fattura
				DECLARE @pos INT;
				SELECT @pos = ISNULL(MAX(Pos), 0) + 1
				FROM dbo.tblFattureRighe WITH (UPDLOCK, HOLDLOCK)
				WHERE IdFattura = @IdFattura;

				INSERT dbo.tblFattureRighe (Id, IdFattura, Descrizione, Pos)
				VALUES (@Id, @IdFattura, @Descrizione, @pos);
			END
			ELSE
			BEGIN
				UPDATE dbo.tblFattureRighe
				SET Descrizione = @Descrizione
				WHERE Id = @Id;
			END

			DELETE dbo.tblFattureRigheImporti
			WHERE Id = @Id;

			IF @conImporti = 1
				INSERT dbo.tblFattureRigheImporti (Id, IdAliquotaIva, IdConto, IdUnitaMisura, Quantita, Importo, RitenutaAcconto)
				VALUES (@Id, @IdAliquotaIva, @IdConto, @IdUnitaMisura, @Quantita, @Importo, @RitenutaAcconto);
		COMMIT TRANSACTION;

		SELECT Id = @Id;

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
