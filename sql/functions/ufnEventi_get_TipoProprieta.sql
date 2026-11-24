SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Campi aggiuntivi del tipo con i valori dell'evento @Id, come JSON per la scheda della scadenza, del servizio e del
-- servizio assegnato (_TipoProprietaPartial). Un campo disattivato (S3.8) c'e' solo se ha un valore (una casella si/no
-- solo se spuntata) e la scheda lo mostra in sola lettura. Per l'Elenco a scelta (S3.7) Voci sono le voci dell'elenco,
-- una per riga, nell'ordine.
CREATE OR ALTER FUNCTION [dbo].[ufnEventi_get_TipoProprieta]
(
	@Id CHAR(16),
	@IdTipo CHAR(16)
)
RETURNS NVARCHAR(MAX)
WITH SCHEMABINDING
AS
BEGIN
	RETURN (
		SELECT
			Id = t.IdProprieta,
			p.IdTipoDato,
			Nome = t.Nome,
			-- Campo obbligatorio per segnare come eseguito (S3.6): la scheda mette l'asterisco
			t.Obbligatorio,
			t.Attivo,
			-- Numero salvato con il punto, nella scheda con la virgola
			Valore = CASE p.IdTipoDato
				WHEN 'B' THEN ISNULL(e.Valore, 'false')
				WHEN 'I' THEN REPLACE(ISNULL(e.Valore, ''), '.', ',')
				ELSE ISNULL(e.Valore, '')
			END,
			Voci = (
				SELECT STRING_AGG(CAST(o.Nome AS NVARCHAR(MAX)), NCHAR(10)) WITHIN GROUP (ORDER BY o.Pos)
				FROM dbo.tblTipiProprietaVoci o
				WHERE
					o.Id = t.Id
					AND o.IdProprieta = t.IdProprieta
					AND p.IdTipoDato = 'L'
			)
		FROM
			dbo.tblTipiProprieta t
			INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
			LEFT JOIN dbo.tblEventiProprieta e ON t.IdProprieta = e.IdProprieta
											   AND e.Id = @Id
		WHERE
			t.Id = @IdTipo
			AND t.Lock = 0
			AND
				(
				t.Attivo = 1
				OR (NULLIF(LTRIM(RTRIM(e.Valore)), '') IS NOT NULL AND NOT (p.IdTipoDato = 'B' AND e.Valore <> 'true'))
				)
		ORDER BY
			t.Pos
		FOR JSON PATH
	);
END;
GO
