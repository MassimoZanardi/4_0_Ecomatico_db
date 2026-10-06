SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Modulo Anagrafica estesa (ANX) e prima configurazione del modulo Fatturazione (FAT).
--   ANX richiede ANA: le voci Clienti e Fornitori stanno nell'area di menu Anagrafica, visibile solo con ANA attivo.
--   FAT "Fatturazione": nuova area di menu dopo Magazzino, con la funzione FTC "Configurazione" che governa
--   le pagine Banche e casse e Aliquote IVA. FAT richiede ANX e ANA (uspDomini_ins_Modulo risolve un solo
--   livello di dipendenze, quindi vanno indicate entrambe).
-- In tblModuliRelazioni Id = modulo richiesto, IdParent = modulo che lo richiede.
-- Nessuna attivazione sui domini: i moduli si attivano da Impostazioni > Domini.
-- Rieseguibile.

BEGIN TRANSACTION;

-- Dipendenza ANX -> ANA
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliRelazioni WHERE Id = 'ANA' AND IdParent = 'ANX')
	INSERT INTO dbo.tblModuliRelazioni (Id, IdParent) VALUES ('ANA', 'ANX');

-- Modulo, area di menu e funzione
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuli WHERE Id = 'FAT')
	INSERT INTO dbo.tblModuli (Id, Nome, Attivo) VALUES ('FAT', 'Fatturazione', 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagineAree WHERE Id = 'FAT')
	INSERT INTO dbo.tblPagineAree (Id, Nome, Icon) VALUES ('FAT', 'Fatturazione', 'fal fa-file-invoice');

IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'FTC')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('FTC', 'Configurazione', 0, 0, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'FAT' AND IdFunzione = 'FTC')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('FAT', 'FTC');

-- Dipendenze FAT -> ANX e FAT -> ANA
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliRelazioni WHERE Id = 'ANX' AND IdParent = 'FAT')
	INSERT INTO dbo.tblModuliRelazioni (Id, IdParent) VALUES ('ANX', 'FAT');

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliRelazioni WHERE Id = 'ANA' AND IdParent = 'FAT')
	INSERT INTO dbo.tblModuliRelazioni (Id, IdParent) VALUES ('ANA', 'FAT');

-- Pagine: Url esplicito perché il nome contiene spazi ("/fatturazione/banche-casse", "/fatturazione/aliquote-iva")
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTB')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTB', 'FTC', 'Banche e casse', 'banche-casse', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTI')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTI', 'FTC', 'Aliquote IVA', 'aliquote-iva', NULL);

-- Menu: Fatturazione dopo Magazzino; Rentri e Impostazioni scendono di una posizione
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ0')
BEGIN
	UPDATE dbo.tblMenu SET Pos = 8 WHERE Id = 'AG0' AND Pos = 7;
	UPDATE dbo.tblMenu SET Pos = 9 WHERE Id = 'AZ0' AND Pos = 8;
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ0', NULL, 'FAT', NULL, 7);
END

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ1')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ1', 'AJ0', NULL, 'FTB', 0);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ2')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ2', 'AJ0', NULL, 'FTI', 1);

COMMIT TRANSACTION;

SELECT m.Id, m.Pos, Area = a.Nome
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagineAree a ON m.IdArea = a.Id
WHERE m.IdParent IS NULL
ORDER BY m.Pos;

SELECT m.Id, m.Pos, p.Nome, p.Url, p.IdFunzione
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
WHERE m.IdParent IN ('AC0', 'AJ0')
ORDER BY m.IdParent, m.Pos;

SELECT Id, IdParent FROM dbo.tblModuliRelazioni ORDER BY IdParent, Id;
GO
