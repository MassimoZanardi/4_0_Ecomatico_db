SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblEoWMaterialiRegistri](
	[IdMateriale] [char](2) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRegistro] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdLotto] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdImballo] [char](2) COLLATE Latin1_General_CI_AS NOT NULL
 CONSTRAINT [PK_tblEoWMaterialiRegistri] PRIMARY KEY CLUSTERED 
(
	[IdMateriale] ASC,
	[IdRegistro] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblEoWMaterialiRegistri]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWMaterialiLotti_tblEoWLotti] FOREIGN KEY([IdLotto])
REFERENCES [dbo].[tblEoWLotti] ([Id])
GO

ALTER TABLE [dbo].[tblEoWMaterialiRegistri] CHECK CONSTRAINT [FK_tblEoWMaterialiLotti_tblEoWLotti]
GO

ALTER TABLE [dbo].[tblEoWMaterialiRegistri]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWMaterialiLotti_tblRifiutiMateriali] FOREIGN KEY([IdMateriale])
REFERENCES [dbo].[tblRifiutiMateriali] ([Id])
GO

ALTER TABLE [dbo].[tblEoWMaterialiRegistri] CHECK CONSTRAINT [FK_tblEoWMaterialiLotti_tblRifiutiMateriali]
GO

ALTER TABLE [dbo].[tblEoWMaterialiRegistri]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWMaterialiLotti_tblRifiutiRegistri] FOREIGN KEY([IdRegistro])
REFERENCES [dbo].[tblRifiutiRegistri] ([Id])
GO

ALTER TABLE [dbo].[tblEoWMaterialiRegistri] CHECK CONSTRAINT [FK_tblEoWMaterialiLotti_tblRifiutiRegistri]
GO

ALTER TABLE [dbo].[tblEoWMaterialiRegistri]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWMaterialiRegistri_tblImballi] FOREIGN KEY([IdImballo])
REFERENCES [dbo].[tblImballi] ([Id])
GO

ALTER TABLE [dbo].[tblEoWMaterialiRegistri] CHECK CONSTRAINT [FK_tblEoWMaterialiRegistri_tblImballi]
GO

