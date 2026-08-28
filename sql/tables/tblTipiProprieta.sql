SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblTipiProprieta](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdProprieta] [char](3) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Pos] [int] NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblServiziTipiProprieta] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdProprieta] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblTipiProprieta]  WITH CHECK ADD  CONSTRAINT [FK_tblTipiProprieta_tblProprieta] FOREIGN KEY([IdProprieta])
REFERENCES [dbo].[tblProprieta] ([Id])
GO

ALTER TABLE [dbo].[tblTipiProprieta] CHECK CONSTRAINT [FK_tblTipiProprieta_tblProprieta]
GO

ALTER TABLE [dbo].[tblTipiProprieta]  WITH CHECK ADD  CONSTRAINT [FK_tblTipiProprieta_tblTipi] FOREIGN KEY([Id])
REFERENCES [dbo].[tblTipi] ([Id])
GO

ALTER TABLE [dbo].[tblTipiProprieta] CHECK CONSTRAINT [FK_tblTipiProprieta_tblTipi]