SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_ins
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));

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

		-- Controlla il permesso sulla funzione: ANC per i clienti, ANF per i fornitori
		DECLARE @idFunzione CHAR(3) = IIF(@Tipo = 'C', 'ANC', 'ANF');
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La scheda appartiene all'azienda interna corrente della sessione
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

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		-- Bozza: il soggetto si sceglie nella scheda. Valori predefiniti: valuta euro; decorrenza delle rate dalla data fattura (DF); giorno del mese, importo minimo fatturabile e ritenuta d'acconto a 0; per un cliente
		-- le fatture della procedura automatica raggruppate per cliente (C)
		BEGIN TRANSACTION;
			INSERT dbo.tblClientiFornitori (Id, IdAziendaInterna, Tipo, IdValuta, IdRataInizio, SplitPayment, RataGiorniInizio, ImportoMinimoFatturabile, RitenutaAcconto, IdRaggruppamento, Lock)
			VALUES (@returnId, @idAzienda, @Tipo, 'EUR', 'DF', 0, 0, 0, 0, IIF(@Tipo = 'C', 'C', NULL), 2);
		COMMIT TRANSACTION;

		SELECT Id = @returnId;

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

END;
GO
