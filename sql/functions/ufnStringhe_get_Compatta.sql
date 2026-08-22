CREATE OR ALTER FUNCTION [dbo].[ufnStringhe_get_Compatta]
(
	@str VARCHAR(4000),
	@len INT = 0,
	@suffix VARCHAR(10) = '...'
)
RETURNS VARCHAR(4000)
AS
BEGIN
	IF @str IS NULL
		RETURN NULL;

	IF @len = 0 OR LEN(@str) <= @len
		RETURN @str;

	IF @len <= LEN(@suffix)
		RETURN LEFT(@suffix, @len);

	RETURN RTRIM(LEFT(@str, @len - LEN(@suffix))) + @suffix;
END;
