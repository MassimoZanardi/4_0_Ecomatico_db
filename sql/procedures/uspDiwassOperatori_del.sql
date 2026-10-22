SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scollega una sede dall'operatore DIWASS (Scollega): solo le sedi dell'azienda del contesto; l'azienda solo dopo
-- le sue sedi
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassOperatori_del]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
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
			@IdFunzione = 'DWO',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità): solo le sedi dell'azienda del contesto, non quelle condivise
		DECLARE @condivisa BIT;
		SELECT @condivisa = Condivisa
		FROM dbo.ufnDiwassOperatori_get_SediBySessione_List(@IdSessione)
		WHERE Id = @Id;

		IF @condivisa IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END
		IF @condivisa = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il soggetto è condiviso da un''altra azienda: il collegamento a DIWASS lo gestisce l''azienda che lo ha creato';
			GOTO BRANCH_END;
		END

		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblSedi s
				INNER JOIN dbo.tblDiwassOperatori o ON s.Id = o.Id
			WHERE s.IdParent = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Scollegare prima le sedi dell''azienda collegate a DIWASS';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DELETE dbo.tblDiwassOperatori
			WHERE Id = @Id;
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

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
