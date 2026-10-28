SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Id dell'hub della credenziale DIWASS dell'azienda interna del contesto, usata dalle pagine operative per parlare
-- con DIWASS (ricerca e lettura degli operatori). Basta la funzione DWO: non serve DWC (configurazione)
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassOperatori_get_IdDiwassCredenziale]
	@IdSessione CHAR(16) = NULL
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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'DWO',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16) = (SELECT IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione);
		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		-- Credenziale associata all'azienda in Diwass > Aziende
		DECLARE @idDiwass CHAR(16) = (
			SELECT c.IdDiwass
			FROM
				dbo.tblDiwassCredenzialiAziende a
				INNER JOIN dbo.tblDiwassCredenziali c ON a.IdCredenziale = c.Id
			WHERE
				a.IdAziendaInterna = @idAzienda
				AND c.Lock = 0
		);
		IF @idDiwass IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''azienda non ha una credenziale DIWASS: chiedere all''amministratore di associarla in Diwass > Aziende';
			GOTO BRANCH_END;
		END

		SELECT rtn = @idDiwass;

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
