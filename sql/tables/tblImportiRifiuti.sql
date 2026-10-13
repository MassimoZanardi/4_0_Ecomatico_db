SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiRifiuti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NULL,
	[IdProduttoreParent] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdProduttore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdTrasportatore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdDestinatario] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdIntermediario] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEtichetta] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblImportiRifiuti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_ImportiRifiuti_IdSede] ON [dbo].[tblImportiRifiuti]
(
	[IdSede] ASC
)
INCLUDE([IdEer],[IdProduttoreParent],[IdProduttore],[IdTrasportatore],[IdDestinatario],[IdIntermediario],[IdEtichetta]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblEtichette] FOREIGN KEY([IdEtichetta])
REFERENCES [dbo].[tblEtichette] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblEtichette]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblImporti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblImporti] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblImporti]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblRifiutiEer] FOREIGN KEY([IdEer])
REFERENCES [dbo].[tblRifiutiEer] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblRifiutiEer]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdDestinatario] FOREIGN KEY([IdDestinatario])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdDestinatario]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdIntermediario] FOREIGN KEY([IdIntermediario])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdIntermediario]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdProduttore] FOREIGN KEY([IdProduttore])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdProduttore]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdProduttoreParent] FOREIGN KEY([IdProduttoreParent])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdProduttoreParent]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdTrasportatore] FOREIGN KEY([IdTrasportatore])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdTrasportatore]
GO
