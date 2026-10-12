SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblClientiFornitori](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdAziendaInterna] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Tipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdModalita] [char](4) COLLATE Latin1_General_CI_AS NULL,
	[IdRata] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdRataInizio] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdBancaCassa] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdAliquotaIva] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdValuta] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[SplitPayment] [bit] NULL,
	[Iban] [varchar](34) COLLATE Latin1_General_CI_AS NULL,
	[RataGiorniInizio] [int] NULL,
	[ImportoMinimoFatturabile] [decimal](18, 2) NULL,
	[RitenutaAcconto] [int] NULL,
	[CodiceDestinatario] [varchar](7) COLLATE Latin1_General_CI_AS NULL,
	[PecDestinatario] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[Note] [varchar](1000) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
	[IdRaggruppamento] [char](1) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblClientiFornitori] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_ClientiFornitori_IdSede] ON [dbo].[tblClientiFornitori]
(
	[IdSede] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE UNIQUE NONCLUSTERED INDEX [UX_ClientiFornitori_IdAziendaInterna_IdSede_Tipo_Lock] ON [dbo].[tblClientiFornitori]
(
	[IdAziendaInterna] ASC,
	[IdSede] ASC,
	[Tipo] ASC
)
WHERE ([Lock]=(0))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblAliquoteIva] FOREIGN KEY([IdAliquotaIva])
REFERENCES [dbo].[tblAliquoteIva] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblAliquoteIva]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblBancheCasse] FOREIGN KEY([IdBancaCassa])
REFERENCES [dbo].[tblBancheCasse] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblBancheCasse]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblFattureRaggruppamenti] FOREIGN KEY([IdRaggruppamento])
REFERENCES [dbo].[tblFattureRaggruppamenti] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblFattureRaggruppamenti]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblPagamentiModalita] FOREIGN KEY([IdModalita])
REFERENCES [dbo].[tblPagamentiModalita] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblPagamentiModalita]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblPagamentiRate] FOREIGN KEY([IdRata])
REFERENCES [dbo].[tblPagamentiRate] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblPagamentiRate]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblPagamentiRateInizi] FOREIGN KEY([IdRataInizio])
REFERENCES [dbo].[tblPagamentiRateInizi] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblPagamentiRateInizi]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblPagamentiValute] FOREIGN KEY([IdValuta])
REFERENCES [dbo].[tblPagamentiValute] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblPagamentiValute]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblSedi_IdAziendaInterna] FOREIGN KEY([IdAziendaInterna])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblSedi_IdAziendaInterna]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblSedi_IdSede] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblSedi_IdSede]
GO
