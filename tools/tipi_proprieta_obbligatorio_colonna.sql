-- Campi aggiuntivi dei tipi (tblTipiProprieta): campo obbligatorio per segnare come eseguito un servizio o una scadenza
-- (S3.6, decisione dell'utente del 2026-11-23). 0 = facoltativo, come tutti i campi prima di questa modifica.
-- Da installare prima delle SP e della funzione che leggono la colonna. Si puo' rilanciare.
-- Eseguito su dev il 2026-11-23. NON ancora eseguito in produzione.

IF COL_LENGTH('dbo.tblTipiProprieta', 'Obbligatorio') IS NULL
	ALTER TABLE dbo.tblTipiProprieta ADD Obbligatorio BIT NOT NULL CONSTRAINT DF_tblTipiProprieta_Obbligatorio DEFAULT (0);
GO

SELECT COL_LENGTH('dbo.tblTipiProprieta', 'Obbligatorio') AS Obbligatorio;
GO
