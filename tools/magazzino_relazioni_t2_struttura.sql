-- Magazzino - relazioni carico/scarico, tranche 2 (righe EoW): struttura.
-- Per l'EoW il "carico" è il lotto EoW (quote delle registrazioni rifiuti M attribuite,
-- tblEoWLottiRifiutiRegistrazioni): la riga EoW di scarico si relaziona ai lotti EoW che
-- consuma riusando tblMagazziniMovimentiRigheEoWLotti (Id = riga, IdLotto, Quantita), con
-- Pos = ordine di consumo dal criterio. IdLotto sulla riga EoW = lotto scelto con il
-- criterio Manuale.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF COL_LENGTH('dbo.tblMagazziniMovimentiRigheEoW', 'IdLotto') IS NULL
	ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoW] ADD [IdLotto] [char](16) COLLATE Latin1_General_CI_AS NULL;
GO

IF OBJECT_ID('dbo.FK_tblMagazziniMovimentiRigheEoW_tblEoWLotti', 'F') IS NULL
	ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoW]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheEoW_tblEoWLotti] FOREIGN KEY([IdLotto])
	REFERENCES [dbo].[tblEoWLotti] ([Id]);
GO

IF COL_LENGTH('dbo.tblMagazziniMovimentiRigheEoWLotti', 'Pos') IS NULL
	ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoWLotti] ADD [Pos] [int] NULL;
GO
