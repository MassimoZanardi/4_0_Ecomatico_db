SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiMagazzino](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdDestinatarioParent] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdDestinatario] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEtichetta] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSedePartenza] [char](16) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblImportiMagazzino] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_ImportiMagazzino_IdSede] ON [dbo].[tblImportiMagazzino]
(
	[IdSede] ASC
)
INCLUDE([IdSedePartenza],[IdDestinatarioParent],[IdDestinatario],[IdEtichetta]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImportiMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiMagazzino_tblEtichette] FOREIGN KEY([IdEtichetta])
REFERENCES [dbo].[tblEtichette] ([Id])
GO

ALTER TABLE [dbo].[tblImportiMagazzino] CHECK CONSTRAINT [FK_tblImportiMagazzino_tblEtichette]
GO

ALTER TABLE [dbo].[tblImportiMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiMagazzino_tblImporti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblImporti] ([Id])
GO

ALTER TABLE [dbo].[tblImportiMagazzino] CHECK CONSTRAINT [FK_tblImportiMagazzino_tblImporti]
GO

ALTER TABLE [dbo].[tblImportiMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdDestinatario] FOREIGN KEY([IdDestinatario])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiMagazzino] CHECK CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdDestinatario]
GO

ALTER TABLE [dbo].[tblImportiMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdDestinatarioParent] FOREIGN KEY([IdDestinatarioParent])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiMagazzino] CHECK CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdDestinatarioParent]
GO

ALTER TABLE [dbo].[tblImportiMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdSedePartenza] FOREIGN KEY([IdSedePartenza])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiMagazzino] CHECK CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdSedePartenza]
GO
