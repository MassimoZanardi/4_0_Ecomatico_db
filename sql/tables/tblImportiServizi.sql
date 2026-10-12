SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiServizi](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdTipo] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdRichiedenteParent] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdRichiedente] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEsecutore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEtichetta] [char](16) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblImportiServizi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

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

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblSedi_IdEsecutore] FOREIGN KEY([IdEsecutore])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblSedi_IdEsecutore]
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

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblTipi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblTipi]
GO
