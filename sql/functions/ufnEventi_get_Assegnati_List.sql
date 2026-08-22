CREATE FUNCTION [dbo].[ufnEventi_get_Assegnati_List] (
	@DallaData SMALLDATETIME,
	@AllaData SMALLDATETIME,
	@IdUtente CHAR(16),
	@IdCalendario tvpId_char_16 READONLY)
RETURNS TABLE
AS
RETURN
(
	SELECT
		e.Id,
		e.IdCalendario,
		e.IdStato,
		Stato = t.Nome,
		e.IdTipo,
		e.[Data],
		e.InGiornata,
		AvvisoTesto = e.Avviso,
		Avviso = CAST(IIF(e.AvvisoAnticipo IS NULL, 0, 1) AS BIT),
		e.AvvisoAnticipo,
		AvvisoData = DATEADD(MINUTE, e.AvvisoAnticipo * -1, e.[Data])
	FROM
		dbo.tblEventiUtenti u
		INNER JOIN dbo.tblEventi e ON u.Id = e.Id
		INNER JOIN dbo.tblEventiStati t ON e.IdStato = t.Id
		-- Ricorrenza: NULL per eventi singoli
		LEFT JOIN dbo.tblRicorrenze r ON e.Id = r.Id
		-- Eccezione di ricorrenza attiva
		LEFT JOIN dbo.tblRicorrenzeEccezioni z ON e.Id = z.IdEvento
											   AND z.Lock = 0
	WHERE
		u.IdUtente = @IdUtente
		AND e.IdCalendario IN (SELECT Id FROM @IdCalendario)
		AND e.IdTipo = 'V'
		AND e.[Data] BETWEEN @DallaData AND @AllaData
		-- Ricorre = 0: evento singolo; Eccezione = 1: occorrenza modificata
		AND (r.Id IS NULL OR z.IdEvento IS NOT NULL)
		AND e.Lock = 0
);
