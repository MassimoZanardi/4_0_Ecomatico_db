SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMagazziniMovimentiRigheEoW](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdMovimento] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdMateriale] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdCriterio] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Quantita] [decimal](18, 2) NULL,
	[Lock] [tinyint] NULL,
	[IdLotto] [char](16) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblMagazziniMovimentiRigheEoW] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

-- ATTENZIONE: IdMovimento NON ha vincolo FK verso tblMagazziniMovimenti (asimmetria
-- rispetto a tblMagazziniMovimentiRighe, che invece ce l'ha) - verificato sullo schema
-- reale, non un refuso di questo backfill. Va validato in SP (THROW 50001), non a
-- livello di vincolo DB.
ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoW]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheEoW_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoW] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRigheEoW_tblSedi]
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoW]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheEoW_tblRifiutiMateriali] FOREIGN KEY([IdMateriale])
REFERENCES [dbo].[tblRifiutiMateriali] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoW] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRigheEoW_tblRifiutiMateriali]
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoW]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheEoW_tblMagazziniCriteriScarichiLotti] FOREIGN KEY([IdCriterio])
REFERENCES [dbo].[tblMagazziniCriteriScarichiLotti] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoW] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRigheEoW_tblMagazziniCriteriScarichiLotti]
GO

-- IdLotto: lotto EoW da cui scaricare, valorizzato solo con il criterio Manuale (validato in
-- uspMagazziniMovimentiRigheEoW_ins).
ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoW]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheEoW_tblEoWLotti] FOREIGN KEY([IdLotto])
REFERENCES [dbo].[tblEoWLotti] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheEoW] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRigheEoW_tblEoWLotti]
GO
