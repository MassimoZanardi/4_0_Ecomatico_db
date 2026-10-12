SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblFattureDocumenti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdModulo] [char](3) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdFattura] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdClienteFornitore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdImporto] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdOffertaContratto] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[NonFatturabile] [bit] NULL,
 CONSTRAINT [PK_tblFattureDocumenti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_FattureDocumenti_IdFattura] ON [dbo].[tblFattureDocumenti]
(
	[IdFattura] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblFattureDocumenti]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureDocumenti_tblClientiFornitori] FOREIGN KEY([IdClienteFornitore])
REFERENCES [dbo].[tblClientiFornitori] ([Id])
GO

ALTER TABLE [dbo].[tblFattureDocumenti] CHECK CONSTRAINT [FK_tblFattureDocumenti_tblClientiFornitori]
GO

ALTER TABLE [dbo].[tblFattureDocumenti]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureDocumenti_tblFatture] FOREIGN KEY([IdFattura])
REFERENCES [dbo].[tblFatture] ([Id])
GO

ALTER TABLE [dbo].[tblFattureDocumenti] CHECK CONSTRAINT [FK_tblFattureDocumenti_tblFatture]
GO

ALTER TABLE [dbo].[tblFattureDocumenti]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureDocumenti_tblId] FOREIGN KEY([Id])
REFERENCES [dbo].[tblId] ([Id])
GO

ALTER TABLE [dbo].[tblFattureDocumenti] CHECK CONSTRAINT [FK_tblFattureDocumenti_tblId]
GO

ALTER TABLE [dbo].[tblFattureDocumenti]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureDocumenti_tblImporti] FOREIGN KEY([IdImporto])
REFERENCES [dbo].[tblImporti] ([Id])
GO

ALTER TABLE [dbo].[tblFattureDocumenti] CHECK CONSTRAINT [FK_tblFattureDocumenti_tblImporti]
GO

ALTER TABLE [dbo].[tblFattureDocumenti]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureDocumenti_tblModuli] FOREIGN KEY([IdModulo])
REFERENCES [dbo].[tblModuli] ([Id])
GO

ALTER TABLE [dbo].[tblFattureDocumenti] CHECK CONSTRAINT [FK_tblFattureDocumenti_tblModuli]
GO

ALTER TABLE [dbo].[tblFattureDocumenti]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureDocumenti_tblOfferteContratti] FOREIGN KEY([IdOffertaContratto])
REFERENCES [dbo].[tblOfferteContratti] ([Id])
GO

ALTER TABLE [dbo].[tblFattureDocumenti] CHECK CONSTRAINT [FK_tblFattureDocumenti_tblOfferteContratti]
GO
