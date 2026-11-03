SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblViviFirCredenzialiAziende](
	[IdAziendaInterna] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdCredenziale] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSoggetto] [int] NULL,
	[Soggetto] [varchar](255) COLLATE Latin1_General_CI_AS NULL,
	[Blocco] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[DataVerifica] [datetime2](0) NULL,
 CONSTRAINT [PK_tblViviFirCredenzialiAziende] PRIMARY KEY CLUSTERED 
(
	[IdAziendaInterna] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_ViviFirCredenzialiAziende_IdCredenziale] ON [dbo].[tblViviFirCredenzialiAziende]
(
	[IdCredenziale] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblViviFirCredenzialiAziende]  WITH CHECK ADD  CONSTRAINT [FK_tblViviFirCredenzialiAziende_tblSediInterne] FOREIGN KEY([IdAziendaInterna])
REFERENCES [dbo].[tblSediInterne] ([Id])
GO

ALTER TABLE [dbo].[tblViviFirCredenzialiAziende] CHECK CONSTRAINT [FK_tblViviFirCredenzialiAziende_tblSediInterne]
GO

ALTER TABLE [dbo].[tblViviFirCredenzialiAziende]  WITH CHECK ADD  CONSTRAINT [FK_tblViviFirCredenzialiAziende_tblViviFirCredenziali] FOREIGN KEY([IdCredenziale])
REFERENCES [dbo].[tblViviFirCredenziali] ([Id])
GO

ALTER TABLE [dbo].[tblViviFirCredenzialiAziende] CHECK CONSTRAINT [FK_tblViviFirCredenzialiAziende_tblViviFirCredenziali]
GO
