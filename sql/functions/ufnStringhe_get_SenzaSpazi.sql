CREATE OR ALTER FUNCTION [dbo].[ufnStringhe_get_SenzaSpazi]
(
	@str VARCHAR(8000),
	@len INT = 0, -- 0 = nessun troncamento
	@nullIfEmpty BIT = 1 -- 1 = restituisce NULL per stringa vuota
											-- 0 = restituisce '' per stringa vuota
)
RETURNS VARCHAR(8000)
AS
BEGIN
	/*
     * Normalizza una stringa:
     *   1. Collassa sequenze di spazi multipli in un singolo spazio (senza loop).
     *   2. Rimuove spazi iniziali e finali (LTRIM/RTRIM).
     *   3. Restituisce NULL (o '') se la stringa risultante è vuota.
     *   4. Tronca opzionalmente al limite @len.
     */

	-- Gestione esplicita NULL in ingresso
	IF @str IS NULL
		RETURN NULL;

	-- Tecnica: inserisce un marcatore (CHAR(1), non stampabile) per
	-- identificare i doppi spazi, poi rimuove il ridondante.
	-- Ripetuto due volte per coprire sequenze dispari di spazi (es. 3, 5...).
	SET @str = REPLACE(REPLACE(REPLACE(@str,
					SPACE(2), SPACE(1) + CHAR(1)),
					CHAR(1) + SPACE(1), ''),
					CHAR(1), '');

	SET @str = REPLACE(REPLACE(REPLACE(@str,
					SPACE(2), SPACE(1) + CHAR(1)),
					CHAR(1) + SPACE(1), ''),
					CHAR(1), '');

	-- Rimozione spazi iniziali e finali
	SET @str = LTRIM(RTRIM(@str));

	-- Gestione stringa vuota
	IF LEN(@str) = 0
		RETURN CASE WHEN @nullIfEmpty = 1 THEN NULL ELSE '' END;

	-- Troncamento opzionale
	IF @len > 0 AND LEN(@str) > @len
		SET @str = LEFT(@str, @len);

	RETURN @str;

END;
