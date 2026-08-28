SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblServizi](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdTipo] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEvento] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdRichiedente] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[DataRichiesta] [smalldatetime] NULL,
	[Descrizione] [varchar](1000) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblServizi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_Servizi_IdEvento] ON [dbo].[tblServizi]
(
	[IdEvento] ASC
)
INCLUDE([Descrizione],[IdTipo],[IdRichiedente]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblServizi_tblEventi] FOREIGN KEY([IdEvento])
REFERENCES [dbo].[tblEventi] ([Id])
GO

ALTER TABLE [dbo].[tblServizi] CHECK CONSTRAINT [FK_tblServizi_tblEventi]
GO

ALTER TABLE [dbo].[tblServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblServizi_tblSedi_IdRichiedente] FOREIGN KEY([IdRichiedente])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblServizi] CHECK CONSTRAINT [FK_tblServizi_tblSedi_IdRichiedente]
GO

ALTER TABLE [dbo].[tblServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblServizi_tblTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblTipi] ([Id])
GO

ALTER TABLE [dbo].[tblServizi] CHECK CONSTRAINT [FK_tblServizi_tblTipi]