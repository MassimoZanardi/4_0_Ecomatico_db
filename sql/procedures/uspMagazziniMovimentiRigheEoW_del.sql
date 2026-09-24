SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspMagazziniMovimentiRigheEoW_del
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

		-- Idempotenza: mai esistita è trattata come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheEoW WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- La riga è rimovibile mentre il movimento è in bozza o già confermato (non
		-- se eliminato, Lock = 4): le righe EoW rappresentano sempre uno scarico
		-- (vedi Ins), quindi rimuoverle libera solo disponibilità, mai un vincolo
		-- reale da verificare, a differenza dei carichi tradizionali. IdMovimento
		-- non ha FK: il join è comunque valido, solo non vincolato a livello DB.
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblMagazziniMovimentiRigheEoW r
				INNER JOIN dbo.tblMagazziniMovimenti c ON r.IdMovimento = c.Id
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				r.Id = @Id
				AND e.Id = @IdSessione
				AND c.Lock IN (0, 2)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il movimento non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DELETE dbo.tblMagazziniMovimentiRigheEoWLotti
			WHERE Id = @Id;

			DELETE dbo.tblMagazziniMovimentiRigheEoW
			WHERE Id = @Id;
		COMMIT TRANSACTION;

		END

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
