CREATE FUNCTION [dbo].[ufnUtenti_get_IsAdmin]
(
	@IdSessione CHAR(16))
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
	DECLARE @rtn INT
	IF EXISTS (SELECT 1
		FROM
			dbo.tblUtenti u
		INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
		INNER JOIN dbo.tblSessioni s ON u.Id = s.IdUtente
		WHERE
			s.Id = @IdSessione
			AND d.[Master] = 1
			AND u.Lock = 0
	)
		SET @rtn = 2
	ELSE IF EXISTS (SELECT 1
		FROM
			dbo.tblUtenti u INNER JOIN
			dbo.tblSessioni s ON u.Id = s.IdUtente
		WHERE
			s.Id = @IdSessione
			AND u.IdRuolo = 'AD'
			AND u.Lock = 0
	)
		SET @rtn = 1
	ELSE
		SET @rtn = 0

	RETURN @rtn
END
