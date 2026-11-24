-- Campi aggiuntivi dei tipi di scadenza e di servizio (decisioni dell'utente del 2026-11-24):
-- 1. tipo di campo "Elenco a scelta" (tblTipiDati L) con 5 posti per tipo (tblProprieta L00-L04) e le voci dell'elenco
--    del campo (tblTipiProprietaVoci): sull'evento si salva il testo della voce (S3.7);
-- 2. campo disattivato (tblTipiProprieta.Attivo = 0): sparisce dalle schede dove e' vuoto, dove ha un valore resta in
--    sola lettura, non e' obbligatorio; i valori non si perdono e si puo' riattivare (S3.8).
-- Da installare prima delle SP e delle funzioni che leggono le nuove colonne e la nuova tabella. Si puo' rilanciare.
-- Eseguito su dev il 2026-11-24. NON ancora eseguito in produzione.

SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM dbo.tblTipiDati WHERE Id = 'L')
	INSERT dbo.tblTipiDati (Id, Nome) VALUES ('L', 'Elenco a scelta');

INSERT dbo.tblProprieta (Id, IdTipoDato)
SELECT n.Id, 'L'
FROM (VALUES ('L00'), ('L01'), ('L02'), ('L03'), ('L04')) n (Id)
WHERE NOT EXISTS (SELECT 1 FROM dbo.tblProprieta p WHERE p.Id = n.Id COLLATE Latin1_General_CI_AS);

IF COL_LENGTH('dbo.tblTipiProprieta', 'Attivo') IS NULL
	ALTER TABLE dbo.tblTipiProprieta ADD Attivo BIT NOT NULL CONSTRAINT DF_tblTipiProprieta_Attivo DEFAULT (1);
GO

IF OBJECT_ID('dbo.tblTipiProprietaVoci', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblTipiProprietaVoci (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdProprieta CHAR(3) COLLATE Latin1_General_CI_AS NOT NULL,
		Pos INT NOT NULL,
		Nome VARCHAR(50) COLLATE Latin1_General_CI_AS NOT NULL,
		CONSTRAINT PK_tblTipiProprietaVoci PRIMARY KEY CLUSTERED (Id ASC, IdProprieta ASC, Pos ASC),
		CONSTRAINT FK_tblTipiProprietaVoci_tblTipiProprieta FOREIGN KEY (Id, IdProprieta) REFERENCES dbo.tblTipiProprieta (Id, IdProprieta)
	);
	CREATE UNIQUE NONCLUSTERED INDEX UX_tblTipiProprietaVoci_Nome ON dbo.tblTipiProprietaVoci (Id ASC, IdProprieta ASC, Nome ASC);
END
GO

SELECT Id, Nome FROM dbo.tblTipiDati ORDER BY Id;
SELECT Id, IdTipoDato FROM dbo.tblProprieta WHERE IdTipoDato = 'L' ORDER BY Id;
SELECT COL_LENGTH('dbo.tblTipiProprieta', 'Attivo') AS Attivo, OBJECT_ID('dbo.tblTipiProprietaVoci', 'U') AS tblTipiProprietaVoci;
GO
