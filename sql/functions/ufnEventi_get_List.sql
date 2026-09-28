SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[ufnEventi_get_List] (
	@DallaData SMALLDATETIME,
	@AllaData SMALLDATETIME,
	@IdCalendario tvpId_char_16 READONLY,
	@IdTipo tvpId_char_1 READONLY)
RETURNS TABLE
-- WITH SCHEMABINDING non applicabile: dipende da TVP (tvpId_char_16, tvpId_char_1)
-- che non sono oggetti schema-bound
AS
RETURN
(
	WITH cteEventi AS (
		SELECT
			e.Id,
			e.IdTipo,
			e.IdCalendario,
			c.IdSede,
			s.IdAziendaInterna,
			e.IdStato,
			Stato = t.Nome,
			e.[Data],
			e.InGiornata,
			-- Ricorre: true se esiste una riga in tblRicorrenze
			Ricorre = CAST(IIF(r.Id IS NULL, 0, 1) AS BIT),
			e.AvvisoAnticipo,
			-- Avviso: true se e' stato impostato un anticipo
			Avviso = CAST(IIF(e.AvvisoAnticipo IS NULL, 0, 1) AS BIT),
			AvvisoTesto = e.Avviso,
			e.Etichette,
			e.Email,
			r.IdIntervallo,
			r.Frequenza,
			r.DataFine,
			r.Ripetizioni,
			r.Relativo,
			-- Eccezione: true se l'evento ricorrente ha almeno un'eccezione attiva
			Eccezione = CAST(IIF(z.Id IS NULL, 0, 1) AS BIT),
			IdEventoEccezione = z.IdEvento,
			IdEccezione = z.Id,
			e.Lock,
			-- NumberMax: numero massimo di occorrenze da generare con GENERATE_SERIES.
			-- FIX: limitato al minimo tra il valore "originale" (DataFine/
			-- Ripetizioni) e il numero di occorrenze sufficienti a coprire
			-- @AllaData, cosi' GENERATE_SERIES non genera oltre il necessario
			-- per la finestra richiesta da QUESTA query. Un solo DATEDIFF
			-- (parametrizzato per unita' tramite il CASE, che e' l'unica
			-- parte che deve necessariamente variare per intervallo, dato
			-- che DATEDIFF non accetta l'unita' come variabile in T-SQL),
			-- poi si deriva sia il valore originale sia quello di finestra.
			NumberMax = IIF(r.Id IS NULL, 0,
				IIF(nm.NumberMaxOriginale <= nm.NumberMaxFinestra,
					nm.NumberMaxOriginale,
					nm.NumberMaxFinestra))
		FROM
			dbo.tblEventi e
			INNER JOIN dbo.tblEventiStati t ON e.IdStato = t.Id
			INNER JOIN dbo.tblCalendari c ON e.IdCalendario = c.Id
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			-- Ricorrenza: NULL per eventi singoli
			LEFT JOIN dbo.tblRicorrenze r ON e.Id = r.Id
			-- Eccezione: cerca le eccezioni dell'evento originale (z.Id = evento originale)
			LEFT JOIN dbo.tblRicorrenzeEccezioni z ON e.Id = z.Id
													AND z.Lock = 0
			-- FIX NumberMax: calcola una sola volta il DATEDIFF nell'unita'
			-- corretta, poi deriva da esso sia il NumberMax originale sia
			-- quello di finestra
			OUTER APPLY (
				SELECT Diff = CASE r.IdIntervallo
					WHEN 'DD' THEN DATEDIFF(DAY, e.[Data], @AllaData)
					WHEN 'WK' THEN DATEDIFF(WEEK, e.[Data], @AllaData)
					WHEN 'MM' THEN DATEDIFF(MONTH, e.[Data], @AllaData)
					WHEN 'YY' THEN DATEDIFF(YEAR, e.[Data], @AllaData)
					ELSE 0
				END
			) d
			OUTER APPLY (
				SELECT
					NumberMaxOriginale = IIF(r.Id IS NULL, 0,
						dbo.ufnEventi_get_NumberMax(e.[Data], r.DataFine, r.IdIntervallo, r.Frequenza, r.Ripetizioni)),
					NumberMaxFinestra = IIF(r.Id IS NULL OR r.Frequenza IS NULL OR r.Frequenza <= 0, 0,
						d.Diff / r.Frequenza)
			) nm
		WHERE
			e.IdCalendario IN (SELECT Id FROM @IdCalendario)
			AND e.IdTipo IN (SELECT Id FROM @IdTipo)
			AND
				(
				r.DataFine IS NULL
				OR r.DataFine >= @DallaData
				)
			AND e.Lock = 0
	)
	SELECT
		t.*,
		AvvisoData = DATEADD(MINUTE, t.AvvisoAnticipo * -1, t.[Data])
	FROM (
		-- Ramo 1: eventi non ricorrenti
		SELECT
			e.Id, e.IdCalendario, e.IdStato, e.Stato, e.IdTipo,
			e.[Data], e.InGiornata, e.Avviso, e.AvvisoTesto, e.AvvisoAnticipo,
			e.Etichette, e.Ricorre, e.Eccezione, e.IdEccezione
		FROM cteEventi e
		WHERE e.Ricorre = 0
		UNION ALL -- rami mutualmente esclusivi per Ricorre + IdIntervallo + Relativo

		-- Ramo 2: ricorrenti ogni N giorni
		SELECT
			e.Id, e.IdCalendario, e.IdStato, e.Stato, e.IdTipo,
			[Data] = DATEADD(DAY, n.Number * e.Frequenza, e.[Data]),
			e.InGiornata, e.Avviso, e.AvvisoTesto, e.AvvisoAnticipo,
			e.Etichette, e.Ricorre, e.Eccezione, e.IdEccezione
		FROM cteEventi e
		CROSS APPLY (SELECT Number = [value]
			 FROM GENERATE_SERIES(0, e.NumberMax, 1)) n
		WHERE
			e.Ricorre = 1
			AND e.IdIntervallo = 'DD'
		UNION ALL

		-- Ramo 3: ricorrenti ogni N settimane
		SELECT
			e.Id, e.IdCalendario, e.IdStato, e.Stato, e.IdTipo,
			[Data] = DATEADD(WEEK, n.Number * e.Frequenza, e.[Data]),
			e.InGiornata, e.Avviso, e.AvvisoTesto, e.AvvisoAnticipo,
			e.Etichette, e.Ricorre, e.Eccezione, e.IdEccezione
		FROM cteEventi e
		CROSS APPLY (SELECT Number = [value]
			 FROM GENERATE_SERIES(0, e.NumberMax, 1)) n
		WHERE
			e.Ricorre = 1
			AND e.IdIntervallo = 'WK'
		UNION ALL

		-- Ramo 4: ricorrenti ogni N mesi (giorno fisso)
		SELECT
			e.Id, e.IdCalendario, e.IdStato, e.Stato, e.IdTipo,
			[Data] = DATEADD(MONTH, n.Number * e.Frequenza, e.[Data]),
			e.InGiornata, e.Avviso, e.AvvisoTesto, e.AvvisoAnticipo,
			e.Etichette, e.Ricorre, e.Eccezione, e.IdEccezione
		FROM cteEventi e
		CROSS APPLY (SELECT Number = [value]
			 FROM GENERATE_SERIES(0, e.NumberMax, 1)) n
		WHERE
			e.Ricorre = 1
			AND e.IdIntervallo = 'MM'
			AND e.Relativo = 0
		UNION ALL

		-- Ramo 5: ricorrenti ogni N mesi (giorno relativo es. "terzo lunedì del mese")
		SELECT
			t.Id, t.IdCalendario, t.IdStato, t.Stato, t.IdTipo,
			t.[Data], t.InGiornata, t.Avviso, t.AvvisoTesto, t.AvvisoAnticipo,
			t.Etichette, t.Ricorre, t.Eccezione, t.IdEccezione
		FROM (
			SELECT
				e.Id, e.IdCalendario, e.IdStato, e.Stato, e.IdTipo,
				[Data] = dbo.ufnDate_get_GiornoDelMeseRelativo(
							 e.[Data],
							 DATEADD(MONTH, n.Number * e.Frequenza, e.[Data]),
							 e.Relativo),
				e.InGiornata, e.Avviso, e.AvvisoTesto, e.AvvisoAnticipo,
				e.Etichette, e.Ricorre, e.Eccezione, e.IdEccezione,
				e.DataFine
			FROM cteEventi e
			CROSS APPLY (SELECT Number = [value]
				 FROM GENERATE_SERIES(0, e.NumberMax, 1)) n
			WHERE
				e.Ricorre = 1
				AND e.IdIntervallo = 'MM'
				AND e.Relativo > 0
		) t
		WHERE t.[Data] < t.DataFine
		UNION ALL

		-- Ramo 6: ricorrenti ogni N anni
		SELECT
			e.Id, e.IdCalendario, e.IdStato, e.Stato, e.IdTipo,
			[Data] = DATEADD(YEAR, n.Number * e.Frequenza, e.[Data]),
			e.InGiornata, e.Avviso, e.AvvisoTesto, e.AvvisoAnticipo,
			e.Etichette, e.Ricorre, e.Eccezione, e.IdEccezione
		FROM cteEventi e
		CROSS APPLY (SELECT Number = [value]
			 FROM GENERATE_SERIES(0, e.NumberMax, 1)) n
		WHERE
			e.Ricorre = 1
			AND e.IdIntervallo = 'YY'
	) t
	-- Esclude le date per cui esiste un'eccezione di ricorrenza attiva
		LEFT JOIN dbo.tblRicorrenzeEccezioni x
		ON t.Id = x.Id
		AND t.[Data] = x.[Data]
		AND x.Lock = 0
	WHERE
		x.Id IS NULL
		AND t.[Data] BETWEEN @DallaData AND @AllaData
);