SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiServizi](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdTipo] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdRichiedenteParent] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdRichiedente] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEtichetta] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSedeInterna] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblImportiServizi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_ImportiServizi_IdSede] ON [dbo].[tblImportiServizi]
(
	[IdSede] ASC
)
INCLUDE([IdTipo],[IdRichiedenteParent],[IdRichiedente],[IdSedeInterna],[IdEtichetta]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblEtichette] FOREIGN KEY([IdEtichetta])
REFERENCES [dbo].[tblEtichette] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblEtichette]
GO

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblImporti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblImporti] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblImporti]
GO

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblSedi_IdRichiedente] FOREIGN KEY([IdRichiedente])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblSedi_IdRichiedente]
GO

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblSedi_IdRichiedenteParent] FOREIGN KEY([IdRichiedenteParent])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblSedi_IdRichiedenteParent]
GO

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblSedi_IdSedeInterna] FOREIGN KEY([IdSedeInterna])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblSedi_IdSedeInterna]
GO

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblTipi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblTipi]
GO
