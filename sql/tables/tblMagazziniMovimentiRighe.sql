SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMagazziniMovimentiRighe](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdMovimento] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdArticolo] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdCriterio] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Quantita] [decimal](18, 2) NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblMagazziniMovimentiRighe] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

-- IdSede è la vera Sede operativa (perimetro del magazzino), non l'Azienda.
ALTER TABLE [dbo].[tblMagazziniMovimentiRighe]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRighe_tblMagazziniMovimenti] FOREIGN KEY([IdMovimento])
REFERENCES [dbo].[tblMagazziniMovimenti] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRighe] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRighe_tblMagazziniMovimenti]
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRighe]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheArticoli_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRighe] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRigheArticoli_tblSedi]
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRighe]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRighe_tblMagazziniArticoli] FOREIGN KEY([IdArticolo])
REFERENCES [dbo].[tblMagazziniArticoli] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRighe] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRighe_tblMagazziniArticoli]
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRighe]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRighe_tblMagazziniCriteriScarichiLotti] FOREIGN KEY([IdCriterio])
REFERENCES [dbo].[tblMagazziniCriteriScarichiLotti] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRighe] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRighe_tblMagazziniCriteriScarichiLotti]
GO
