SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Ripristina gli importi (rifiuti, magazzino o servizi) cancellati con l'ultima cancellazione della sessione.
-- Rifiutato se nel frattempo è stato inserito un importo dello stesso modulo con lo stesso nome.
CREATE OR ALTER PROCEDURE dbo.uspImporti_del_Undo
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Dopo la cancellazione può essere stato inserito un importo dello stesso modulo con lo stesso nome
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblImporti i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
				INNER JOIN dbo.tblImporti a ON i.IdSede = a.IdSede
										   AND i.Nome = a.Nome
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4
				AND a.Lock = 0
				AND
					(
					(EXISTS (SELECT 1 FROM dbo.tblImportiRifiuti x WHERE x.Id = i.Id) AND EXISTS (SELECT 1 FROM dbo.tblImportiRifiuti x WHERE x.Id = a.Id))
					OR (EXISTS (SELECT 1 FROM dbo.tblImportiMagazzino x WHERE x.Id = i.Id) AND EXISTS (SELECT 1 FROM dbo.tblImportiMagazzino x WHERE x.Id = a.Id))
					OR (EXISTS (SELECT 1 FROM dbo.tblImportiServizi x WHERE x.Id = i.Id) AND EXISTS (SELECT 1 FROM dbo.tblImportiServizi x WHERE x.Id = a.Id))
					)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ripristino non possibile: esiste già un importo con lo stesso nome';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblImporti i
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
