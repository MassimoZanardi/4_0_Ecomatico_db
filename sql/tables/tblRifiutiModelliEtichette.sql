SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiModelliEtichette](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdEtichetta] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiModelliEtichette] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdEtichetta] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiModelliEtichette]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelliEtichette_tblEtichette] FOREIGN KEY([IdEtichetta])
REFERENCES [dbo].[tblEtichette] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelliEtichette] CHECK CONSTRAINT [FK_tblRifiutiModelliEtichette_tblEtichette]
GO

ALTER TABLE [dbo].[tblRifiutiModelliEtichette]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelliEtichette_tblRifiutiModelli] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiModelli] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelliEtichette] CHECK CONSTRAINT [FK_tblRifiutiModelliEtichette_tblRifiutiModelli]