
CREATE   FUNCTION [dbo].[ufnOggetti_get_CondivisiByUtente_List] (
    @IdUtente CHAR(16))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    -- GROUP BY su s.Id per deduplicare: lo stesso oggetto può apparire più volte
    -- se associato a più aree o se più sedi interne appartengono alla stessa area
    SELECT
        s.Id,
        s.IdSede,
        IdDominio = MIN(ui.IdDominio),
        IdArea    = MIN(a.Id),
        Area      = MIN(a.Nome)
    FROM
        dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente) ui
        INNER JOIN dbo.tblAreeSediInterne ai ON ui.Id      = ai.IdSede
        INNER JOIN dbo.tblAree            a  ON ai.Id      = a.Id
        INNER JOIN dbo.tblAreeOsepe       ae ON a.Id       = ae.Id
        INNER JOIN dbo.tblOggetti         s  ON ae.IdOsepe = s.Id
    WHERE
        a.Lock = 0
        AND s.Lock = 0
    GROUP BY s.Id, s.IdSede
);
