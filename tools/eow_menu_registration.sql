SET NOCOUNT ON;

-- Modulo EoW come modulo indipendente di primo livello (come RIF/SCD/SRV), un solo permesso EOW.
-- Eseguito su dev il 2026-09-21. NON ancora eseguito in produzione.
-- NON include l'attivazione per-dominio (tblDominiModuli) - decisione commerciale/di licenza
-- dell'utente su quali domini abilitare al modulo EOW, da fare a parte quando serve.

INSERT INTO dbo.tblModuli (Id, Nome, Attivo) VALUES ('EOW', 'Gestione EoW', 1);

-- Nome DEVE essere una singola parola che, in minuscolo, coincide col prefisso di route
-- dell'area applicativa (qui "eow", da @page "/eow/..."): SideBarMenuViewComponent
-- (Pages/Shared/Components/SideBarMenu/Default.cshtml) costruisce l'href della pagina come
-- "/" + item.Nome.ToLower() + itemSub.Pagina, NON usa un codice separato - "Gestione EoW"
-- (con spazio) romperebbe il link generando "/gestione eow/..." invece di "/eow/...".
INSERT INTO dbo.tblPagineAree (Id, Nome, Icon) VALUES ('EOW', 'EoW', 'fal fa-recycle');

INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('EOW', 'Gestione EoW', 0, 0, 1);

INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('EOW', 'EOW');

-- Giacenze: una sola voce di menu (Url='giacenze/lotto', la vista di default) - Magazzino e
-- Carichi si raggiungono con un dropdown IN PAGINA (Pages/Eow/Giacenze/Lotto.cshtml), stesso
-- pattern di uspRifiutiGiacenze/RGC (tblPagine.Url='giacenze/eer', Materiale/Etichette/Carichi
-- sono link interni alla pagina, non voci di menu separate).
INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES
    ('EWL', 'EOW', 'Lotti', NULL, NULL),
    ('EWM', 'EOW', 'Magazzini', NULL, NULL),
    ('EWA', 'EOW', 'Allocazioni', NULL, NULL),
    ('EWG', 'EOW', 'Giacenze', 'giacenze/lotto', NULL);

-- Riga Area (contenitore). Posizione richiesta dall'utente: dopo Rentri (Pos=5), prima di
-- Impostazioni - Impostazioni (AZ0) va quindi spostata da Pos=6 a Pos=7.
UPDATE dbo.tblMenu SET Pos = 7 WHERE Id = 'AZ0';
INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AH0', NULL, 'EOW', NULL, 6);

-- Righe pagina sotto l'Area
INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES
    ('AH1', 'AH0', NULL, 'EWL', 0),
    ('AH2', 'AH0', NULL, 'EWM', 1),
    ('AH3', 'AH0', NULL, 'EWA', 2),
    ('AH4', 'AH0', NULL, 'EWG', 3);
