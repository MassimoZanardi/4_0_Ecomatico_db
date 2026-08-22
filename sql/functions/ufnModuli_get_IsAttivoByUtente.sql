CREATE FUNCTION [dbo].[ufnModuli_get_IsAttivoByUtente]
(
	@Id CHAR(3),
	@IdUtente CHAR(16)
)
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
	RETURN IIF(
		EXISTS (
			SELECT 1
			FROM dbo.tblUtenti u
			INNER JOIN dbo.tblDominiModuli m ON u.IdDominio = m.Id
			WHERE
				u.Id = @IdUtente
				AND m.IdModulo = @Id
		), 1, 0);
END;
