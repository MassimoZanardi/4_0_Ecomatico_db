SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiModelliRegistrazioniAuto](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdModello] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Posizione] [int] NULL,
	[Percentuale] [int] NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NULL,
	[IdStatoFisico] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdUnitaMisura] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdMateriale] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblRifiutiModelliRegistrazioniAuto_1] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAuto]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAuto_tblRifiutiModelli] FOREIGN KEY([IdModello])
REFERENCES [dbo].[tblRifiutiModelli] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAuto] CHECK CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAuto_tblRifiutiModelli]
GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAuto]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAuto_tblRifiutiEer] FOREIGN KEY([IdEer])
REFERENCES [dbo].[tblRifiutiEer] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAuto] CHECK CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAuto_tblRifiutiEer]
GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAuto]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAuto_tblRifiutiStatiFisici] FOREIGN KEY([IdStatoFisico])
REFERENCES [dbo].[tblRifiutiStatiFisici] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAuto] CHECK CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAuto_tblRifiutiStatiFisici]
GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAuto]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAuto_tblUnitaMisura] FOREIGN KEY([IdUnitaMisura])
REFERENCES [dbo].[tblUnitaMisura] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAuto] CHECK CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAuto_tblUnitaMisura]
GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAuto]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAuto_tblRifiutiMateriali] FOREIGN KEY([IdMateriale])
REFERENCES [dbo].[tblRifiutiMateriali] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAuto] CHECK CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAuto_tblRifiutiMateriali]
GO
