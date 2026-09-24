-- Registrazione modulo "Gestione Magazzino" (Fase 1: Articoli, Lotti, Movimenti, Giacenze)
-- Pattern identico a tools/eow_menu_registration.sql.
--
-- PRIMA DI ESEGUIRE su un nuovo ambiente: verificare che i codici sotto siano liberi con:
-- SELECT Id FROM dbo.tblModuli WHERE Id = 'MAG';
-- SELECT Id FROM dbo.tblPagineAree WHERE Id = 'MAG';
-- SELECT Id FROM dbo.tblFunzioni WHERE Id = 'MAG';
-- SELECT Id FROM dbo.tblPagine WHERE Id IN ('MGA','MGL','MGM','MGG');
-- SELECT Id FROM dbo.tblMenu WHERE Id IN ('AI0','AI1','AI2','AI3','AI4');
-- Tutte le SELECT sopra devono restituire 0 righe.

SET XACT_ABORT ON;
BEGIN TRANSACTION;

	INSERT INTO dbo.tblModuli (Id, Nome, Attivo) VALUES ('MAG', 'Gestione Magazzino', 1);
	INSERT INTO dbo.tblPagineAree (Id, Nome, Icon) VALUES ('MAG', 'Magazzino', 'fal fa-warehouse');
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('MAG', 'Gestione Magazzino', 0, 0, 1);
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('MAG', 'MAG');

	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES
		('MGA', 'MAG', 'Articoli', NULL, NULL),
		('MGL', 'MAG', 'Lotti', NULL, NULL),
		('MGM', 'MAG', 'Movimenti', NULL, NULL),
		('MGG', 'MAG', 'Giacenze', 'giacenze/articolo', NULL);

	-- Inserita tra EoW (Pos = 5) e Rentri (Pos = 6): riordina le voci successive.
	UPDATE dbo.tblMenu SET Pos = 8 WHERE Id = 'AZ0'; -- Impostazioni
	UPDATE dbo.tblMenu SET Pos = 7 WHERE Id = 'AG0'; -- Rentri
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AI0', NULL, 'MAG', NULL, 6);
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES
		('AI1', 'AI0', NULL, 'MGA', 0),
		('AI2', 'AI0', NULL, 'MGL', 1),
		('AI3', 'AI0', NULL, 'MGM', 2),
		('AI4', 'AI0', NULL, 'MGG', 3);

COMMIT TRANSACTION;
SET XACT_ABORT OFF;
