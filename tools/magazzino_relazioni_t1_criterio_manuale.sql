-- Magazzino - relazioni carico/scarico, tranche 1: criterio di scarico Manuale esplicito.
-- Prima il Manuale era rappresentato da IdCriterio NULL, non distinguibile da "non
-- selezionato": ora il criterio della riga di scarico è obbligatorio e 'M' indica la scelta
-- diretta del lotto nella modale "Aggiungi riga" (IdLotto sulla riga di scarico).
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT 1 FROM dbo.tblMagazziniCriteriScarichiLotti WHERE Id = 'M')
	INSERT dbo.tblMagazziniCriteriScarichiLotti (Id, Nome, Pos)
	VALUES ('M', 'Manuale: scarica dal lotto selezionato', 0);
GO

-- Il Manuale sceglie il lotto direttamente sulla riga: l'associazione manuale dei carichi
-- in un secondo passaggio (modale "Carichi associabili") non esiste più
DROP PROCEDURE IF EXISTS dbo.uspMagazziniMovimentiRigheRelazioni_ins;
DROP PROCEDURE IF EXISTS dbo.uspMagazziniMovimentiRigheRelazioni_del;
DROP PROCEDURE IF EXISTS dbo.uspMagazziniMovimentiRighe_get_CarichiDaAssociare_List;
GO
