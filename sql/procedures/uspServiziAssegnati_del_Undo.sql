CREATE OR ALTER PROCEDURE [dbo].[uspServiziAssegnati_del_Undo]
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

		BEGIN TRANSACTION;

			-- Ripristina i servizi assegnati cancellati (eventi singoli)
			UPDATE e
			SET Lock = 0
			FROM dbo.tblServizi i
			INNER JOIN dbo.tblEventi e ON i.IdEvento = e.Id
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND c.DataEccezione IS NULL;

			-- Ripristina le eccezioni di ricorrenza cancellate
			UPDATE i
			SET Lock = 0
			FROM dbo.tblRicorrenzeEccezioni i
			INNER JOIN dbo.tblServizi s ON i.Id = s.IdEvento
			INNER JOIN dbo.tblIdCancellati c ON s.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND c.DataEccezione IS NULL;

			-- Rimuove le eccezioni per singola occorrenza
			DELETE i
			FROM dbo.tblRicorrenzeEccezioni i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
												   AND i.[Data] = c.DataEccezione
			WHERE
				c.IdSessione = @IdSessione
				AND i.IdEvento IS NULL;

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
		THROW 50001, @returnMessage, 1
	END

END;
