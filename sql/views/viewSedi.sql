

CREATE   VIEW [dbo].[viewSedi]
WITH SCHEMABINDING
AS
SELECT
    s.Id,
    s.IdParent,
    s.IdAziendaInterna,
    IdDominio        = ai.IdDominio,
    s.IdTipo,
    s.InternaEsterna,
    s.Nome,
    s.Cognome,
    s.PartitaIva,
    s.CodiceFiscale,
    s.IndirizzoCompleto,
    s.NomeCompleto,
    s.Note,
    IdIndirizzo      = i.Id,
    i.IdComune,
    i.IdNazione,
    i.CAP,
    i.Indirizzo,
	i.NumeroCivico,
    i.Localita,
    Comune           = IIF(i.IdNazione = '380', c.Nome, n.Nome),
    Provincia        = IIF(i.IdNazione = '380', v.Nome, i.Localita),
    Nazione          = n.Nome,
    NazioneSigla     = n.Sigla,
    NazioneSigla3    = n.Sigla3,
    s.Disabilitata,
    s.Lock
FROM
    dbo.tblSedi           s
    LEFT JOIN dbo.tblSediIndirizzi si ON s.Id               = si.Id
    LEFT JOIN dbo.tblIndirizzi     i  ON si.IdIndirizzo     = i.Id
    LEFT JOIN dbo.tblComuni        c  ON i.IdComune         = c.Id
    LEFT JOIN dbo.tblNazioni       n  ON i.IdNazione        = n.Id
    LEFT JOIN dbo.tblProvince      v  ON c.IdProvincia      = v.Id
    LEFT JOIN dbo.tblSediInterne   ai ON s.IdAziendaInterna = ai.Id;

