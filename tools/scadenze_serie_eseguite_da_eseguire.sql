-- Scadenze ricorrenti: la serie non si esegue (S5.9, decisione dell'utente del 2026-11-24). Le occorrenze generate
-- hanno lo stato della serie: una serie segnata Eseguito rendeva eseguite anche le occorrenze future. La nuova regola
-- vale dai salvataggi successivi (uspScadenze_upd); questo script riporta a Da eseguire le serie gia' segnate Eseguito
-- (decisione dell'utente: le occorrenze passate tornano scadute e si segnano eseguite con la sola occorrenza o con
-- Segna eseguiti). Restano come sono le serie Annullate (annullare tutta la serie e' ammesso, come nei servizi) e le
-- occorrenze modificate, che sono scadenze a se'. Rieseguibile.
-- Eseguito su dev il 2026-11-24 (nessuna serie). NON ancora eseguito in produzione.

SET NOCOUNT ON;

-- Prima: le serie che cambiano
SELECT
	Dominio = d.Nome,
	Calendario = c.Nome,
	SerieDal = e.[Data],
	Descrizione = e.Avviso,
	e.Id
FROM
	dbo.tblScadenze s
	INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
	INNER JOIN dbo.tblRicorrenze r ON r.Id = e.Id
	INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
	INNER JOIN dbo.tblSedi sd ON c.IdSede = sd.Id
	INNER JOIN dbo.tblSediInterne i ON sd.IdAziendaInterna = i.Id
	INNER JOIN dbo.tblDomini d ON i.IdDominio = d.Id
WHERE
	e.IdStato = 'E'
	AND e.Lock = 0
	AND NOT EXISTS (SELECT 1 FROM dbo.tblRicorrenzeEccezioni x WHERE x.IdEvento = e.Id)
ORDER BY d.Nome, c.Nome, e.[Data];

UPDATE e
SET IdStato = 'D'
FROM
	dbo.tblScadenze s
	INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
	INNER JOIN dbo.tblRicorrenze r ON r.Id = e.Id
WHERE
	e.IdStato = 'E'
	AND e.Lock = 0
	AND NOT EXISTS (SELECT 1 FROM dbo.tblRicorrenzeEccezioni x WHERE x.IdEvento = e.Id);

SELECT SerieRiportateDaEseguire = @@ROWCOUNT;
GO
