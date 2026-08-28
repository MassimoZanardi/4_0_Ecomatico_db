SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblEtichette](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdModulo] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdColore] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Descrizione] [varchar](500) COLLATE Latin1_General_CI_AS NULL,
	[Visualizzazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblEtichette] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_Etichette_IdSede_IdModulo_Lock] ON [dbo].[tblEtichette]
(
	[IdSede] ASC,
	[IdModulo] ASC
)
WHERE ([Lock]<(2))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblEtichette]  WITH CHECK ADD  CONSTRAINT [FK_tblEtichette_tblColori] FOREIGN KEY([IdColore])
REFERENCES [dbo].[tblColori] ([Id])
GO

ALTER TABLE [dbo].[tblEtichette] CHECK CONSTRAINT [FK_tblEtichette_tblColori]
GO

ALTER TABLE [dbo].[tblEtichette]  WITH CHECK ADD  CONSTRAINT [FK_tblEtichette_tblModuli] FOREIGN KEY([IdModulo])
REFERENCES [dbo].[tblModuli] ([Id])
GO

ALTER TABLE [dbo].[tblEtichette] CHECK CONSTRAINT [FK_tblEtichette_tblModuli]
GO

ALTER TABLE [dbo].[tblEtichette]  WITH CHECK ADD  CONSTRAINT [FK_tblEtichette_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblEtichette] CHECK CONSTRAINT [FK_tblEtichette_tblSedi]