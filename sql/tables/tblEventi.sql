SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblEventi](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdCalendario] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdStato] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdTipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Data] [smalldatetime] NULL,
	[InGiornata] [bit] NULL,
	[AvvisoAnticipo] [int] NULL,
	[Avviso] [varchar](1000) COLLATE Latin1_General_CI_AS NULL,
	[Email] [varchar](1000) COLLATE Latin1_General_CI_AS NULL,
	[Etichette] [varchar](2000) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblEventi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_Eventi_IdCalendario_Data] ON [dbo].[tblEventi]
(
	[IdCalendario] ASC,
	[Data] ASC
)
INCLUDE([IdStato],[Lock]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_Eventi_IdCalendario_IdTipo_Lock] ON [dbo].[tblEventi]
(
	[IdCalendario] ASC,
	[IdTipo] ASC,
	[Lock] ASC
)
INCLUDE([IdStato],[Data],[InGiornata],[AvvisoAnticipo],[Avviso],[Etichette],[Email]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblEventi]  WITH CHECK ADD  CONSTRAINT [FK_tblEventi_tblCalendari] FOREIGN KEY([IdCalendario])
REFERENCES [dbo].[tblCalendari] ([Id])
GO

ALTER TABLE [dbo].[tblEventi] CHECK CONSTRAINT [FK_tblEventi_tblCalendari]
GO

ALTER TABLE [dbo].[tblEventi]  WITH CHECK ADD  CONSTRAINT [FK_tblEventi_tblEventiStati] FOREIGN KEY([IdStato])
REFERENCES [dbo].[tblEventiStati] ([Id])
GO

ALTER TABLE [dbo].[tblEventi] CHECK CONSTRAINT [FK_tblEventi_tblEventiStati]
GO

ALTER TABLE [dbo].[tblEventi]  WITH CHECK ADD  CONSTRAINT [FK_tblEventi_tblEventiTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblEventiTipi] ([Id])
GO

ALTER TABLE [dbo].[tblEventi] CHECK CONSTRAINT [FK_tblEventi_tblEventiTipi]
GO
