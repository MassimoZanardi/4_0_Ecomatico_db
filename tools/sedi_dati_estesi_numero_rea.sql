-- tblSediDatiEstesi: la colonna CodiceRea diventa NumeroRea, lo stesso nome di tblFattureDatiFiscali.NumeroRea
-- ("numero REA" è il termine ufficiale). Restano due dati distinti: questo è il numero dell'unità locale,
-- salvato dal MUD; quello dei dati fiscali è il numero dell'azienda, usato dalla fattura elettronica.
-- Script idempotente: rieseguibile senza effetti su un DB che ha già la colonna rinominata.
SET NOCOUNT ON;
GO
IF COL_LENGTH('dbo.tblSediDatiEstesi', 'CodiceRea') IS NOT NULL
	AND COL_LENGTH('dbo.tblSediDatiEstesi', 'NumeroRea') IS NULL
	EXEC sp_rename 'dbo.tblSediDatiEstesi.CodiceRea', 'NumeroRea', 'COLUMN';
GO
