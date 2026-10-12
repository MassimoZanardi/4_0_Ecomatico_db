SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Nuovo importo rifiuti, in bozza (Lock = 2), dell'azienda interna corrente della sessione, con priorità Media.
-- @IdOffertaContratto (facoltativo): l'importo nasce già associato a quel contratto o a quell'offerta ("Nuovo
-- importo" dalla scheda del contratto); serve anche il permesso di modifica sui contratti (OCC).
CREATE OR ALTER PROCEDURE dbo.uspImportiRifiuti_ins
	@IdSessione CHAR(16) = NULL,
	@IdOffertaContratto CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOffertaContratto = NULLIF(NULLIF(LTRIM(RTRIM(@IdOffertaContratto)), ''), REPLICATE('0', 16));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Rifiuti sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'importo appartiene all'azienda interna corrente della sessione
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

		-- Contratto o offerta a cui associare l'importo: della stessa azienda, attivo o in bozza
		IF @IdOffertaContratto IS NOT NULL
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'OCC',
				@Permesso = @permesso OUTPUT;
			IF 2 > @permesso OR NOT EXISTS (
				SELECT 1
				FROM dbo.tblOfferteContratti
				WHERE
					Id = @IdOffertaContratto
					AND IdSede = @idAzienda
					AND Lock <= 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari, o il contratto non esiste';
				GOTO BRANCH_END;
			END
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblImporti (Id, IdSede, IdPriorita, Lock)
			VALUES (@returnId, @idAzienda, 4, 2);

			INSERT dbo.tblImportiRifiuti (Id)
			VALUES (@returnId);

			IF @IdOffertaContratto IS NOT NULL
				INSERT dbo.tblOfferteContrattiImporti (IdOffertaContratto, IdImporto)
				VALUES (@IdOffertaContratto, @returnId);
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
