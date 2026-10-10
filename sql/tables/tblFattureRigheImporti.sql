SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblFattureRigheImporti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdAliquotaIva] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdConto] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdUnitaMisura] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Quantita] [decimal](18, 4) NULL,
	[Importo] [decimal](18, 4) NULL,
	[RitenutaAcconto] [int] NULL,
 CONSTRAINT [PK_tblFattureRigheImporti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblFattureRigheImporti]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureRigheImporti_tblAliquoteIva] FOREIGN KEY([IdAliquotaIva])
REFERENCES [dbo].[tblAliquoteIva] ([Id])
GO

ALTER TABLE [dbo].[tblFattureRigheImporti] CHECK CONSTRAINT [FK_tblFattureRigheImporti_tblAliquoteIva]
GO

ALTER TABLE [dbo].[tblFattureRigheImporti]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureRigheImporti_tblFattureConti] FOREIGN KEY([IdConto])
REFERENCES [dbo].[tblFattureConti] ([Id])
GO

ALTER TABLE [dbo].[tblFattureRigheImporti] CHECK CONSTRAINT [FK_tblFattureRigheImporti_tblFattureConti]
GO

ALTER TABLE [dbo].[tblFattureRigheImporti]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureRigheImporti_tblFattureRighe] FOREIGN KEY([Id])
REFERENCES [dbo].[tblFattureRighe] ([Id])
GO

ALTER TABLE [dbo].[tblFattureRigheImporti] CHECK CONSTRAINT [FK_tblFattureRigheImporti_tblFattureRighe]
GO

ALTER TABLE [dbo].[tblFattureRigheImporti]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureRigheImporti_tblUnitaMisura] FOREIGN KEY([IdUnitaMisura])
REFERENCES [dbo].[tblUnitaMisura] ([Id])
GO

ALTER TABLE [dbo].[tblFattureRigheImporti] CHECK CONSTRAINT [FK_tblFattureRigheImporti_tblUnitaMisura]
GO
