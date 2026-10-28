SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblDiwassCredenzialiAziende](
	[IdAziendaInterna] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdCredenziale] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblDiwassCredenzialiAziende] PRIMARY KEY CLUSTERED 
(
	[IdAziendaInterna] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_DiwassCredenzialiAziende_IdCredenziale] ON [dbo].[tblDiwassCredenzialiAziende]
(
	[IdCredenziale] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblDiwassCredenzialiAziende]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassCredenzialiAziende_tblDiwassCredenziali] FOREIGN KEY([IdCredenziale])
REFERENCES [dbo].[tblDiwassCredenziali] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassCredenzialiAziende] CHECK CONSTRAINT [FK_tblDiwassCredenzialiAziende_tblDiwassCredenziali]
GO

ALTER TABLE [dbo].[tblDiwassCredenzialiAziende]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassCredenzialiAziende_tblSediInterne] FOREIGN KEY([IdAziendaInterna])
REFERENCES [dbo].[tblSediInterne] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassCredenzialiAziende] CHECK CONSTRAINT [FK_tblDiwassCredenzialiAziende_tblSediInterne]
GO
