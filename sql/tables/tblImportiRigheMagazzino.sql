SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiRigheMagazzino](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdArticolo] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdMateriale] [char](2) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblImportiRigheMagazzino] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_ImportiRigheMagazzino_IdArticolo] ON [dbo].[tblImportiRigheMagazzino]
(
	[IdArticolo] ASC
)
WHERE ([IdArticolo] IS NOT NULL)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImportiRigheMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRigheMagazzino_tblImportiRighe] FOREIGN KEY([Id])
REFERENCES [dbo].[tblImportiRighe] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblImportiRigheMagazzino] CHECK CONSTRAINT [FK_tblImportiRigheMagazzino_tblImportiRighe]
GO

ALTER TABLE [dbo].[tblImportiRigheMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRigheMagazzino_tblMagazziniArticoli] FOREIGN KEY([IdArticolo])
REFERENCES [dbo].[tblMagazziniArticoli] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRigheMagazzino] CHECK CONSTRAINT [FK_tblImportiRigheMagazzino_tblMagazziniArticoli]
GO

ALTER TABLE [dbo].[tblImportiRigheMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRigheMagazzino_tblRifiutiMateriali] FOREIGN KEY([IdMateriale])
REFERENCES [dbo].[tblRifiutiMateriali] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRigheMagazzino] CHECK CONSTRAINT [FK_tblImportiRigheMagazzino_tblRifiutiMateriali]
GO
