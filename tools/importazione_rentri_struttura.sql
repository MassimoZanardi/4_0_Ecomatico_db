-- Rentri > Importazione (registrazioni trasmesse a RENTRI da altri gestionali): oggetti di struttura e dati di
-- configurazione da installare prima delle SP uspRentriImportazioni_*. Le tabelle si creano una volta sola (CREATE TABLE);
-- le righe del menu si inseriscono solo se mancano.
-- Tabelle: sql/tables/tblRentriImportazioni*.sql (area temporanea dell'importazione).

:r ..\sql\tables\tblRentriImportazioni.sql
:r ..\sql\tables\tblRentriImportazioniMovimenti.sql
:r ..\sql\tables\tblRentriImportazioniCausali.sql
:r ..\sql\tables\tblRentriImportazioniAnomalie.sql
:r ..\sql\tables\tblRentriImportazioniRelazioni.sql
:r ..\sql\tables\tblRentriImportazioniSoggetti.sql
:r ..\sql\tables\tblRentriImportazioniMovimentiSoggetti.sql

-- Voce di menu Rentri > Importazione, sotto la funzione RNT (configurazione RENTRI, solo amministratori)
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'RIM')
	INSERT dbo.tblPagine (Id, IdFunzione, Nome, Url, Note, IdModulo)
	VALUES ('RIM', 'RNT', 'Importazione', NULL, NULL, NULL);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AG6')
	INSERT dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos)
	VALUES ('AG6', 'AG0', NULL, 'RIM', 5);
GO
