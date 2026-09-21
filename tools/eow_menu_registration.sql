SET NOCOUNT ON;

-- Modulo EoW come modulo indipendente di primo livello (come RIF/SCD/SRV), un solo permesso EOW.
-- Eseguito su dev il 2026-09-21. NON ancora eseguito in produzione.
-- NON include l'attivazione per-dominio (tblDominiModuli) - decisione commerciale/di licenza
-- dell'utente su quali domini abilitare al modulo EOW, da fare a parte quando serve.

INSERT INTO dbo.tblModuli (Id, Nome, Attivo) VALUES ('EOW', 'Gestione EoW', 1);

INSERT INTO dbo.tblPagineAree (Id, Nome, Icon) VALUES ('EOW', 'Gestione EoW', 'fal fa-recycle');

INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('EOW', 'Gestione EoW', 0, 0, 1);

INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('EOW', 'EOW');

INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES
    ('EWL', 'EOW', 'Lotti', NULL, NULL),
    ('EWM', 'EOW', 'Magazzini', NULL, NULL),
    ('EWA', 'EOW', 'Allocazioni', NULL, NULL);

-- Riga Area (contenitore, Pos=7 = dopo Impostazioni, ultima nella sidebar)
INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AH0', NULL, 'EOW', NULL, 7);

-- Righe pagina sotto l'Area
INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES
    ('AH1', 'AH0', NULL, 'EWL', 0),
    ('AH2', 'AH0', NULL, 'EWM', 1),
    ('AH3', 'AH0', NULL, 'EWA', 2);
