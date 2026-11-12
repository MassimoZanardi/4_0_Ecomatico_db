SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Pulizia dei file allegati (docs/regole/allegati.md, A7): righe di tblFiles il cui record non esiste più, per esempio
-- una rettifica non inviata cancellata fisicamente. Un record cancellato con Lock = 4 esiste ancora e tiene i suoi
-- file per il ripristino. Usata dal servizio di pulizia dell'app, senza sessione.
-- ATTENZIONE: quando gli allegati si estendono a un'altra tabella, va aggiunta qui, altrimenti i suoi file risultano
-- orfani e vengono cancellati
CREATE OR ALTER PROCEDURE [dbo].[uspFiles_get_Orfani_List]
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		SELECT
			f.Id,
			f.IdRecord,
			f.IdDominio,
			f.Nome,
			Quota = ISNULL(f.Quota, 0)
		FROM dbo.tblFiles f
		WHERE
			NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiRegistrazioni r WHERE r.Id = f.IdRecord)
			AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiAutorizzazioni a WHERE a.Id = f.IdRecord);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	SET NOCOUNT, XACT_ABORT OFF;

END;
GO
