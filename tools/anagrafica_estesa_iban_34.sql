SET NOCOUNT ON;

-- Colonne Iban di tblClientiFornitori e tblBancheCasse da 30 a 34 caratteri: è la lunghezza massima di un
-- IBAN (ISO 13616); con 30 non entravano gli IBAN dei paesi che ne usano di più (es. Malta, 31).
-- Rieseguibile: modifica solo le colonne ancora più corte di 34.

IF COL_LENGTH('dbo.tblClientiFornitori', 'Iban') < 34
	ALTER TABLE dbo.tblClientiFornitori ALTER COLUMN Iban VARCHAR(34) COLLATE Latin1_General_CI_AS NULL;

IF COL_LENGTH('dbo.tblBancheCasse', 'Iban') < 34
	ALTER TABLE dbo.tblBancheCasse ALTER COLUMN Iban VARCHAR(34) COLLATE Latin1_General_CI_AS NULL;

SELECT
	Tabella = OBJECT_NAME(c.object_id),
	Colonna = c.name,
	Lunghezza = c.max_length,
	Collation = c.collation_name
FROM sys.columns c
WHERE
	c.name = 'Iban'
	AND c.object_id IN (OBJECT_ID('dbo.tblClientiFornitori'), OBJECT_ID('dbo.tblBancheCasse'));
GO
