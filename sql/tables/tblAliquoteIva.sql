SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblAliquoteIva](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdTipo] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdNatura] [varchar](4) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Codice] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[Valore] [decimal](9, 2) NULL,
	[Lock] [tinyint] NULL,
	[RiferimentoNormativo] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblAliquoteIva] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[tblAliquoteIva]  WITH CHECK ADD  CONSTRAINT [FK_tblAliquoteIva_tblAliquoteIvaNatura] FOREIGN KEY([IdNatura])
REFERENCES [dbo].[tblAliquoteIvaNatura] ([Id])
GO
ALTER TABLE [dbo].[tblAliquoteIva] CHECK CONSTRAINT [FK_tblAliquoteIva_tblAliquoteIvaNatura]
GO
ALTER TABLE [dbo].[tblAliquoteIva]  WITH CHECK ADD  CONSTRAINT [FK_tblAliquoteIva_tblAliquoteIvaTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblAliquoteIvaTipi] ([Id])
GO
ALTER TABLE [dbo].[tblAliquoteIva] CHECK CONSTRAINT [FK_tblAliquoteIva_tblAliquoteIvaTipi]
GO
ALTER TABLE [dbo].[tblAliquoteIva]  WITH CHECK ADD  CONSTRAINT [FK_tblAliquoteIva_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO
ALTER TABLE [dbo].[tblAliquoteIva] CHECK CONSTRAINT [FK_tblAliquoteIva_tblSedi]
GO
