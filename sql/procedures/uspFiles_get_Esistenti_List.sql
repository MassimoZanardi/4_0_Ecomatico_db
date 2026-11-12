SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Pulizia dei file allegati (docs/regole/allegati.md, A7): tra gli Id dei file trovati nell'archivio (@Ids, separati da
-- virgola), quelli che hanno ancora la riga in tblFiles. Gli altri sono file rimasti nell'archivio dopo una
-- cancellazione non completata e il servizio di pulizia li cancella. Un valore che non è un Id viene ignorato
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_get_Esistenti_List]
	@Ids VARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		SELECT f.Id
		FROM
			dbo.tblFiles f
			INNER JOIN (
				SELECT DISTINCT Id = TRY_CAST(LTRIM(RTRIM(s.value)) AS UNIQUEIDENTIFIER)
				FROM STRING_SPLIT(ISNULL(@Ids, ''), ',') s
			) i ON f.Id = i.Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;

END;
GO
