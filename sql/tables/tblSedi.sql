SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblSedi](
	[Id] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdParent] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdAziendaInterna] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdTipo] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[InternaEsterna] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Nome] [varchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Cognome] [varchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[PartitaIva] [varchar](20) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[CodiceFiscale] [varchar](20) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IndirizzoCompleto] [varchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[NomeCompleto] [varchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Codice] [varchar](20) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Note] [varchar](1000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Disabilitata] [bit] NULL,
	[Lock] [tinyint] NULL,
	[UnitaLocale] [bit] NULL,
 CONSTRAINT [PK_tblSedi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_Sedi_IdParent_Lock] ON [dbo].[tblSedi]
(
	[IdParent] ASC
)
INCLUDE([NomeCompleto],[IndirizzoCompleto]) 
WHERE ([Lock]<(2))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_Sedi_InternaEsterna_IdAziendaInterna_Lock] ON [dbo].[tblSedi]
(
	[InternaEsterna] ASC,
	[IdAziendaInterna] ASC
)
INCLUDE([IdTipo],[NomeCompleto],[IndirizzoCompleto],[CodiceFiscale],[PartitaIva],[Note],[Disabilitata]) 
WHERE ([Lock]<(2))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblSedi]  WITH CHECK ADD  CONSTRAINT [FK_tblSedi_tblOsepe] FOREIGN KEY([Id])
REFERENCES [dbo].[tblOsepe] ([Id])
GO

ALTER TABLE [dbo].[tblSedi] CHECK CONSTRAINT [FK_tblSedi_tblOsepe]
GO

ALTER TABLE [dbo].[tblSedi]  WITH CHECK ADD  CONSTRAINT [FK_tblSedi_tblSedi_IdAziendaInterna] FOREIGN KEY([IdAziendaInterna])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblSedi] CHECK CONSTRAINT [FK_tblSedi_tblSedi_IdAziendaInterna]
GO

ALTER TABLE [dbo].[tblSedi]  WITH CHECK ADD  CONSTRAINT [FK_tblSedi_tblSedi_IdParent] FOREIGN KEY([IdParent])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblSedi] CHECK CONSTRAINT [FK_tblSedi_tblSedi_IdParent]
GO

ALTER TABLE [dbo].[tblSedi]  WITH CHECK ADD  CONSTRAINT [FK_tblSedi_tblSediTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblSediTipi] ([Id])
GO

ALTER TABLE [dbo].[tblSedi] CHECK CONSTRAINT [FK_tblSedi_tblSediTipi]