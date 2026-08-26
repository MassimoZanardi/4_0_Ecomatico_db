SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspAvvisi_get_Dashboard_Statistiche]
	@IdUtente CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);

		-- Aggregato su tutte le sedi accessibili all'utente, coerente con lo spirito di
		-- riepilogo della dashboard (stesso principio già usato per Limiti superati).
		SELECT
			RegistrazioniSettimana = COUNT(CASE WHEN r.[Data] >= DATEADD(DAY, -7, @oggi) THEN 1 END),
			RegistrazioniMese = COUNT(CASE WHEN r.[Data] >= DATEADD(MONTH, -1, @oggi) THEN 1 END)
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneByUtente_List(@IdUtente) i ON g.IdSede = i.Id
		WHERE
			r.Lock = 0
			AND r.[Data] >= DATEADD(MONTH, -1, @oggi) -- il mese è la finestra più ampia, un solo filtro basta
		OPTION (RECOMPILE);

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
