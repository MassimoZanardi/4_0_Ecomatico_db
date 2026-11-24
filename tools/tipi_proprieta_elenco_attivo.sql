-- Campi aggiuntivi dei tipi di scadenza e di servizio (decisioni dell'utente del 2026-11-24):
-- 1. tipo di campo "Elenco a scelta" (tblTipiDati L) e le voci dell'elenco del campo (tblTipiProprietaVoci): sull'evento
--    si salva il testo della voce (S3.7);
-- 2. campo disattivato (tblTipiProprieta.Attivo = 0): sparisce dalle schede dove e' vuoto, dove ha un valore resta in
--    sola lettura, non e' obbligatorio; i valori non si perdono e si puo' riattivare (S3.8);
-- 3. al massimo 20 campi per tipo in qualunque combinazione (S3.3, prima 5 per tipo di campo): 20 posti in tblProprieta
--    per ogni tipo di campo (B00-B19, D00-D19, I00-I19, L00-L19, S00-S19); il totale lo controlla uspTipi_ins_Proprieta.
-- Da installare prima delle SP e delle funzioni che leggono le nuove colonne e la nuova tabella. Si puo' rilanciare.
-- Eseguito su dev il 2026-11-24. NON ancora eseguito in produzione.

SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM dbo.tblTipiDati WHERE Id = 'L')
	INSERT dbo.tblTipiDati (Id, Nome) VALUES ('L', 'Elenco a scelta');

INSERT dbo.tblProprieta (Id, IdTipoDato)
SELECT n.Id, d.Id
FROM
	(VALUES ('B'), ('D'), ('I'), ('L'), ('S')) d (Id)
	CROSS JOIN (VALUES ('00'), ('01'), ('02'), ('03'), ('04'), ('05'), ('06'), ('07'), ('08'), ('09'),
		('10'), ('11'), ('12'), ('13'), ('14'), ('15'), ('16'), ('17'), ('18'), ('19')) g (Numero)
	CROSS APPLY (SELECT Id = CAST(d.Id + g.Numero AS CHAR(3))) n
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
SELECT IdTipoDato, Posti = COUNT(*) FROM dbo.tblProprieta GROUP BY IdTipoDato ORDER BY IdTipoDato;
SELECT COL_LENGTH('dbo.tblTipiProprieta', 'Attivo') AS Attivo, OBJECT_ID('dbo.tblTipiProprietaVoci', 'U') AS tblTipiProprietaVoci;
GO
