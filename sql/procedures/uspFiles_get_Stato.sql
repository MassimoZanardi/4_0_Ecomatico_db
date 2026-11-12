SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Sezione "Allegati" della scheda di una registrazione o di un'autorizzazione (@IdRecord): spazio del dominio della
-- sessione (byte) e permesso sul record (uspFiles_get_Permesso: 0 nessuno, 1 lettura, 2 modifica). La sezione si mostra
-- con IsAttivo = 1 (FileQuotaMax > 0) e Permesso >= 1; senza permesso non è un errore, la sezione resta nascosta
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_get_Stato]
	@IdRecord CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdRecord = NULLIF(LTRIM(RTRIM(@IdRecord)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdRecord IS NULL OR @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I parametri @IdRecord e @IdSessione non possono essere vuoti';
			GOTO BRANCH_END;
		END

		DECLARE @permesso INT;
		EXEC dbo.uspFiles_get_Permesso
			@IdRecord = @IdRecord,
			@IdSessione = @IdSessione,
			@Permesso = @permesso OUTPUT;

		SELECT
			IdRecord = @IdRecord,
			IsAttivo = CAST(IIF(ISNULL(d.FileQuotaMax, 0) > 0, 1, 0) AS BIT),
			Permesso = ISNULL(@permesso, 0),
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
