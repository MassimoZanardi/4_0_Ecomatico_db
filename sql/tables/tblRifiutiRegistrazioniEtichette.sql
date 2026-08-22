SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiRegistrazioniEtichette](
	[Id] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdEtichetta] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiRegistrazioniEtichette] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdEtichetta] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RifiutiRegistrazioniEtichette_IdEtichetta] ON [dbo].[tblRifiutiRegistrazioniEtichette]
(
	[IdEtichetta] ASC
)
INCLUDE([Id]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioniEtichette]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioniEtichette_tblEtichette] FOREIGN KEY([IdEtichetta])
REFERENCES [dbo].[tblEtichette] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioniEtichette] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioniEtichette_tblEtichette]
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioniEtichette]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioniEtichette_tblRifiutiRegistrazioni] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiRegistrazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioniEtichette] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioniEtichette_tblRifiutiRegistrazioni]