SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Etichette del modulo Magazzino, applicabili solo ai DDT.
--   1. La funzione ETC "Etichette" entra nel modulo MAG e la voce Etichette nel menu Magazzino, in coda
--      (la pagina ETC e le SP uspEtichette_* sono comuni ai moduli: il modulo arriva in @IdModulo).
--   2. tblMagazziniDdtEtichette: etichette assegnate al DDT. Le due chiavi esterne sono ON DELETE CASCADE:
--      cancellato il DDT (bozza abbandonata, cancellazioni a cascata) o l'etichetta, il legame sparisce da solo,
--      senza dover toccare ogni SP che cancella un DDT.
--   3. tblMagazziniDdt.Etichette: JSON delle etichette per gli elenchi (ufnMagazziniDdt_get_Etichette), come
--      sulle registrazioni e sui formulari dei rifiuti.
-- Rieseguibile.

BEGIN TRANSACTION;

-- 1. Funzione nel modulo e voce di menu
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'MAG' AND IdFunzione = 'ETC')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('MAG', 'ETC');

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AI6')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AI6', 'AI0', NULL, 'ETC', 5);

-- 2. Etichette del DDT
IF OBJECT_ID('dbo.tblMagazziniDdtEtichette', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblMagazziniDdtEtichette (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdEtichetta CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		CONSTRAINT PK_tblMagazziniDdtEtichette PRIMARY KEY CLUSTERED (Id ASC, IdEtichetta ASC)
	);

	ALTER TABLE dbo.tblMagazziniDdtEtichette WITH CHECK ADD CONSTRAINT FK_tblMagazziniDdtEtichette_tblMagazziniDdt
		FOREIGN KEY (Id) REFERENCES dbo.tblMagazziniDdt (Id) ON DELETE CASCADE;
	ALTER TABLE dbo.tblMagazziniDdtEtichette WITH CHECK ADD CONSTRAINT FK_tblMagazziniDdtEtichette_tblEtichette
		FOREIGN KEY (IdEtichetta) REFERENCES dbo.tblEtichette (Id) ON DELETE CASCADE;

	-- DDT di un'etichetta: rinomina, cancellazione e ripristino dell'etichetta, importi con l'etichetta
	CREATE NONCLUSTERED INDEX IX_MagazziniDdtEtichette_IdEtichetta ON dbo.tblMagazziniDdtEtichette (IdEtichetta);
END

-- 3. JSON delle etichette sul DDT
IF COL_LENGTH('dbo.tblMagazziniDdt', 'Etichette') IS NULL
	ALTER TABLE dbo.tblMagazziniDdt ADD Etichette VARCHAR(2000) COLLATE Latin1_General_CI_AS NULL;

COMMIT TRANSACTION;
GO

SELECT m.Id, m.Pos, p.Nome, p.IdFunzione
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
WHERE m.IdParent = 'AI0'
ORDER BY m.Pos;
GO
