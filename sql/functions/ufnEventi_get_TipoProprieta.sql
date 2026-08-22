CREATE FUNCTION [dbo].[ufnEventi_get_TipoProprieta]
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
			Valore = IIF(p.IdTipoDato = 'B',
							ISNULL(e.Valore, 'false'),
							ISNULL(e.Valore, ''))
		FROM
			dbo.tblTipiProprieta t
			INNER JOIN dbo.tblProprieta p ON t.IdProprieta = p.Id
			LEFT JOIN dbo.tblEventiProprieta e ON t.IdProprieta = e.IdProprieta
											   AND e.Id = @Id
		WHERE t.Id = @IdTipo
		ORDER BY
			t.Pos
		FOR JSON PATH
	);
END;
