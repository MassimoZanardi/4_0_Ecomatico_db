SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva i dati fiscali dell'azienda interna corrente della sessione (una riga per azienda: la crea se manca).
-- Regime fiscale obbligatorio. Iscrizione REA: ufficio e numero si indicano insieme e, con loro, lo stato di
-- liquidazione, come richiede il file della fattura elettronica; capitale sociale e socio unico solo con
-- l'iscrizione.
-- Ritenuta d'acconto: tipo e causale del pagamento si indicano insieme.
CREATE OR ALTER PROCEDURE dbo.uspFattureDatiFiscali_upd
	@IdSessione CHAR(16) = NULL,
	@IdRegimeFiscale CHAR(4) = NULL,
	@IdProvinciaRea CHAR(3) = NULL,
	@IdRitenutaTipo CHAR(4) = NULL,
	@IdRitenutaCausale VARCHAR(2) = NULL,
	@NumeroRea VARCHAR(30) = NULL,
	@CapitaleSociale DECIMAL(18, 2) = NULL,
	@SocioUnico CHAR(2) = NULL,
	@StatoLiquidazione CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegimeFiscale = UPPER(NULLIF(NULLIF(LTRIM(RTRIM(@IdRegimeFiscale)), ''), REPLICATE('0', 4)));
		SET @IdProvinciaRea = NULLIF(NULLIF(LTRIM(RTRIM(@IdProvinciaRea)), ''), REPLICATE('0', 3));
		SET @IdRitenutaTipo = UPPER(NULLIF(NULLIF(LTRIM(RTRIM(@IdRitenutaTipo)), ''), REPLICATE('0', 4)));
		SET @IdRitenutaCausale = UPPER(NULLIF(NULLIF(LTRIM(RTRIM(@IdRitenutaCausale)), ''), '0'));
		SET @NumeroRea = NULLIF(REPLACE(LTRIM(RTRIM(@NumeroRea)), ' ', ''), '');
		SET @SocioUnico = UPPER(NULLIF(LTRIM(RTRIM(@SocioUnico)), ''));
		SET @StatoLiquidazione = UPPER(NULLIF(LTRIM(RTRIM(@StatoLiquidazione)), ''));

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
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- I dati sono dell'azienda interna corrente della sessione
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

		IF @IdRegimeFiscale IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il regime fiscale';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureRegimiFiscali WHERE Id = @IdRegimeFiscale)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il regime fiscale indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Iscrizione REA
		IF @IdProvinciaRea IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblProvince WHERE Id = @IdProvinciaRea AND Sigla IS NOT NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''ufficio REA indicato non esiste';
			GOTO BRANCH_END;
		END
		IF (@IdProvinciaRea IS NULL AND @NumeroRea IS NOT NULL) OR (@IdProvinciaRea IS NOT NULL AND @NumeroRea IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Per l''iscrizione REA indicare sia l''ufficio sia il numero';
			GOTO BRANCH_END;
		END
		IF LEN(@NumeroRea) > 20
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il numero REA non può superare i 20 caratteri';
			GOTO BRANCH_END;
		END
		IF @CapitaleSociale < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il capitale sociale non può essere negativo';
			GOTO BRANCH_END;
		END
		IF @SocioUnico IS NOT NULL AND @SocioUnico NOT IN ('SU', 'SM')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @SocioUnico deve essere SU (socio unico) o SM (più soci)';
			GOTO BRANCH_END;
		END
		IF @StatoLiquidazione IS NOT NULL AND @StatoLiquidazione NOT IN ('LS', 'LN')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @StatoLiquidazione deve essere LS (in liquidazione) o LN (non in liquidazione)';
			GOTO BRANCH_END;
		END
		IF @IdProvinciaRea IS NULL AND (@CapitaleSociale IS NOT NULL OR @SocioUnico IS NOT NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con il capitale sociale o il socio unico indicare anche l''iscrizione REA (ufficio e numero)';
			GOTO BRANCH_END;
		END
		-- Senza iscrizione REA lo stato di liquidazione non serve; con l'iscrizione è richiesto
		IF @IdProvinciaRea IS NULL
			SET @StatoLiquidazione = NULL;
		ELSE IF @StatoLiquidazione IS NULL
			SET @StatoLiquidazione = 'LN';

		-- Ritenuta d'acconto: tipo e causale insieme
		IF (@IdRitenutaTipo IS NULL AND @IdRitenutaCausale IS NOT NULL) OR (@IdRitenutaTipo IS NOT NULL AND @IdRitenutaCausale IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Per la ritenuta d''acconto selezionare sia il tipo sia la causale del pagamento';
			GOTO BRANCH_END;
		END
		IF @IdRitenutaTipo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblFattureRitenuteTipi WHERE Id = @IdRitenutaTipo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il tipo di ritenuta indicato non esiste';
			GOTO BRANCH_END;
		END
		IF @IdRitenutaCausale IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblFattureRitenuteCausali WHERE Id = @IdRitenutaCausale)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La causale del pagamento indicata non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblFattureDatiFiscali WITH (UPDLOCK, HOLDLOCK)
			SET
				IdRegimeFiscale = @IdRegimeFiscale,
				IdProvinciaRea = @IdProvinciaRea,
				IdRitenutaTipo = @IdRitenutaTipo,
				IdRitenutaCausale = @IdRitenutaCausale,
				NumeroRea = @NumeroRea,
				CapitaleSociale = @CapitaleSociale,
				SocioUnico = @SocioUnico,
				StatoLiquidazione = @StatoLiquidazione
			WHERE Id = @idAzienda;

			IF @@ROWCOUNT = 0
				INSERT dbo.tblFattureDatiFiscali (Id, IdRegimeFiscale, IdProvinciaRea, IdRitenutaTipo, IdRitenutaCausale, NumeroRea, CapitaleSociale, SocioUnico, StatoLiquidazione)
				VALUES (@idAzienda, @IdRegimeFiscale, @IdProvinciaRea, @IdRitenutaTipo, @IdRitenutaCausale, @NumeroRea, @CapitaleSociale, @SocioUnico, @StatoLiquidazione);
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
