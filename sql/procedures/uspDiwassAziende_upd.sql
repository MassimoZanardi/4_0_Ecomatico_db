SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Diwass > Aziende: associa a un'azienda interna la credenziale DIWASS con cui lavora (una credenziale del dominio può
-- servire più aziende, un'azienda ne usa al massimo una). Senza credenziale (@IdCredenziale vuoto o sedici zeri)
-- l'associazione si toglie
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassAziende_upd]
	@IdAziendaInterna CHAR(16) = NULL,
	@IdCredenziale CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdAziendaInterna = NULLIF(LTRIM(RTRIM(@IdAziendaInterna)), '');
		SET @IdCredenziale = NULLIF(NULLIF(LTRIM(RTRIM(@IdCredenziale)), ''), REPLICATE('0', 16));
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): azienda interna del dominio visibile all'utente
		DECLARE @idDominio CHAR(16);
		SELECT @idDominio = i.IdDominio
		FROM
			dbo.tblSessioni e
			CROSS APPLY dbo.ufnSedi_get_AziendeInterneByUtente_List(e.IdUtente) i
		WHERE
			e.Id = @IdSessione
			AND i.Id = @IdAziendaInterna
			AND i.IdDominio = e.IdDominio;

		IF @idDominio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La credenziale deve essere dello stesso dominio, attiva e già salvata nell'hub
		IF @IdCredenziale IS NOT NULL
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblDiwassCredenziali
				WHERE
					Id = @IdCredenziale
					AND IdDominio = @idDominio
					AND Lock = 0
					AND IdDiwass IS NOT NULL
			)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La credenziale selezionata non è valida';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			IF @IdCredenziale IS NULL
				DELETE dbo.tblDiwassCredenzialiAziende
				WHERE IdAziendaInterna = @IdAziendaInterna;
			ELSE IF EXISTS (SELECT 1
			FROM dbo.tblDiwassCredenzialiAziende
			WHERE IdAziendaInterna = @IdAziendaInterna)
				UPDATE dbo.tblDiwassCredenzialiAziende
				SET IdCredenziale = @IdCredenziale
				WHERE IdAziendaInterna = @IdAziendaInterna;
			ELSE
				INSERT INTO dbo.tblDiwassCredenzialiAziende (IdAziendaInterna, IdCredenziale)
				VALUES (@IdAziendaInterna, @IdCredenziale);
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
