-- Magazzino - relazioni carico/scarico, tranche 2: le relazioni delle righe EoW si
-- costruiscono in uspMagazziniMovimenti_upd secondo il criterio (Manuale = lotto EoW scelto
-- sulla riga): l'esecuzione del criterio e l'allocazione manuale riga per riga non esistono più.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS dbo.uspMagazziniMovimentiRigheEoW_esegui_Criterio;
DROP PROCEDURE IF EXISTS dbo.uspMagazziniMovimentiRigheEoWLotti_ins;
DROP PROCEDURE IF EXISTS dbo.uspMagazziniMovimentiRigheEoWLotti_del;
GO
