SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblFattureRatePagamenti](
	[IdRata] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdPagamento] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Importo] [decimal](18, 2) NULL,
 CONSTRAINT [PK_tblFattureRatePagamenti] PRIMARY KEY CLUSTERED 
(
	[IdRata] ASC,
	[IdPagamento] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblFattureRatePagamenti]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureRatePagamenti_tblFattureRate] FOREIGN KEY([IdRata])
REFERENCES [dbo].[tblFattureRate] ([Id])
GO

ALTER TABLE [dbo].[tblFattureRatePagamenti] CHECK CONSTRAINT [FK_tblFattureRatePagamenti_tblFattureRate]
GO

ALTER TABLE [dbo].[tblFattureRatePagamenti]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureRatePagamenti_tblPagamenti] FOREIGN KEY([IdPagamento])
REFERENCES [dbo].[tblPagamenti] ([Id])
GO

ALTER TABLE [dbo].[tblFattureRatePagamenti] CHECK CONSTRAINT [FK_tblFattureRatePagamenti_tblPagamenti]
GO
