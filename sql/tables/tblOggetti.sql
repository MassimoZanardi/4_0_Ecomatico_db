SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblOggetti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdUnitaMisura] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdTipo] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Codice] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[Descrizione] [varchar](500) COLLATE Latin1_General_CI_AS NULL,
	[ImpiegabileServizi] [bit] NULL,
	[Disabilitata] [bit] NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblOggetti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblOggetti]  WITH CHECK ADD  CONSTRAINT [FK_tblOggetti_tblOggettiTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblOggettiTipi] ([Id])
GO

ALTER TABLE [dbo].[tblOggetti] CHECK CONSTRAINT [FK_tblOggetti_tblOggettiTipi]
GO

ALTER TABLE [dbo].[tblOggetti]  WITH CHECK ADD  CONSTRAINT [FK_tblOggetti_tblOsepe] FOREIGN KEY([Id])
REFERENCES [dbo].[tblOsepe] ([Id])
GO

ALTER TABLE [dbo].[tblOggetti] CHECK CONSTRAINT [FK_tblOggetti_tblOsepe]
GO

ALTER TABLE [dbo].[tblOggetti]  WITH CHECK ADD  CONSTRAINT [FK_tblOggetti_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblOggetti] CHECK CONSTRAINT [FK_tblOggetti_tblSedi]
GO

ALTER TABLE [dbo].[tblOggetti]  WITH CHECK ADD  CONSTRAINT [FK_tblOggetti_tblUnitaMisura] FOREIGN KEY([IdUnitaMisura])
REFERENCES [dbo].[tblUnitaMisura] ([Id])
GO

ALTER TABLE [dbo].[tblOggetti] CHECK CONSTRAINT [FK_tblOggetti_tblUnitaMisura]
GO
