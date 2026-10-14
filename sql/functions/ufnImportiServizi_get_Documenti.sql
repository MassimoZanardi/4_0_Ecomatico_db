SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti, servizi: i servizi che la fatturazione considera. Il documento fatturabile è il servizio:
-- Id è l'Id del servizio (chiave di tblFattureDocumenti), IdEvento quello del suo evento nel calendario.
--   @Id: un solo servizio; altrimenti i servizi dell'azienda @IdAzienda (calendari delle sue sedi interne) con la
--        data dell'evento tra @DataDa e @DataA. Due rami distinti, ciascuno con il suo accesso (come
--        ufnImportiMagazzino_get_Documenti).
-- IsFatturabile: il servizio non è una serie ricorrente (nessuna riga in tblRicorrenze per il suo evento). La serie
-- è solo pianificazione: si esegue e si fattura la singola occorrenza modificata, che è un servizio a sé (regola
-- O5S.1). IsEseguito: stato Eseguito; senza, il servizio non viene fatturato.
-- Lock: quello dell'evento (0 confermato, 2 bozza, 4 cancellato).
-- IdSedeInterna: sede interna del calendario che ospita il servizio (variabile "Sede interna" degli importi).
-- Richiedente: IdRichiedente è la sede indicata sul servizio, IdRichiedenteParent il suo soggetto.
CREATE OR ALTER FUNCTION dbo.ufnImportiServizi_get_Documenti (
	@Id CHAR(16),
	@IdAzienda CHAR(16),
	@DataDa DATE,
	@DataA DATE)
RETURNS TABLE
AS
RETURN
(
	WITH ids AS (
		SELECT s.Id
		FROM dbo.tblServizi s
		WHERE s.Id = @Id

		UNION ALL

		SELECT s.Id
		FROM
			dbo.tblSedi si
			INNER JOIN dbo.tblCalendari c ON si.Id = c.IdSede
										   AND c.IdModulo = 'SRV'
			INNER JOIN dbo.tblEventi e ON c.Id = e.IdCalendario
			INNER JOIN dbo.tblServizi s ON e.Id = s.IdEvento
		WHERE
			@Id IS NULL
			AND si.IdAziendaInterna = @IdAzienda
			AND si.InternaEsterna = 'I'
			AND e.[Data] >= @DataDa
			AND e.[Data] < DATEADD(DAY, 1, CAST(@DataA AS DATETIME))
	)
	SELECT
		s.Id,
		s.IdEvento,
		[Data] = CAST(e.[Data] AS DATE),
		Lock = CAST(ISNULL(e.Lock, 0) AS TINYINT),
		IdAzienda = si.IdAziendaInterna,
		IdSedeInterna = c.IdSede,
		IsFatturabile = CAST(IIF(r.Id IS NULL, 1, 0) AS BIT),
		IsEseguito = CAST(IIF(e.IdStato = 'E', 1, 0) AS BIT),
		s.IdTipo,
		s.IdRichiedente,
		IdRichiedenteParent = ISNULL(sr.IdParent, sr.Id)
	FROM
		ids k
		INNER JOIN dbo.tblServizi s ON k.Id = s.Id
		INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
		INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
		INNER JOIN dbo.tblSedi si ON c.IdSede = si.Id
		LEFT JOIN dbo.tblRicorrenze r ON e.Id = r.Id
		LEFT JOIN dbo.tblSedi sr ON s.IdRichiedente = sr.Id
);
GO
