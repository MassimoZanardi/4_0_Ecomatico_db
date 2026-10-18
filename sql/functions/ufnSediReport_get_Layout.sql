SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Layout di stampa (DDT e fatture) di un'azienda interna, sempre una riga: se il layout non è ancora stato
-- salvato valgono i valori predefiniti (come nella 3.2: layout 11, testo nero 10 pt, intestazione a sinistra e piè
-- di pagina al centro). Unica fonte dei valori predefiniti per la pagina Impostazioni > Report layout e per le stampe
CREATE OR ALTER FUNCTION dbo.ufnSediReport_get_Layout (@IdAzienda CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		IdLayout = ISNULL(r.IdLayout, '11'),
		Intestazione = ISNULL(r.Intestazione, ''),
		PiePagina = ISNULL(r.Piepagina, ''),
		IntestazioneColore = ISNULL(r.IntestazioneColore, 'Black'),
		IntestazioneFontSize = ISNULL(r.IntestazioneFontSize, '10pt'),
		IntestazioneAllineamento = ISNULL(r.IntestazioneAllineamento, 'Left'),
		PiePaginaColore = ISNULL(r.PiepaginaColore, 'Black'),
		PiePaginaFontSize = ISNULL(r.PiepaginaFontSize, '10pt'),
		PiePaginaAllineamento = ISNULL(r.PiepaginaAllineamento, 'Center'),
		r.Logo
	FROM
		(SELECT Id = @IdAzienda) a
		LEFT JOIN dbo.tblSediReport r ON a.Id = r.Id
);
GO
