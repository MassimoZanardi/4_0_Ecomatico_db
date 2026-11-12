SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Spazio per i file allegati del dominio della sessione (byte): IsAttivo = 0 senza FileQuotaMax, e allora le schermate
-- non mostrano la sezione degli allegati
CREATE OR ALTER PROCEDURE [dbo].[uspDomini_get_FileQuota]
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

		SELECT
			IsAttivo = CAST(IIF(ISNULL(d.FileQuotaMax, 0) > 0, 1, 0) AS BIT),
			FileQuotaMax = ISNULL(d.FileQuotaMax, 0),
			FileQuotaConsumata = ISNULL(d.FileQuotaConsumata, 0),
			FileQuotaResidua = IIF(ISNULL(d.FileQuotaMax, 0) - ISNULL(d.FileQuotaConsumata, 0) < 0, 0, ISNULL(d.FileQuotaMax, 0) - ISNULL(d.FileQuotaConsumata, 0))
		FROM
			dbo.tblSessioni e
			INNER JOIN dbo.tblDomini d ON e.IdDominio = d.Id
		WHERE e.Id = @IdSessione;

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
