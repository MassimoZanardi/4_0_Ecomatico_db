SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Modulo Fatturazione: aliquote IVA di sistema (IdSede NULL = valide per tutti i domini).
-- Gli Id sono fissi e vengono registrati anche in tblId, così uspId_get non li assegna ad altre entità.
-- Nessuna riga in tblIdLog: dato di sistema senza sessione né utente.
-- L'aliquota "Esente" ha natura N4 (Esenti), richiesta dalla fattura elettronica per le aliquote a zero.
-- Rieseguibile.

DECLARE @aliquote TABLE (
	Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	IdTipo CHAR(2) COLLATE DATABASE_DEFAULT NOT NULL,
	IdNatura VARCHAR(4) COLLATE DATABASE_DEFAULT NULL,
	Nome VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
	Codice VARCHAR(20) COLLATE DATABASE_DEFAULT NOT NULL,
	Valore DECIMAL(9, 2) NOT NULL
);

INSERT INTO @aliquote (Id, IdTipo, IdNatura, Nome, Codice, Valore)
VALUES
	('003c400231134eac', 'IM', NULL, 'Iva 22%', '22000', 22.00),
	('54de2336ccc94971', 'ES', 'N4', 'Esente', '00000', 0.00),
	('636d843fca6b488c', 'IM', NULL, 'Iva 4%', '04000', 4.00),
	('dd5fd1d8c64848d0', 'IM', NULL, 'Iva 10%', '10000', 10.00);

-- Un Id già registrato in tblId ma assente da tblAliquoteIva appartiene a un'altra entità
IF EXISTS (
	SELECT 1
	FROM @aliquote a
	INNER JOIN dbo.tblId i ON i.Id = a.Id
	WHERE NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIva ai WHERE ai.Id = a.Id)
)
	THROW 50001, 'Uno o più Id delle aliquote IVA sono già assegnati ad altre entità', 1;

BEGIN TRANSACTION;

INSERT INTO dbo.tblId (Id)
SELECT a.Id
FROM @aliquote a
WHERE NOT EXISTS (SELECT 1 FROM dbo.tblId i WHERE i.Id = a.Id);

INSERT INTO dbo.tblAliquoteIva (Id, IdSede, IdTipo, IdNatura, Nome, Codice, Valore, Lock)
SELECT a.Id, NULL, a.IdTipo, a.IdNatura, a.Nome, a.Codice, a.Valore, 0
FROM @aliquote a
WHERE NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIva ai WHERE ai.Id = a.Id);

COMMIT TRANSACTION;

SELECT ai.Id, ai.IdSede, ai.IdTipo, ai.IdNatura, ai.Nome, ai.Codice, ai.Valore, ai.Lock,
	CASE WHEN i.Id IS NULL THEN 0 ELSE 1 END AS InTblId
FROM dbo.tblAliquoteIva ai
LEFT JOIN dbo.tblId i ON i.Id = ai.Id
ORDER BY ai.Valore DESC;
GO
