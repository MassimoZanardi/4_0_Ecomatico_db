SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Pulizia dei file allegati (docs/regole/allegati.md, A7): cancella la riga di un file orfano e ne libera lo spazio sul
-- dominio che l'aveva caricato. Ricontrolla che il record non esista, nella stessa istruzione della cancellazione:
-- una riga tornata valida nel frattempo resta. Il servizio di pulizia la chiama dopo aver cancellato il file
-- dall'archivio. Restituisce 1 se la riga è stata cancellata, 0 se non c'era o non è orfana
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_del_Orfano]
	@Id UNIQUEIDENTIFIER = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @cancellato TABLE (IdDominio CHAR(16), Quota INT);

		BEGIN TRANSACTION;

			DELETE f
			OUTPUT
				deleted.IdDominio,
				ISNULL(deleted.Quota, 0)
			INTO @cancellato (IdDominio, Quota)
			FROM dbo.tblFiles f
			WHERE
				f.Id = @Id
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioni r WHERE r.Id = f.IdRecord)
				AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioni a WHERE a.Id = f.IdRecord);

			UPDATE d
			SET FileQuotaConsumata = IIF(ISNULL(d.FileQuotaConsumata, 0) - c.Quota < 0, 0, ISNULL(d.FileQuotaConsumata, 0) - c.Quota)
			FROM
				dbo.tblDomini d
				INNER JOIN @cancellato c ON d.Id = c.IdDominio;

		COMMIT TRANSACTION;

		SELECT Cancellato = CAST(IIF(EXISTS (SELECT 1
		FROM @cancellato), 1, 0) AS INT);

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
