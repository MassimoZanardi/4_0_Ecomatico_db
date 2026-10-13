SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMagazziniDdtEtichette](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdEtichetta] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblMagazziniDdtEtichette] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdEtichetta] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_MagazziniDdtEtichette_IdEtichetta] ON [dbo].[tblMagazziniDdtEtichette]
(
	[IdEtichetta] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblMagazziniDdtEtichette]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniDdtEtichette_tblEtichette] FOREIGN KEY([IdEtichetta])
REFERENCES [dbo].[tblEtichette] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblMagazziniDdtEtichette] CHECK CONSTRAINT [FK_tblMagazziniDdtEtichette_tblEtichette]
GO

ALTER TABLE [dbo].[tblMagazziniDdtEtichette]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniDdtEtichette_tblMagazziniDdt] FOREIGN KEY([Id])
REFERENCES [dbo].[tblMagazziniDdt] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblMagazziniDdtEtichette] CHECK CONSTRAINT [FK_tblMagazziniDdtEtichette_tblMagazziniDdt]
GO
