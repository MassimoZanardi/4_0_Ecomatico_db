SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspRifiutiFormulari_del_Undo]
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

		-- Un formulario cancellato la cui registrazione indica nel frattempo un altro documento di trasporto (Allegato
		-- VII o Allegato I-B) non si ripristina: con il cambio del documento il numero del formulario è stato azzerato
		-- (uspRifiutiRegistrazioni_upd)
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblIdCancellati c
				INNER JOIN dbo.tblRifiutiFormulari f ON c.Id = f.Id
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON f.IdMovimento = r.IdMovimento
			WHERE
				c.IdSessione = @IdSessione
				AND r.Lock < 2
				AND r.IdTrasportoTransfrontalieroTipo IS NOT NULL
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il formulario non può essere ripristinato: la sua registrazione indica ora un altro documento di trasporto';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM
				dbo.tblRifiutiFormulari i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE c.IdSessione = @IdSessione;

			-- Aggiorna il Log
			DELETE i
			FROM
				dbo.tblIdLog i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;

			SET @returnMessage = IIF(@@ROWCOUNT = 1, 'Entità ripristinata', FORMAT(@@ROWCOUNT, 'N0', 'it-IT') + ' entità ripristinate');

		COMMIT TRANSACTION;

		SELECT ReturnMessage = @returnMessage;

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
