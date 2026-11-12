SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Cancella un file allegato: toglie la riga e libera lo spazio del dominio che l'ha caricato (tblFiles.IdDominio).
-- Serve il permesso di modifica sul record (uspFiles_get_Permesso). L'app cancella il contenuto dall'Object Storage
-- (<Prefisso>/<Id>) dopo questa SP; un file già cancellato non è un errore (doppio clic, caricamento fallito)
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_del]
	@Id UNIQUEIDENTIFIER = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @Id e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		DECLARE @idRecord CHAR(16);
		DECLARE @idDominio CHAR(16);
		DECLARE @quota INT;
		SELECT
			@idRecord = IdRecord,
			@idDominio = IdDominio,
			@quota = ISNULL(Quota, 0)
		FROM dbo.tblFiles
		WHERE Id = @Id;

		IF @idRecord IS NOT NULL
		BEGIN

			DECLARE @permesso INT;
			EXEC dbo.uspFiles_get_Permesso
				@IdRecord = @idRecord,
				@IdSessione = @IdSessione,
				@Permesso = @permesso OUTPUT;

			IF 2 > @permesso
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;

				DELETE dbo.tblFiles
				WHERE Id = @Id;

				-- Una cancellazione contemporanea dello stesso file libera lo spazio una volta sola
				IF @@ROWCOUNT > 0
					UPDATE dbo.tblDomini
					SET FileQuotaConsumata = IIF(ISNULL(FileQuotaConsumata, 0) - @quota < 0, 0, ISNULL(FileQuotaConsumata, 0) - @quota)
					WHERE Id = @idDominio;

			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @idRecord, @IdSessione = @IdSessione, @Operazione = 'U';

		END

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
