SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRicorrenzeEccezioni](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Data] [smalldatetime] NOT NULL,
	[IdEvento] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblRicorrenzeEccezioni] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[Data] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RicorrenzeEccezioni_Id_Data_Lock] ON [dbo].[tblRicorrenzeEccezioni]
(
	[Id] ASC,
	[Data] ASC
)
WHERE ([Lock]=(0))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblRicorrenzeEccezioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRicorrenzeEccezioni_tblEventi_Id] FOREIGN KEY([Id])
REFERENCES [dbo].[tblEventi] ([Id])
GO

ALTER TABLE [dbo].[tblRicorrenzeEccezioni] CHECK CONSTRAINT [FK_tblRicorrenzeEccezioni_tblEventi_Id]
GO

ALTER TABLE [dbo].[tblRicorrenzeEccezioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRicorrenzeEccezioni_tblEventi_IdEvento] FOREIGN KEY([IdEvento])
REFERENCES [dbo].[tblEventi] ([Id])
GO

ALTER TABLE [dbo].[tblRicorrenzeEccezioni] CHECK CONSTRAINT [FK_tblRicorrenzeEccezioni_tblEventi_IdEvento]