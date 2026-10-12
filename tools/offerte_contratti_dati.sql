SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Modulo Offerte e contratti: valori delle tabelle di riferimento degli importi.
--   tblImportiPriorita: priorità con cui la fatturazione automatica sceglie l'importo (la più alta vince)
--   tblImportiRigheTipi: per che cosa si moltiplica l'importo di una riga, per modulo dei documenti
--     (rifiuti: una volta per registrazione, per i chilogrammi, le tonnellate o i litri; magazzino: per
--     movimento o per articolo; servizi: per servizio o per unità)
-- Rieseguibile: inserisce le righe mancanti e riallinea i nomi.

BEGIN TRANSACTION;

IF NOT EXISTS (SELECT 1 FROM dbo.tblImportiPriorita WHERE Id = 2)
	INSERT INTO dbo.tblImportiPriorita (Id, Nome) VALUES (2, 'Bassa');
IF NOT EXISTS (SELECT 1 FROM dbo.tblImportiPriorita WHERE Id = 4)
	INSERT INTO dbo.tblImportiPriorita (Id, Nome) VALUES (4, 'Media');
IF NOT EXISTS (SELECT 1 FROM dbo.tblImportiPriorita WHERE Id = 6)
	INSERT INTO dbo.tblImportiPriorita (Id, Nome) VALUES (6, 'Alta');

DECLARE @tipi TABLE (
	Id CHAR(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	IdModulo CHAR(3) COLLATE DATABASE_DEFAULT NOT NULL,
	Nome VARCHAR(50) NOT NULL,
	Pos INT NOT NULL
);
INSERT @tipi (Id, IdModulo, Nome, Pos)
VALUES
	('MM', 'MAG', 'Movimento', 1),
	('MA', 'MAG', 'Articolo', 2),
	('RM', 'RIF', 'Movimento', 1),
	('RK', 'RIF', 'KG (Kilogrammo)', 2),
	('RT', 'RIF', 'T (Tonnellata)', 3),
	('RL', 'RIF', 'L (Litro)', 4),
	('SM', 'SRV', 'Servizio', 1),
	('SU', 'SRV', 'Unità', 2);

INSERT INTO dbo.tblImportiRigheTipi (Id, IdModulo, Nome, Pos)
SELECT t.Id, t.IdModulo, t.Nome, t.Pos
FROM @tipi t
WHERE NOT EXISTS (SELECT 1 FROM dbo.tblImportiRigheTipi x WHERE x.Id = t.Id);

UPDATE x
SET
	IdModulo = t.IdModulo,
	Nome = t.Nome,
	Pos = t.Pos
FROM
	dbo.tblImportiRigheTipi x
	INNER JOIN @tipi t ON x.Id = t.Id
WHERE
	ISNULL(x.IdModulo, '') <> t.IdModulo
	OR ISNULL(x.Nome, '') <> t.Nome COLLATE Latin1_General_BIN2
	OR ISNULL(x.Pos, 0) <> t.Pos;

COMMIT TRANSACTION;
GO

SELECT Id, Nome FROM dbo.tblImportiPriorita ORDER BY Id DESC;
SELECT Id, IdModulo, Nome, Pos FROM dbo.tblImportiRigheTipi ORDER BY IdModulo, Pos;
GO
