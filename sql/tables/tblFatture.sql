SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblFatture](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdClienteFornitore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdTipo] [char](4) COLLATE Latin1_General_CI_AS NULL,
	[IdStato] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdModalita] [char](4) COLLATE Latin1_General_CI_AS NULL,
	[IdRata] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdRataInizio] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdValuta] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdBancaCassa] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdFatturaRiferimento] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Tipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Numero] [int] NULL,
	[Sezionale] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[NumeroFornitore] [varchar](30) COLLATE Latin1_General_CI_AS NULL,
	[DataRegistrazione] [date] NULL,
	[DataEmissione] [date] NULL,
	[Causale] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	[Iban] [varchar](34) COLLATE Latin1_General_CI_AS NULL,
	[RataGiorniInizio] [int] NULL,
	[Ordine] [varchar](30) COLLATE Latin1_General_CI_AS NULL,
	[DataOrdine] [date] NULL,
	[SplitPayment] [bit] NULL,
	[Bollo] [decimal](9, 2) NULL,
	[CodiceCig] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[CodiceCup] [varchar](15) COLLATE Latin1_General_CI_AS NULL,
	[SolaLettura] [bit] NULL,
	[Lock] [tinyint] NULL,
	[DataXml] [smalldatetime] NULL,
	[ProgressivoXml] [varchar](5) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblFatture] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_tblFatture_IdClienteFornitore] ON [dbo].[tblFatture]
(
	[IdClienteFornitore] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_tblFatture_IdSede_Tipo_DataEmissione] ON [dbo].[tblFatture]
(
	[IdSede] ASC,
	[Tipo] ASC,
	[DataEmissione] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblFatture]  WITH CHECK ADD  CONSTRAINT [FK_tblFatture_tblBancheCasse] FOREIGN KEY([IdBancaCassa])
REFERENCES [dbo].[tblBancheCasse] ([Id])
GO

ALTER TABLE [dbo].[tblFatture] CHECK CONSTRAINT [FK_tblFatture_tblBancheCasse]
GO

ALTER TABLE [dbo].[tblFatture]  WITH CHECK ADD  CONSTRAINT [FK_tblFatture_tblClientiFornitori] FOREIGN KEY([IdClienteFornitore])
REFERENCES [dbo].[tblClientiFornitori] ([Id])
GO

ALTER TABLE [dbo].[tblFatture] CHECK CONSTRAINT [FK_tblFatture_tblClientiFornitori]
GO

ALTER TABLE [dbo].[tblFatture]  WITH CHECK ADD  CONSTRAINT [FK_tblFatture_tblFatture] FOREIGN KEY([IdFatturaRiferimento])
REFERENCES [dbo].[tblFatture] ([Id])
GO

ALTER TABLE [dbo].[tblFatture] CHECK CONSTRAINT [FK_tblFatture_tblFatture]
GO

ALTER TABLE [dbo].[tblFatture]  WITH CHECK ADD  CONSTRAINT [FK_tblFatture_tblFattureStati] FOREIGN KEY([IdStato])
REFERENCES [dbo].[tblFattureStati] ([Id])
GO

ALTER TABLE [dbo].[tblFatture] CHECK CONSTRAINT [FK_tblFatture_tblFattureStati]
GO

ALTER TABLE [dbo].[tblFatture]  WITH CHECK ADD  CONSTRAINT [FK_tblFatture_tblFattureTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblFattureTipi] ([Id])
GO

ALTER TABLE [dbo].[tblFatture] CHECK CONSTRAINT [FK_tblFatture_tblFattureTipi]
GO

ALTER TABLE [dbo].[tblFatture]  WITH CHECK ADD  CONSTRAINT [FK_tblFatture_tblPagamentiModalita] FOREIGN KEY([IdModalita])
REFERENCES [dbo].[tblPagamentiModalita] ([Id])
GO

ALTER TABLE [dbo].[tblFatture] CHECK CONSTRAINT [FK_tblFatture_tblPagamentiModalita]
GO

ALTER TABLE [dbo].[tblFatture]  WITH CHECK ADD  CONSTRAINT [FK_tblFatture_tblPagamentiRate] FOREIGN KEY([IdRata])
REFERENCES [dbo].[tblPagamentiRate] ([Id])
GO

ALTER TABLE [dbo].[tblFatture] CHECK CONSTRAINT [FK_tblFatture_tblPagamentiRate]
GO

ALTER TABLE [dbo].[tblFatture]  WITH CHECK ADD  CONSTRAINT [FK_tblFatture_tblPagamentiRateInizi] FOREIGN KEY([IdRataInizio])
REFERENCES [dbo].[tblPagamentiRateInizi] ([Id])
GO

ALTER TABLE [dbo].[tblFatture] CHECK CONSTRAINT [FK_tblFatture_tblPagamentiRateInizi]
GO

ALTER TABLE [dbo].[tblFatture]  WITH CHECK ADD  CONSTRAINT [FK_tblFatture_tblPagamentiValute] FOREIGN KEY([IdValuta])
REFERENCES [dbo].[tblPagamentiValute] ([Id])
GO

ALTER TABLE [dbo].[tblFatture] CHECK CONSTRAINT [FK_tblFatture_tblPagamentiValute]
GO

ALTER TABLE [dbo].[tblFatture]  WITH CHECK ADD  CONSTRAINT [FK_tblFatture_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblFatture] CHECK CONSTRAINT [FK_tblFatture_tblSedi]
GO
