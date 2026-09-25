-- Magazzino - relazioni carico/scarico, tranche 1: rimozione del vecchio modello ad
-- allocazioni riga->lotto (sostituito da IdLotto sulla riga di carico e da
-- tblMagazziniMovimentiRigheRelazioni). Da eseguire dopo le SP della tranche 1.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS dbo.uspMagazziniMovimentiRigheLotti_ins;
DROP PROCEDURE IF EXISTS dbo.uspMagazziniMovimentiRigheLotti_del;
DROP PROCEDURE IF EXISTS dbo.uspMagazziniMovimentiRigheLotti_get_List;
DROP PROCEDURE IF EXISTS dbo.uspMagazziniMovimentiRighe_esegui_Criterio;
GO

DROP TABLE IF EXISTS dbo.tblMagazziniMovimentiRigheLotti;
GO
