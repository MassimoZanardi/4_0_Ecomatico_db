SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPagamenti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdBancaCassa] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdModalita] [char](4) COLLATE Latin1_General_CI_AS NULL,
	[Tipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Causale] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[DataRegistrazione] [date] NULL,
	[DataContabile] [date] NULL,
	[Importo] [decimal](18, 2) NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblPagamenti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[tblPagamenti]  WITH CHECK ADD  CONSTRAINT [FK_tblPagamenti_tblBancheCasse] FOREIGN KEY([IdBancaCassa])
REFERENCES [dbo].[tblBancheCasse] ([Id])
GO
ALTER TABLE [dbo].[tblPagamenti] CHECK CONSTRAINT [FK_tblPagamenti_tblBancheCasse]
GO
ALTER TABLE [dbo].[tblPagamenti]  WITH CHECK ADD  CONSTRAINT [FK_tblPagamenti_tblPagamentiModalita] FOREIGN KEY([IdModalita])
REFERENCES [dbo].[tblPagamentiModalita] ([Id])
GO
ALTER TABLE [dbo].[tblPagamenti] CHECK CONSTRAINT [FK_tblPagamenti_tblPagamentiModalita]
GO
ALTER TABLE [dbo].[tblPagamenti]  WITH CHECK ADD  CONSTRAINT [FK_tblPagamenti_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO
ALTER TABLE [dbo].[tblPagamenti] CHECK CONSTRAINT [FK_tblPagamenti_tblSedi]
GO
