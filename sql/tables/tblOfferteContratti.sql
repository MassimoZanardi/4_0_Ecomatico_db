SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblOfferteContratti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdClienteFornitore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Tipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[ClienteFornitoreTipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[DataInizio] [date] NULL,
	[DataFine] [date] NULL,
	[Descrizione] [varchar](1000) COLLATE Latin1_General_CI_AS NULL,
	[Protocollo] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Ordine] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[DataOrdine] [date] NULL,
	[CodiceCig] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[CodiceCup] [varchar](15) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblOfferteContratti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_OfferteContratti_IdClienteFornitore] ON [dbo].[tblOfferteContratti]
(
	[IdClienteFornitore] ASC
)
INCLUDE([Lock]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_OfferteContratti_IdSede] ON [dbo].[tblOfferteContratti]
(
	[IdSede] ASC
)
INCLUDE([IdClienteFornitore],[Tipo],[Lock]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblOfferteContratti]  WITH CHECK ADD  CONSTRAINT [FK_tblOfferteContratti_tblClientiFornitori] FOREIGN KEY([IdClienteFornitore])
REFERENCES [dbo].[tblClientiFornitori] ([Id])
GO

ALTER TABLE [dbo].[tblOfferteContratti] CHECK CONSTRAINT [FK_tblOfferteContratti_tblClientiFornitori]
GO

ALTER TABLE [dbo].[tblOfferteContratti]  WITH CHECK ADD  CONSTRAINT [FK_tblOfferteContratti_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblOfferteContratti] CHECK CONSTRAINT [FK_tblOfferteContratti_tblSedi]
GO
