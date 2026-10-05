SET NOCOUNT ON;

-- Modulo Magazzino: nuova funzione MGC "Configurazione" che governa i permessi su Articoli e Lotti
-- (elenco, dettaglio, inserimento, modifica, cancellazione). La funzione MAG resta per Movimenti,
-- Giacenze e per l'uso di articoli e lotti nelle righe dei movimenti (select di articoli e lotti,
-- lettura della scheda articolo).
-- Rieseguibile. Nessun travaso dei permessi: chi aveva MAG non riceve MGC in automatico, il permesso
-- va assegnato in Impostazioni > Utenti (gli amministratori lo hanno già, come per ogni funzione dei
-- moduli attivi del dominio).

IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'MGC')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('MGC', 'Configurazione', 0, 0, 1);
ELSE
	UPDATE dbo.tblFunzioni SET Nome = 'Configurazione' WHERE Id = 'MGC' AND Nome <> 'Configurazione';

-- La funzione esistente si chiama solo "Gestione" (il modulo si legge nella colonna Moduli)
UPDATE dbo.tblFunzioni SET Nome = 'Gestione' WHERE Id = 'MAG' AND Nome <> 'Gestione';

-- Anche il modulo perde "Gestione": si chiama solo "Magazzino"
UPDATE dbo.tblModuli SET Nome = 'Magazzino' WHERE Id = 'MAG' AND Nome <> 'Magazzino';

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'MAG' AND IdFunzione = 'MGC')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('MAG', 'MGC');

-- Le voci di menu Articoli e Lotti seguono la funzione della pagina
UPDATE dbo.tblPagine SET IdFunzione = 'MGC' WHERE Id IN ('MGA', 'MGL') AND IdFunzione <> 'MGC';

SELECT Id, IdFunzione, Nome FROM dbo.tblPagine WHERE Id LIKE 'MG%' ORDER BY Id;
GO
