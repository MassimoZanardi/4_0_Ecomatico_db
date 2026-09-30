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

-- Metodo con cui e' nata l'allocazione (U = Lotto unico, P = Percentuale, C = Priorita'/capacita'; NULL = manuale):
-- la riduzione automatica rispetta il metodo (percentuale in proporzione, priorita' e manuale dall'ultimo lotto
-- riempito). Salvato il tipo e non l'allocazione configurata, che puo' essere cancellata fisicamente.
IF COL_LENGTH('dbo.tblEoWLottiRifiutiRegistrazioni', 'IdAllocazioneTipo') IS NULL
	ALTER TABLE [dbo].[tblEoWLottiRifiutiRegistrazioni] ADD [IdAllocazioneTipo] [char](1) COLLATE Latin1_General_CI_AS NULL;
GO

IF OBJECT_ID('dbo.FK_tblEoWLottiRifiutiRegistrazioni_tblEoWAllocazioniTipi', 'F') IS NULL
	ALTER TABLE [dbo].[tblEoWLottiRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWLottiRifiutiRegistrazioni_tblEoWAllocazioniTipi] FOREIGN KEY([IdAllocazioneTipo])
	REFERENCES [dbo].[tblEoWAllocazioniTipi] ([Id]);
GO
