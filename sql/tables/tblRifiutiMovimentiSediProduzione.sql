SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiMovimentiSediProduzione](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Quantita] [decimal](18, 2) NULL,
	[Pos] [tinyint] NULL,
 CONSTRAINT [PK_tblRifiutiMovimentiSediProduzione] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdSede] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RifiutiMovimentiSediProduzione_IdSede] ON [dbo].[tblRifiutiMovimentiSediProduzione]
(
	[IdSede] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiMovimentiSediProduzione]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimentiSediProduzione_tblRifiutiMovimenti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiMovimenti] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiSediProduzione] CHECK CONSTRAINT [FK_tblRifiutiMovimentiSediProduzione_tblRifiutiMovimenti]
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiSediProduzione]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimentiSediProduzione_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiSediProduzione] CHECK CONSTRAINT [FK_tblRifiutiMovimentiSediProduzione_tblSedi]
GO
