SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblPersone](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdUnitaMisura] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Cognome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Disabilitata] [bit] NULL,
	[NomeCompleto] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[ImpiegabileServizi] [bit] NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblPersone] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblPersone]  WITH CHECK ADD  CONSTRAINT [FK_tblPersone_tblOsepe] FOREIGN KEY([Id])
REFERENCES [dbo].[tblOsepe] ([Id])
GO

ALTER TABLE [dbo].[tblPersone] CHECK CONSTRAINT [FK_tblPersone_tblOsepe]
GO

ALTER TABLE [dbo].[tblPersone]  WITH CHECK ADD  CONSTRAINT [FK_tblPersone_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblPersone] CHECK CONSTRAINT [FK_tblPersone_tblSedi]
GO

ALTER TABLE [dbo].[tblPersone]  WITH CHECK ADD  CONSTRAINT [FK_tblPersone_tblUnitaMisura] FOREIGN KEY([IdUnitaMisura])
REFERENCES [dbo].[tblUnitaMisura] ([Id])
GO

ALTER TABLE [dbo].[tblPersone] CHECK CONSTRAINT [FK_tblPersone_tblUnitaMisura]