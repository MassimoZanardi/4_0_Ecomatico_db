SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION [dbo].[ufnSedi_get_AziendeByUtente_List] (
	@IdUtente CHAR(16),
	@IdAziendaInterna CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	-- Aziende radice (IdTipo = 'L', IdParent NULL) della IdAziendaInterna indicata,
	-- sia interne (l'azienda interna stessa) sia esterne (clienti/fornitori/terzi
	-- registrati sotto la stessa azienda interna, es. per studi di consulenza che
	-- inviano MUD per conto dei propri assistiti)
	SELECT
		s.Id,
		s.Nome,
		s.IndirizzoCompleto,
		s.InternaEsterna,
		s.Disabilitata
	FROM
		dbo.tblSedi s
	WHERE
		s.IdParent IS NULL
		AND s.IdTipo = 'L'
		AND s.IdAziendaInterna = @IdAziendaInterna
		AND s.Lock = 0
		AND EXISTS (
			SELECT 1
			FROM dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) i
			WHERE i.Id = @IdAziendaInterna
		)
);
GO
