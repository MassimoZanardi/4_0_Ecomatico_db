-- Confronta lo schema di due database sullo stesso server: serve a verificare che un database ricostruito dal
-- repo (ricostruisci_database.ps1) sia uguale a quello di riferimento. Deve dare 0 righe.
-- Uso: sqlcmd -S SERVER -E -f 65001 -W -s "|" -v A="4_0_ecomatico" B="4_0_ecomatico_nuovo" -i confronta_schema.sql
-- Confronta: tabelle e colonne (tipo, lunghezza, precisione, null, identity, collation), chiavi primarie, vincoli
-- unici e indici (colonne, colonne incluse, filtro), chiavi esterne (colonne, tabella di destinazione, regole),
-- tipi tabella con le loro colonne, e il testo di SP, funzioni e viste (senza differenze di soli spazi e a capo).
-- Colonna Dove: A = presente o diverso solo nel primo database, B = solo nel secondo.
SET NOCOUNT ON;
GO
DROP TABLE IF EXISTS #schema;
CREATE TABLE #schema (
	Db CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL,
	Tipo VARCHAR(60) COLLATE DATABASE_DEFAULT NOT NULL,
	Nome NVARCHAR(400) COLLATE DATABASE_DEFAULT NOT NULL,
	Definizione NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL
);
GO
DECLARE @sql NVARCHAR(MAX) = N'
USE [?DB?];
INSERT #schema (Db, Tipo, Nome, Definizione)
SELECT ''?L?'', ''Colonna'', t.name + ''.'' + c.name,
	TYPE_NAME(c.user_type_id) + ''|'' + CAST(c.max_length AS VARCHAR(10)) + ''|'' + CAST(c.precision AS VARCHAR(10)) + ''|'' + CAST(c.scale AS VARCHAR(10))
	+ ''|null='' + CAST(c.is_nullable AS VARCHAR(1)) + ''|identity='' + CAST(c.is_identity AS VARCHAR(1)) + ''|'' + ISNULL(c.collation_name, '''') + ''|pos='' + CAST(ROW_NUMBER() OVER (PARTITION BY c.object_id ORDER BY c.column_id) AS VARCHAR(10))
FROM sys.tables t INNER JOIN sys.columns c ON t.object_id = c.object_id
WHERE t.is_ms_shipped = 0 AND t.name <> ''sysdiagrams'';

INSERT #schema (Db, Tipo, Nome, Definizione)
SELECT ''?L?'', ''Indice'', t.name + ''.'' + i.name,
	i.type_desc + ''|pk='' + CAST(i.is_primary_key AS VARCHAR(1)) + ''|unico='' + CAST(i.is_unique AS VARCHAR(1)) + ''|vincolo='' + CAST(i.is_unique_constraint AS VARCHAR(1))
	+ ''|colonne='' + ISNULL(STUFF((SELECT '','' + c.name + IIF(ic.is_descending_key = 1, '' DESC'', '''') FROM sys.index_columns ic INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0 ORDER BY ic.key_ordinal FOR XML PATH('''')), 1, 1, ''''), '''')
	+ ''|incluse='' + ISNULL(STUFF((SELECT '','' + c.name FROM sys.index_columns ic INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1 ORDER BY c.name FOR XML PATH('''')), 1, 1, ''''), '''')
	+ ''|filtro='' + ISNULL(i.filter_definition, '''')
FROM sys.tables t INNER JOIN sys.indexes i ON t.object_id = i.object_id
WHERE t.is_ms_shipped = 0 AND t.name <> ''sysdiagrams'' AND i.type > 0;

INSERT #schema (Db, Tipo, Nome, Definizione)
SELECT ''?L?'', ''Chiave esterna'', t.name + ''.'' + f.name,
	''verso='' + r.name + ''|delete='' + f.delete_referential_action_desc + ''|update='' + f.update_referential_action_desc + ''|disabilitata='' + CAST(f.is_disabled AS VARCHAR(1))
	+ ''|colonne='' + STUFF((SELECT '','' + pc.name + ''>'' + rc.name FROM sys.foreign_key_columns k INNER JOIN sys.columns pc ON k.parent_object_id = pc.object_id AND k.parent_column_id = pc.column_id INNER JOIN sys.columns rc ON k.referenced_object_id = rc.object_id AND k.referenced_column_id = rc.column_id WHERE k.constraint_object_id = f.object_id ORDER BY k.constraint_column_id FOR XML PATH('''')), 1, 1, '''')
FROM sys.foreign_keys f INNER JOIN sys.tables t ON f.parent_object_id = t.object_id INNER JOIN sys.tables r ON f.referenced_object_id = r.object_id;

INSERT #schema (Db, Tipo, Nome, Definizione)
SELECT ''?L?'', ''Tipo tabella'', tt.name + ''.'' + c.name,
	TYPE_NAME(c.user_type_id) + ''|'' + CAST(c.max_length AS VARCHAR(10)) + ''|null='' + CAST(c.is_nullable AS VARCHAR(1)) + ''|'' + ISNULL(c.collation_name, '''') + ''|pos='' + CAST(ROW_NUMBER() OVER (PARTITION BY c.object_id ORDER BY c.column_id) AS VARCHAR(10))
FROM sys.table_types tt INNER JOIN sys.columns c ON tt.type_table_object_id = c.object_id;

INSERT #schema (Db, Tipo, Nome, Definizione)
SELECT ''?L?'', ''Vincolo'', OBJECT_NAME(o.parent_object_id) + ''.'' + o.name, o.type_desc + ''|'' + ISNULL(d.definition, '''') + ISNULL(k.definition, '''')
FROM sys.objects o LEFT JOIN sys.default_constraints d ON o.object_id = d.object_id LEFT JOIN sys.check_constraints k ON o.object_id = k.object_id
WHERE o.type IN (''D'', ''C'') AND o.is_ms_shipped = 0;

INSERT #schema (Db, Tipo, Nome, Definizione)
SELECT ''?L?'', o.type_desc, o.name,
	REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(m.definition, CHAR(13), ''''), CHAR(10), ''''), CHAR(9), ''''), '' '', ''''), ''CREATEORALTER'', ''CREATE'')
FROM sys.objects o INNER JOIN sys.sql_modules m ON o.object_id = m.object_id
WHERE o.is_ms_shipped = 0 AND o.name NOT LIKE ''%diagram%'';
';
DECLARE @a NVARCHAR(MAX) = REPLACE(REPLACE(@sql, '?DB?', '$(A)'), '?L?', 'A');
DECLARE @b NVARCHAR(MAX) = REPLACE(REPLACE(@sql, '?DB?', '$(B)'), '?L?', 'B');
EXEC sys.sp_executesql @a;
EXEC sys.sp_executesql @b;
GO
SELECT
	Dove = x.Db,
	x.Tipo,
	x.Nome,
	Differenza = IIF(y.Nome IS NULL, 'manca nell''altro database', 'diverso'),
	Definizione = LEFT(x.Definizione, 300)
FROM
	#schema x
	LEFT JOIN #schema y ON x.Db <> y.Db AND x.Tipo = y.Tipo AND x.Nome = y.Nome
WHERE
	y.Nome IS NULL
	OR ISNULL(x.Definizione, '') <> ISNULL(y.Definizione, '')
ORDER BY
	x.Tipo,
	x.Nome,
	x.Db;
GO
DROP TABLE #schema;
GO
