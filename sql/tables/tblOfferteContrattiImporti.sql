SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblOfferteContrattiImporti](
	[IdOffertaContratto] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdImporto] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblOfferteContrattiImporti] PRIMARY KEY CLUSTERED 
(
	[IdOffertaContratto] ASC,
	[IdImporto] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE UNIQUE NONCLUSTERED INDEX [UX_OfferteContrattiImporti_IdImporto] ON [dbo].[tblOfferteContrattiImporti]
(
	[IdImporto] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblOfferteContrattiImporti]  WITH CHECK ADD  CONSTRAINT [FK_tblOfferteContrattiImporti_tblImporti] FOREIGN KEY([IdImporto])
REFERENCES [dbo].[tblImporti] ([Id])
GO

ALTER TABLE [dbo].[tblOfferteContrattiImporti] CHECK CONSTRAINT [FK_tblOfferteContrattiImporti_tblImporti]
GO

ALTER TABLE [dbo].[tblOfferteContrattiImporti]  WITH CHECK ADD  CONSTRAINT [FK_tblOfferteContrattiImporti_tblOfferteContratti] FOREIGN KEY([IdOffertaContratto])
REFERENCES [dbo].[tblOfferteContratti] ([Id])
GO

ALTER TABLE [dbo].[tblOfferteContrattiImporti] CHECK CONSTRAINT [FK_tblOfferteContrattiImporti_tblOfferteContratti]
GO
