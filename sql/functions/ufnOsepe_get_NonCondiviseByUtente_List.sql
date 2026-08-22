

CREATE FUNCTION [dbo].[ufnOsepe_get_NonCondiviseByUtente_List] (
    @IdUtente CHAR(16))
RETURNS @result TABLE (
    Id                 CHAR(16)     NOT NULL,
    Tipo               CHAR(1)      NOT NULL,
    IdSede             CHAR(16)     NULL,
    IdDominio          CHAR(16)     NULL,
    Disabilitata       BIT          NOT NULL,
    [Text]             VARCHAR(401) NOT NULL,  
    ImpiegabileServizi BIT          NOT NULL
)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @i dbo.tvpAziendeInterneByUtente;

    INSERT @i (Id, IdDominio)
    SELECT Id, IdDominio
    FROM dbo.ufnSedi_get_AziendeInterneByUtente_List(@IdUtente);

    -- Ramo 1: sedi esterne non condivise
    INSERT @result (Id, Tipo, IdSede, IdDominio, Disabilitata, [Text], ImpiegabileServizi)
    SELECT
        i.Id,
        Tipo               = 'S',
        IdSede             = s.IdAziendaInterna,
        i.IdDominio,
        s.Disabilitata,
        [Text]             = s.NomeCompleto + ' ' + s.IndirizzoCompleto,
        ImpiegabileServizi = CAST(0 AS BIT)
    FROM
        dbo.ufnSedi_get_SediEsterneNonCondiviseByUtente_List(@i) i
        INNER JOIN dbo.tblSedi s ON i.Id = s.Id
    WHERE s.Lock = 0;

    -- Ramo 2: persone non condivise
    INSERT @result (Id, Tipo, IdSede, IdDominio, Disabilitata, [Text], ImpiegabileServizi)
    SELECT
        i.Id,
        Tipo               = 'P',
        IdSede             = i.IdSede,
        i.IdDominio,
        s.Disabilitata,
        [Text]             = s.NomeCompleto,
        s.ImpiegabileServizi
    FROM
        dbo.ufnPersone_get_NonCondiviseByUtente_List(@IdUtente) i
        INNER JOIN dbo.tblPersone s ON i.Id = s.Id
    WHERE s.Lock = 0;

    -- Ramo 3: oggetti non condivisi
    INSERT @result (Id, Tipo, IdSede, IdDominio, Disabilitata, [Text], ImpiegabileServizi)
    SELECT
        i.Id,
        Tipo               = 'O',
        IdSede             = i.IdSede,
        i.IdDominio,
        s.Disabilitata,
        [Text]             = s.Nome,
        s.ImpiegabileServizi
    FROM
        dbo.ufnOggetti_get_NonCondivisiByUtente_List(@IdUtente) i
        INNER JOIN dbo.tblOggetti s ON i.Id = s.Id
    WHERE s.Lock = 0;

    RETURN;
END;
