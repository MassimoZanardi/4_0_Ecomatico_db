SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Nuovo file allegato a una registrazione o a un'autorizzazione (@IdRecord). Controlla nome, tipo, dimensione, permesso di
-- modifica (uspFiles_get_Permesso) e spazio del dominio; prenota lo spazio (tblDomini.FileQuotaConsumata) e restituisce
-- l'Id del file. L'app carica poi il contenuto sull'Object Storage (<Prefisso>/<Id>); se il caricamento fallisce chiama
-- uspFiles_del, che toglie la riga e libera lo spazio.
-- Spazio: FileQuotaMax e FileQuotaConsumata in byte; senza FileQuotaMax (NULL o 0) gli allegati non sono attivi
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_ins]
	@IdRecord CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(500) = NULL,
	@Quota INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		DECLARE @quotaMaxFile INT = 10485760; -- 10 MB

		SET @IdRecord = NULLIF(LTRIM(RTRIM(@IdRecord)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = NULLIF(LTRIM(RTRIM(@Nome)), '');

		IF @IdRecord IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @IdRecord e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il nome del file non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF LEN(@Nome) > 200
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il nome del file può avere al massimo 200 caratteri';
			GOTO BRANCH_END;
		END

		DECLARE @estensione VARCHAR(500) = IIF(CHARINDEX('.', @Nome) > 0, LOWER(RIGHT(@Nome, CHARINDEX('.', REVERSE(@Nome)) - 1)), '');
		IF @estensione NOT IN ('pdf', 'png', 'jpg', 'jpeg', 'gif')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Tipo di file non ammesso: selezionare un file PDF, PNG, JPG, JPEG o GIF';
			GOTO BRANCH_END;
		END

		IF ISNULL(@Quota, 0) <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il file è vuoto';
			GOTO BRANCH_END;
		END
		IF @Quota > @quotaMaxFile
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La dimensione massima del file è 10 MB';
			GOTO BRANCH_END;
		END

		DECLARE @permesso INT;
		EXEC dbo.uspFiles_get_Permesso
			@IdRecord = @IdRecord,
			@IdSessione = @IdSessione,
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idDominio CHAR(16) = (SELECT IdDominio
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione);

		DECLARE @id UNIQUEIDENTIFIER = NEWID();

		BEGIN TRANSACTION;

			-- Prenota lo spazio in un'unica istruzione: due caricamenti contemporanei non superano insieme il massimo
			UPDATE dbo.tblDomini
			SET FileQuotaConsumata = ISNULL(FileQuotaConsumata, 0) + @Quota
			WHERE
				Id = @idDominio
				AND ISNULL(FileQuotaMax, 0) > 0
				AND ISNULL(FileQuotaConsumata, 0) + @Quota <= FileQuotaMax;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = IIF(EXISTS (SELECT 1
				FROM dbo.tblDomini
				WHERE
					Id = @idDominio
					AND ISNULL(FileQuotaMax, 0) > 0
				), 'Spazio per i file allegati insufficiente', 'Lo spazio per i file allegati non è attivo');
				GOTO BRANCH_END;
			END

			INSERT dbo.tblFiles (Id, IdRecord, IdDominio, Nome, Quota)
			VALUES (@id, @IdRecord, @idDominio, @Nome, @Quota);

		COMMIT TRANSACTION;

		EXEC dbo.uspId_upd @Id = @IdRecord, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT Id = @id;

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
