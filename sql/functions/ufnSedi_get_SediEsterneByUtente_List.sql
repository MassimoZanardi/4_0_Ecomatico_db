
CREATE FUNCTION [dbo].[ufnSedi_get_SediEsterneByUtente_List] (
    @IdUtente CHAR(16))
RETURNS @result TABLE (
    Id               CHAR(16) NOT NULL,
    IdParent         CHAR(16) NULL,
    IdAziendaInterna CHAR(16) NULL,
    IdDominio        CHAR(16) NULL,
    Disabilitata     BIT      NOT NULL,
    Condivisa        BIT      NOT NULL,
    Pos              INT      NOT NULL
)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @i dbo.tvpAziendeInterneByUtente;

    INSERT @i (Id, IdDominio)
    SELECT Id, IdDominio
    FROM dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente);

    -- Ramo 1: sedi esterne CONDIVISE (Pos = 0 → precedenza nelle query con ORDER BY Pos)
    INSERT @result (Id, IdParent, IdAziendaInterna, IdDominio, Disabilitata, Condivisa, Pos)
    SELECT
        Id,
        IdParent,
        IdAziendaInterna,
        IdDominio,
        Disabilitata,
        Condivisa = CAST(1 AS BIT),
        Pos       = 0
    FROM dbo.ufnSedi_get_SediEsterneCondiviseByUtente_List(@i);

    -- Ramo 2: sedi esterne NON condivise (Pos = 1 → priorità inferiore)
    INSERT @result (Id, IdParent, IdAziendaInterna, IdDominio, Disabilitata, Condivisa, Pos)
    SELECT
        Id,
        IdParent,
        IdAziendaInterna,
        IdDominio,
        Disabilitata,
        Condivisa = CAST(0 AS BIT),
        Pos       = 1
    FROM dbo.ufnSedi_get_SediEsterneNonCondiviseByUtente_List(@i);

    RETURN;
END;
