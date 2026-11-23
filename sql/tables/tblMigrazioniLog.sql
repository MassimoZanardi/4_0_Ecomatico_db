SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMigrazioniLog](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[IdMigrazione] [int] NOT NULL,
	[Data] [datetime2](3) NOT NULL,
	[Fase] [varchar](50) COLLATE Latin1_General_CI_AS NOT NULL,
	[Livello] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[Tabella] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[IdOrigine] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Righe] [int] NULL,
	[Messaggio] [nvarchar](1000) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblMigrazioniLog] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_MigrazioniLog_IdMigrazione_Livello] ON [dbo].[tblMigrazioniLog]
(
	[IdMigrazione] ASC,
	[Livello] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblMigrazioniLog]  WITH CHECK ADD  CONSTRAINT [FK_tblMigrazioniLog_tblMigrazioni] FOREIGN KEY([IdMigrazione])
REFERENCES [dbo].[tblMigrazioni] ([Id])
GO

ALTER TABLE [dbo].[tblMigrazioniLog] CHECK CONSTRAINT [FK_tblMigrazioniLog_tblMigrazioni]
GO
