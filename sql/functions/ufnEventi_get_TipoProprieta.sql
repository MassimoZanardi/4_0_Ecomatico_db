SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
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
			-- Numero salvato con il punto, nella scheda con la virgola
			Valore = CASE p.IdTipoDato
				WHEN 'B' THEN ISNULL(e.Valore, 'false')
				WHEN 'I' THEN REPLACE(ISNULL(e.Valore, ''), '.', ',')
				ELSE ISNULL(e.Valore, '')
			END
		FROM
			dbo.tblTipiProprieta t
			INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
			LEFT JOIN dbo.tblEventiProprieta e ON t.IdProprieta = e.IdProprieta
											   AND e.Id = @Id
		WHERE
			t.Id = @IdTipo
			AND t.Lock = 0
		ORDER BY
			t.Pos
		FOR JSON PATH
	);
END;
