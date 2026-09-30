-- Magazzino EoW allineato al registro operativo (tranche 3): struttura.
-- Pos = ordine di riempimento delle allocazioni di una registrazione M (max+1 a ogni nuovo lotto):
-- quando la quantita' operativa della M scende, le allocazioni si riducono partendo dall'ultimo lotto
-- riempito (Pos piu' alta). Le righe gia' esistenti restano NULL (ordine di ripiego: DataApertura del lotto).
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF COL_LENGTH('dbo.tblEoWLottiRifiutiRegistrazioni', 'Pos') IS NULL
	ALTER TABLE [dbo].[tblEoWLottiRifiutiRegistrazioni] ADD [Pos] [int] NULL;
GO
