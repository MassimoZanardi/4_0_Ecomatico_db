-- Verifica di tutto il DB (SP, funzioni, viste, trigger): da eseguire DOPO OGNI deploy di SP/viste/funzioni,
-- in dev e in produzione. Deve restituire 0 righe.
--   bare_lf / bare_cr : fine riga non CRLF (il file deployato non era normalizzato CRLF)
--   fffd / mojibake   : accenti corrotti (file senza BOM letto come ANSI, oppure sqlcmd senza -f 65001)
--   qi = 0            : QUOTED_IDENTIFIER OFF (header SET ANSI_NULLS/QUOTED_IDENTIFIER mancante)
-- Esecuzione: sqlcmd -S <server> -d 4_0_ecomatico -E -f 65001 -W -s "|" -i tools\verifica_crlf_accenti.sql
SET NOCOUNT ON;
SELECT
	o.name,
	o.type,
	bare_lf = LEN(REPLACE(m.definition, CHAR(13) + CHAR(10), '')) - LEN(REPLACE(REPLACE(m.definition, CHAR(13) + CHAR(10), ''), CHAR(10), '')),
	bare_cr = LEN(REPLACE(m.definition, CHAR(13) + CHAR(10), '')) - LEN(REPLACE(REPLACE(m.definition, CHAR(13) + CHAR(10), ''), CHAR(13), '')),
	fffd = CHARINDEX(NCHAR(65533), m.definition COLLATE Latin1_General_BIN2),
	mojibake = PATINDEX(N'%' + NCHAR(195) + N'[' + NCHAR(160) + N'-' + NCHAR(191) + N']%', m.definition COLLATE Latin1_General_BIN2),
	qi = m.uses_quoted_identifier,
	modificato = CONVERT(VARCHAR(16), o.modify_date, 120)
FROM
	sys.sql_modules m
	INNER JOIN sys.objects o ON m.object_id = o.object_id
WHERE
	LEN(REPLACE(m.definition, CHAR(13) + CHAR(10), '')) - LEN(REPLACE(REPLACE(m.definition, CHAR(13) + CHAR(10), ''), CHAR(10), '')) > 0
	OR LEN(REPLACE(m.definition, CHAR(13) + CHAR(10), '')) - LEN(REPLACE(REPLACE(m.definition, CHAR(13) + CHAR(10), ''), CHAR(13), '')) > 0
	OR CHARINDEX(NCHAR(65533), m.definition COLLATE Latin1_General_BIN2) > 0
	OR PATINDEX(N'%' + NCHAR(195) + N'[' + NCHAR(160) + N'-' + NCHAR(191) + N']%', m.definition COLLATE Latin1_General_BIN2) > 0
	OR m.uses_quoted_identifier = 0
ORDER BY o.modify_date DESC;
