SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Esito di "Verifica Vi.Vi.FIR" di un'azienda interna (Vivifir > Aziende), letto dall'app sull'hub: il soggetto Vi.Vi.FIR
-- dell'azienda (Id e denominazione) e il codice del blocco del formulario unico (isArt230c5), che la vidimazione userà.
-- Senza un soggetto o senza un blocco si salva quello che c'è (NULL per il resto) con la data della verifica
CREATE OR ALTER PROCEDURE [dbo].[uspViviFirAziende_upd_Verifica]
	@IdAziendaInterna CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSoggetto INT = NULL,
	@Soggetto VARCHAR(255) = NULL,
	@Blocco VARCHAR(20) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdAziendaInterna = NULLIF(LTRIM(RTRIM(@IdAziendaInterna)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Soggetto = dbo.ufnStringhe_get_SenzaSpazi(@Soggetto, 0, 1);
		SET @Blocco = UPPER(NULLIF(LTRIM(RTRIM(@Blocco)), ''));

		IF @IdAziendaInterna IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdAziendaInterna non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSoggetto IS NULL AND @Blocco IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il blocco Vi.Vi.FIR richiede il soggetto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'VVC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda interna del dominio visibile all'utente
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblSessioni e
				CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
			WHERE
				e.Id = @IdSessione
				AND i.Id = @IdAziendaInterna
				AND i.IdDominio = e.IdDominio
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblViviFirCredenzialiAziende
			SET
				IdSoggetto = @IdSoggetto,
				Soggetto = @Soggetto,
				Blocco = @Blocco,
				DataVerifica = SYSDATETIME()
			WHERE IdAziendaInterna = @IdAziendaInterna;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Associare e salvare prima una credenziale Vi.Vi.FIR';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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
