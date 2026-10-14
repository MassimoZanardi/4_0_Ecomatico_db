SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Offerte e contratti, fase servizi: importi dei servizi.
-- L'importo dei servizi è un LISTINO, come quello di magazzino: vale per un tipo di servizio, un richiedente, una
-- sede interna e un'etichetta (o per tutti) e ha una riga per ogni risorsa (persona o oggetto impiegabile nei
-- servizi), con il suo prezzo per la quantità della risorsa nel servizio. La risorsa non è una variabile
-- dell'importo: sta sulla riga.
--   1. tblImportiServizi: via l'esecutore (IdEsecutore, nato dalla 3.1: nella 4.0 il servizio non ha un
--      esecutore); variabile IdSedeInterna (la sede interna del calendario che ospita il servizio); IdSede NOT
--      NULL, copia dell'azienda dell'importo, per il confronto con i servizi (come tblImportiRifiuti.IdSede).
--   2. tblImportiRigheServizi: risorsa a cui si applica il prezzo di una riga a quantità (tipo SU). Chiave
--      esterna sulla riga ON DELETE CASCADE: cancellata la riga, sparisce da sola.
--   3. Il tipo di riga SU si chiama "Risorsa" (era "Unità", dalla 3.1, dove il prezzo era per unità di misura).
--   4. Indici.
-- Rieseguibile. Da eseguire dopo offerte_contratti_struttura.sql.

BEGIN TRANSACTION;

-- 1. Variabili degli importi dei servizi
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiServizi_IdSede')
	DROP INDEX IX_ImportiServizi_IdSede ON dbo.tblImportiServizi;

IF OBJECT_ID('dbo.FK_tblImportiServizi_tblSedi_IdEsecutore', 'F') IS NOT NULL
	ALTER TABLE dbo.tblImportiServizi DROP CONSTRAINT FK_tblImportiServizi_tblSedi_IdEsecutore;

IF COL_LENGTH('dbo.tblImportiServizi', 'IdEsecutore') IS NOT NULL
	ALTER TABLE dbo.tblImportiServizi DROP COLUMN IdEsecutore;

IF COL_LENGTH('dbo.tblImportiServizi', 'IdSedeInterna') IS NULL
BEGIN
	ALTER TABLE dbo.tblImportiServizi ADD IdSedeInterna CHAR(16) COLLATE Latin1_General_CI_AS NULL;

	ALTER TABLE dbo.tblImportiServizi WITH CHECK ADD CONSTRAINT FK_tblImportiServizi_tblSedi_IdSedeInterna
		FOREIGN KEY (IdSedeInterna) REFERENCES dbo.tblSedi (Id);
END

IF COL_LENGTH('dbo.tblImportiServizi', 'IdSede') IS NULL
	ALTER TABLE dbo.tblImportiServizi ADD IdSede CHAR(16) COLLATE Latin1_General_CI_AS NULL;

-- 2. Risorsa delle righe a quantità
IF OBJECT_ID('dbo.tblImportiRigheServizi', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblImportiRigheServizi (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdOsepe CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		CONSTRAINT PK_tblImportiRigheServizi PRIMARY KEY CLUSTERED (Id ASC)
	);

	ALTER TABLE dbo.tblImportiRigheServizi WITH CHECK ADD CONSTRAINT FK_tblImportiRigheServizi_tblImportiRighe
		FOREIGN KEY (Id) REFERENCES dbo.tblImportiRighe (Id) ON DELETE CASCADE;
	ALTER TABLE dbo.tblImportiRigheServizi WITH CHECK ADD CONSTRAINT FK_tblImportiRigheServizi_tblOsepe
		FOREIGN KEY (IdOsepe) REFERENCES dbo.tblOsepe (Id);
END

COMMIT TRANSACTION;
GO

BEGIN TRANSACTION;

-- 2. Importi esistenti: l'azienda dell'importo
UPDATE s
SET IdSede = i.IdSede
FROM
	dbo.tblImportiServizi s
	INNER JOIN dbo.tblImporti i ON s.Id = i.Id
WHERE s.IdSede IS NULL;

-- La copia è obbligatoria, come per rifiuti e magazzino: un importo senza l'azienda non verrebbe mai letto dal
-- confronto con i servizi, e senza errori. L'indice sulla colonna è stato tolto al punto 1 e viene ricreato al
-- punto 4
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.tblImportiServizi') AND name = 'IdSede' AND is_nullable = 1)
	ALTER TABLE dbo.tblImportiServizi ALTER COLUMN IdSede CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL;

-- 3. Tipo di riga per risorsa
UPDATE dbo.tblImportiRigheTipi
SET Nome = 'Risorsa'
WHERE Id = 'SU';

-- 4. Indici
-- Importi dei servizi dell'azienda con le loro variabili: il confronto con ogni servizio legge solo questi
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiServizi_IdSede')
	CREATE NONCLUSTERED INDEX IX_ImportiServizi_IdSede ON dbo.tblImportiServizi (IdSede)
		INCLUDE (IdTipo, IdRichiedenteParent, IdRichiedente, IdSedeInterna, IdEtichetta);

-- Righe di importo di una risorsa: controllo di cancellazione della persona o dell'oggetto e chiave esterna
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiRigheServizi_IdOsepe')
	CREATE NONCLUSTERED INDEX IX_ImportiRigheServizi_IdOsepe ON dbo.tblImportiRigheServizi (IdOsepe);

COMMIT TRANSACTION;
GO

SELECT Id, IdModulo, Nome, Pos FROM dbo.tblImportiRigheTipi WHERE IdModulo = 'SRV' ORDER BY Pos;
GO
