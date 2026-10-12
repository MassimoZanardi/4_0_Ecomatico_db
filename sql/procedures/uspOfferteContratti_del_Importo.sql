SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Toglie un importo da un contratto o da un'offerta (attivo o in bozza) dell'azienda interna corrente della
-- sessione. L'importo non viene cancellato: senza contratto torna a essere un importo standard, valido per
-- tutti i clienti. Un importo che non è (più) associato non è un errore.
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_del_Importo
	@Id CHAR(16) = NULL,
	@IdImporto CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdImporto = NULLIF(LTRIM(RTRIM(@IdImporto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdImporto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdImporto non può essere vuoto';
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
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblOfferteContratti oc
				INNER JOIN dbo.tblSessioni e ON oc.IdSede = e.IdAzienda
			WHERE
				oc.Id = @Id
				AND e.Id = @IdSessione
				AND oc.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il contratto non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DELETE dbo.tblOfferteContrattiImporti
			WHERE
				IdOffertaContratto = @Id
				AND IdImporto = @IdImporto;
		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;

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
