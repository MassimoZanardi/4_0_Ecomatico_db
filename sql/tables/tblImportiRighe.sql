SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiRighe](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdImporto] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdTipo] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Importo] [decimal](18, 4) NULL,
	[MinimoFatturabile] [bit] NULL,
	[Lock] [tinyint] NULL,
	[Pos] [int] NULL,
 CONSTRAINT [PK_tblImportiRighe] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_ImportiRighe_IdImporto] ON [dbo].[tblImportiRighe]
(
	[IdImporto] ASC
)
INCLUDE([Pos],[IdTipo],[Importo],[MinimoFatturabile],[Lock]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImportiRighe]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRighe_tblImporti] FOREIGN KEY([IdImporto])
REFERENCES [dbo].[tblImporti] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRighe] CHECK CONSTRAINT [FK_tblImportiRighe_tblImporti]
GO

ALTER TABLE [dbo].[tblImportiRighe]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRighe_tblImportiRigheTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblImportiRigheTipi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRighe] CHECK CONSTRAINT [FK_tblImportiRighe_tblImportiRigheTipi]
GO
