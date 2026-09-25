SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheRelazioni_del
	@IdParent CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdParent = NULLIF(LTRIM(RTRIM(@IdParent)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @IdParent IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdParent non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'MAG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Solo associazioni manuali (criterio Manuale, IdCriterio NULL) di uno scarico
		-- dell'azienda interna corrente, con movimento non eliminato: con FIFO/LIFO/FEFO le
		-- relazioni sono gestite da uspMagazziniMovimenti_upd
		DECLARE @idCriterio CHAR(1), @trovata BIT = 0;
		SELECT
			@trovata = 1,
			@idCriterio = r.IdCriterio
		FROM
			dbo.tblMagazziniMovimentiRighe r
			INNER JOIN dbo.tblMagazziniMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblSessioni e ON m.IdSede = e.IdAzienda
		WHERE
			r.Id = @IdParent
			AND e.Id = @IdSessione
			AND m.IdOperazione = 'S'
			AND m.Lock IN (0, 2);

		IF @trovata = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la riga di scarico non esiste';
			GOTO BRANCH_END;
		END
		IF @idCriterio IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con un criterio di scarico automatico i carichi vengono associati al salvataggio del movimento';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DELETE dbo.tblMagazziniMovimentiRigheRelazioni
			WHERE
				Id = @Id
				AND IdParent = @IdParent;
		COMMIT TRANSACTION;

		SELECT ReturnValue = @returnValue;

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
