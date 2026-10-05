SET NOCOUNT ON;

-- Modulo EoW: nuova funzione EWC "Configurazione" che governa i permessi su Lotti, Magazzini e
-- Allocazioni (elenco, dettaglio, inserimento, modifica, cancellazione). La funzione EOW resta per
-- Registrazioni, Giacenze e per l'uso dei lotti nelle registrazioni rifiuti (select dei lotti,
-- allocazione, esecuzione di una regola di allocazione).
-- Rieseguibile. Nessun travaso dei permessi: chi aveva EOW non riceve EWC in automatico, il permesso
-- va assegnato in Impostazioni > Utenti (gli amministratori lo hanno già, come per ogni funzione dei
-- moduli attivi del dominio).

IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'EWC')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('EWC', 'Configurazione', 0, 0, 1);
ELSE
	UPDATE dbo.tblFunzioni SET Nome = 'Configurazione' WHERE Id = 'EWC' AND Nome <> 'Configurazione';

-- La funzione esistente si chiama solo "Gestione" (il modulo si legge nella colonna Moduli)
UPDATE dbo.tblFunzioni SET Nome = 'Gestione' WHERE Id = 'EOW' AND Nome <> 'Gestione';

-- Anche il modulo perde "Gestione": si chiama solo "EoW"
UPDATE dbo.tblModuli SET Nome = 'EoW' WHERE Id = 'EOW' AND Nome <> 'EoW';

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'EOW' AND IdFunzione = 'EWC')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('EOW', 'EWC');

-- Le voci di menu Lotti, Magazzini e Allocazioni seguono la funzione della pagina
UPDATE dbo.tblPagine SET IdFunzione = 'EWC' WHERE Id IN ('EWL', 'EWM', 'EWA') AND IdFunzione <> 'EWC';

SELECT Id, IdFunzione, Nome FROM dbo.tblPagine WHERE Id LIKE 'EW%' ORDER BY Id;
GO
