SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspDiwassCredenziali_del_Undo]
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

		-- Una sola credenziale attiva per azienda: se nel frattempo l'azienda ne ha una nuova, non si ripristina
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblDiwassCredenziali i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
				INNER JOIN dbo.tblDiwassCredenziali a ON i.IdAziendaInterna = a.IdAziendaInterna
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4
				AND a.Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Impossibile ripristinare: l''azienda ha già un''altra credenziale DIWASS';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblDiwassCredenziali i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4;

			DELETE i
			FROM dbo.tblIdLog i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;
			DECLARE @ripristinate INT = @@ROWCOUNT;

		COMMIT TRANSACTION;

		SET @returnMessage = CASE @ripristinate
			WHEN 0 THEN 'Nessuna entità da ripristinare'
			WHEN 1 THEN 'Entità ripristinata'
			ELSE FORMAT(@ripristinate, 'N0', 'it-IT') + ' entità ripristinate'
		END;

		SELECT @returnMessage AS ReturnMessage;

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
