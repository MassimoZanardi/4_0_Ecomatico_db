SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Modulo Offerte e contratti (OFC): struttura mancante e registrazione di modulo, funzioni, pagine e menu.
--   Le tabelle tblOfferteContratti* e tblImporti* esistono gia'; qui si aggiunge solo quello che manca.
--   1. tblRifiutiOperazioni.IsFatturabile: operazioni le cui registrazioni entrano nella fatturazione (T*, T*aT, TR)
--   2. tblClientiFornitori.IdRaggruppamento: una fattura per cliente (C), per sede (S) o per contratto (T)
--   3. tblImportiRighe.Pos: ordine delle righe dell'importo
--   4. tblFattureDocumenti: legame tra il documento fatturabile (registrazione, movimento con DDT, servizio)
--      e la fattura, con "non fatturabile" e cliente indicato sul documento
--   5. tblPagine.IdModulo: modulo che il dominio deve avere attivo, oltre a quello dell'area, per vedere la voce
--   6. Indici
--   7. Modulo OFC, area di menu prima di Fatturazione, funzioni OCC e OCI, pagine e voci di menu
-- In tblModuliRelazioni Id = modulo richiesto, IdParent = modulo che lo richiede.
-- Nessuna attivazione sui domini: il modulo si attiva da Impostazioni > Domini.
-- Rieseguibile.

BEGIN TRANSACTION;

-- 1. Operazioni fatturabili
IF COL_LENGTH('dbo.tblRifiutiOperazioni', 'IsFatturabile') IS NULL
	ALTER TABLE dbo.tblRifiutiOperazioni ADD IsFatturabile BIT NULL;

-- 2. Raggruppamento delle fatture generate, sulla scheda del cliente
IF COL_LENGTH('dbo.tblClientiFornitori', 'IdRaggruppamento') IS NULL
BEGIN
	ALTER TABLE dbo.tblClientiFornitori ADD IdRaggruppamento CHAR(1) COLLATE Latin1_General_CI_AS NULL;

	ALTER TABLE dbo.tblClientiFornitori WITH CHECK ADD CONSTRAINT FK_tblClientiFornitori_tblFattureRaggruppamenti
		FOREIGN KEY (IdRaggruppamento) REFERENCES dbo.tblFattureRaggruppamenti (Id);
END

-- 3. Ordine delle righe dell'importo
IF COL_LENGTH('dbo.tblImportiRighe', 'Pos') IS NULL
	ALTER TABLE dbo.tblImportiRighe ADD Pos INT NULL;

-- 4. Documenti fatturabili: Id = Id del documento (registrazione, movimento di magazzino, servizio)
IF OBJECT_ID('dbo.tblFattureDocumenti', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureDocumenti (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdModulo CHAR(3) COLLATE Latin1_General_CI_AS NOT NULL,
		IdFattura CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		IdClienteFornitore CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		IdImporto CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		IdOffertaContratto CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		NonFatturabile BIT NULL,
		CONSTRAINT PK_tblFattureDocumenti PRIMARY KEY CLUSTERED (Id ASC)
	);

	ALTER TABLE dbo.tblFattureDocumenti WITH CHECK ADD CONSTRAINT FK_tblFattureDocumenti_tblId
		FOREIGN KEY (Id) REFERENCES dbo.tblId (Id);
	ALTER TABLE dbo.tblFattureDocumenti WITH CHECK ADD CONSTRAINT FK_tblFattureDocumenti_tblModuli
		FOREIGN KEY (IdModulo) REFERENCES dbo.tblModuli (Id);
	ALTER TABLE dbo.tblFattureDocumenti WITH CHECK ADD CONSTRAINT FK_tblFattureDocumenti_tblFatture
		FOREIGN KEY (IdFattura) REFERENCES dbo.tblFatture (Id);
	ALTER TABLE dbo.tblFattureDocumenti WITH CHECK ADD CONSTRAINT FK_tblFattureDocumenti_tblClientiFornitori
		FOREIGN KEY (IdClienteFornitore) REFERENCES dbo.tblClientiFornitori (Id);
	ALTER TABLE dbo.tblFattureDocumenti WITH CHECK ADD CONSTRAINT FK_tblFattureDocumenti_tblImporti
		FOREIGN KEY (IdImporto) REFERENCES dbo.tblImporti (Id);
	ALTER TABLE dbo.tblFattureDocumenti WITH CHECK ADD CONSTRAINT FK_tblFattureDocumenti_tblOfferteContratti
		FOREIGN KEY (IdOffertaContratto) REFERENCES dbo.tblOfferteContratti (Id);
END

-- 5. Modulo richiesto dalla pagina oltre a quello dell'area di menu
IF COL_LENGTH('dbo.tblPagine', 'IdModulo') IS NULL
BEGIN
	ALTER TABLE dbo.tblPagine ADD IdModulo CHAR(3) COLLATE Latin1_General_CI_AS NULL;

	ALTER TABLE dbo.tblPagine WITH CHECK ADD CONSTRAINT FK_tblPagine_tblModuli
		FOREIGN KEY (IdModulo) REFERENCES dbo.tblModuli (Id);
END

COMMIT TRANSACTION;
GO

BEGIN TRANSACTION;

-- 1. T* (Z), T*aT (T), TR (I)
UPDATE dbo.tblRifiutiOperazioni
SET IsFatturabile = IIF(Id IN ('Z', 'T', 'I'), 1, 0)
WHERE IsFatturabile IS NULL;

-- 2. Schede esistenti dei clienti: una fattura per cliente
UPDATE dbo.tblClientiFornitori
SET IdRaggruppamento = 'C'
WHERE
	Tipo = 'C'
	AND IdRaggruppamento IS NULL;

-- Tipo di riga a litri: stesso stile di "KG (Kilogrammo)" e "T (Tonnellata)"
UPDATE dbo.tblImportiRigheTipi SET Nome = 'L (Litro)' WHERE Id = 'RL' AND Nome <> 'L (Litro)';

-- 6. Indici
-- Un importo sta in un solo contratto o offerta
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_OfferteContrattiImporti_IdImporto')
	CREATE UNIQUE NONCLUSTERED INDEX UX_OfferteContrattiImporti_IdImporto ON dbo.tblOfferteContrattiImporti (IdImporto);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Importi_IdSede')
	CREATE NONCLUSTERED INDEX IX_Importi_IdSede ON dbo.tblImporti (IdSede) INCLUDE (IdPriorita, Lock);

-- Righe dell'importo applicato, lette per ogni documento da ufnImportiRifiuti_get_ApplicazioneRighe: con le
-- colonne incluse non serve il lookup per riga. L'indice nato senza colonne incluse viene ricreato
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiRighe_IdImporto')
	AND NOT EXISTS (
		SELECT 1
		FROM
			sys.indexes i
			INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id
											AND i.index_id = ic.index_id
		WHERE
			i.name = 'IX_ImportiRighe_IdImporto'
			AND ic.is_included_column = 1
	)
	DROP INDEX IX_ImportiRighe_IdImporto ON dbo.tblImportiRighe;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiRighe_IdImporto')
	CREATE NONCLUSTERED INDEX IX_ImportiRighe_IdImporto ON dbo.tblImportiRighe (IdImporto) INCLUDE (Pos, IdTipo, Importo, MinimoFatturabile, Lock);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_OfferteContratti_IdSede')
	CREATE NONCLUSTERED INDEX IX_OfferteContratti_IdSede ON dbo.tblOfferteContratti (IdSede) INCLUDE (IdClienteFornitore, Tipo, Lock);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FattureDocumenti_IdFattura')
	CREATE NONCLUSTERED INDEX IX_FattureDocumenti_IdFattura ON dbo.tblFattureDocumenti (IdFattura);

-- Chiavi esterne di tblFattureDocumenti: senza indice, cancellare la bozza di un importo, di un contratto o di
-- un cliente legge tutta la tabella, che cresce di una riga per ogni documento fatturato. Filtrati: le tre
-- colonne sono vuote finche' il documento non viene fatturato o non gli si indica un cliente
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FattureDocumenti_IdImporto')
	CREATE NONCLUSTERED INDEX IX_FattureDocumenti_IdImporto ON dbo.tblFattureDocumenti (IdImporto) WHERE IdImporto IS NOT NULL;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FattureDocumenti_IdOffertaContratto')
	CREATE NONCLUSTERED INDEX IX_FattureDocumenti_IdOffertaContratto ON dbo.tblFattureDocumenti (IdOffertaContratto) WHERE IdOffertaContratto IS NOT NULL;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FattureDocumenti_IdClienteFornitore')
	CREATE NONCLUSTERED INDEX IX_FattureDocumenti_IdClienteFornitore ON dbo.tblFattureDocumenti (IdClienteFornitore) WHERE IdClienteFornitore IS NOT NULL;

-- Contratti e offerte di un cliente: controllo di uspClientiFornitori_del e chiave esterna sul cliente
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_OfferteContratti_IdClienteFornitore')
	CREATE NONCLUSTERED INDEX IX_OfferteContratti_IdClienteFornitore ON dbo.tblOfferteContratti (IdClienteFornitore) INCLUDE (Lock);

-- 7. Modulo, area di menu, funzioni
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuli WHERE Id = 'OFC')
	INSERT INTO dbo.tblModuli (Id, Nome, Attivo) VALUES ('OFC', 'Offerte e contratti', 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagineAree WHERE Id = 'OFC')
	INSERT INTO dbo.tblPagineAree (Id, Nome, Icon) VALUES ('OFC', 'Offerte e contratti', 'fal fa-file-signature');

IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'OCC')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('OCC', 'Offerte e contratti', 0, 0, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'OCI')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('OCI', 'Importi', 0, 0, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'OFC' AND IdFunzione = 'OCC')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('OFC', 'OCC');

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'OFC' AND IdFunzione = 'OCI')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('OFC', 'OCI');

-- Dipendenze OFC -> FAT, ANX, ANA (uspDomini_ins_Modulo risolve un solo livello: vanno indicate tutte)
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliRelazioni WHERE Id = 'FAT' AND IdParent = 'OFC')
	INSERT INTO dbo.tblModuliRelazioni (Id, IdParent) VALUES ('FAT', 'OFC');

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliRelazioni WHERE Id = 'ANX' AND IdParent = 'OFC')
	INSERT INTO dbo.tblModuliRelazioni (Id, IdParent) VALUES ('ANX', 'OFC');

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliRelazioni WHERE Id = 'ANA' AND IdParent = 'OFC')
	INSERT INTO dbo.tblModuliRelazioni (Id, IdParent) VALUES ('ANA', 'OFC');

-- Pagine: le voci Importi richiedono anche il modulo dei documenti a cui si applicano
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'OCK')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note, IdModulo) VALUES ('OCK', 'OCC', 'Contratti clienti', 'contratti-clienti', NULL, NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'OCO')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note, IdModulo) VALUES ('OCO', 'OCC', 'Offerte clienti', 'offerte-clienti', NULL, NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'OCR')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note, IdModulo) VALUES ('OCR', 'OCI', 'Importi rifiuti', 'importi-rifiuti', NULL, 'RIF');

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'OCM')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note, IdModulo) VALUES ('OCM', 'OCI', 'Importi magazzino', 'importi-magazzino', NULL, 'MAG');

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'OCS')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note, IdModulo) VALUES ('OCS', 'OCI', 'Importi servizi', 'importi-servizi', NULL, 'SRV');

-- Menu: Offerte e contratti prima di Fatturazione; Fatturazione, Rentri e Impostazioni scendono di una posizione
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AK0')
BEGIN
	UPDATE dbo.tblMenu SET Pos = 10 WHERE Id = 'AZ0' AND Pos = 9;
	UPDATE dbo.tblMenu SET Pos = 9 WHERE Id = 'AG0' AND Pos = 8;
	UPDATE dbo.tblMenu SET Pos = 8 WHERE Id = 'AJ0' AND Pos = 7;
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AK0', NULL, 'OFC', NULL, 7);
END

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AK1')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AK1', 'AK0', NULL, 'OCK', 0);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AK2')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AK2', 'AK0', NULL, 'OCO', 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AK3')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AK3', 'AK0', NULL, 'OCR', 2);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AK4')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AK4', 'AK0', NULL, 'OCM', 3);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AK5')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AK5', 'AK0', NULL, 'OCS', 4);

COMMIT TRANSACTION;
GO

SELECT m.Id, m.Pos, Area = a.Nome
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagineAree a ON m.IdArea = a.Id
WHERE m.IdParent IS NULL
ORDER BY m.Pos;

SELECT m.Id, m.Pos, p.Nome, p.Url, p.IdFunzione, p.IdModulo
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
WHERE m.IdParent = 'AK0'
ORDER BY m.Pos;

SELECT Id, Codice, Nome, IsFatturabile FROM dbo.tblRifiutiOperazioni ORDER BY Pos;

SELECT Id, IdModulo, Nome, Pos FROM dbo.tblImportiRigheTipi ORDER BY IdModulo, Pos;

SELECT Id, IdParent FROM dbo.tblModuliRelazioni WHERE IdParent = 'OFC' ORDER BY Id;
GO
