SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- NOTA: [Id] qui è la FK alla riga EoW padre (tblMagazziniMovimentiRigheEoW.Id), non un
-- id proprio. PK composita (Id, IdLotto). IdLotto riferisce i Lotti EoW ESISTENTI
-- (tblEoWLotti) - il modulo Magazzino non crea una propria anagrafica lotti EoW.
CREATE TABLE [dbo].[tblMagazziniMovimentiRigheEoWLotti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdLotto] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Quantita] [decimal](18, 2) NULL,
 CONSTRAINT [PK_tblMagazziniMovimentiRigheEoWLotti] PRIMARY KEY CLUSTERED
(
	[Id] ASC,
	[IdLotto] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoWLotti]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheEoWLotti_tblMagazziniMovimentiRigheEoW] FOREIGN KEY([Id])
REFERENCES [dbo].[tblMagazziniMovimentiRigheEoW] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoWLotti] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRigheEoWLotti_tblMagazziniMovimentiRigheEoW]
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoWLotti]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheEoWLotti_tblEoWLotti] FOREIGN KEY([IdLotto])
REFERENCES [dbo].[tblEoWLotti] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoWLotti] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRigheEoWLotti_tblEoWLotti]
GO
