SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiModelliRegistrazioniAutoEtichette](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdEtichetta] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiModelliRegistrazioniAutoEtichette] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdEtichetta] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAutoEtichette]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAutoEtichette_tblEtichette] FOREIGN KEY([IdEtichetta])
REFERENCES [dbo].[tblEtichette] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAutoEtichette] CHECK CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAutoEtichette_tblEtichette]
GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAutoEtichette]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAutoEtichette_tblRifiutiModelliRegistrazioniAuto] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiModelliRegistrazioniAuto] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelliRegistrazioniAutoEtichette] CHECK CONSTRAINT [FK_tblRifiutiModelliRegistrazioniAutoEtichette_tblRifiutiModelliRegistrazioniAuto]
GO
