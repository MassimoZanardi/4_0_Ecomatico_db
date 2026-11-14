SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioniAnomalie](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[IdImportazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Anno] [smallint] NULL,
	[Progressivo] [int] NULL,
	[Livello] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[Codice] [varchar](30) COLLATE Latin1_General_CI_AS NOT NULL,
	[Messaggio] [nvarchar](400) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRentriImportazioniAnomalie] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RentriImportazioniAnomalie_IdImportazione] ON [dbo].[tblRentriImportazioniAnomalie]
(
	[IdImportazione] ASC,
	[Anno] ASC,
	[Progressivo] ASC
)
INCLUDE([Livello]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriImportazioniAnomalie]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniAnomalie_tblRentriImportazioni] FOREIGN KEY([IdImportazione])
REFERENCES [dbo].[tblRentriImportazioni] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblRentriImportazioniAnomalie] CHECK CONSTRAINT [FK_tblRentriImportazioniAnomalie_tblRentriImportazioni]
GO

ALTER TABLE [dbo].[tblRentriImportazioniAnomalie]  WITH CHECK ADD  CONSTRAINT [CK_tblRentriImportazioniAnomalie_Livello] CHECK  (([Livello]='E' OR [Livello]='W' OR [Livello]='I'))
GO

ALTER TABLE [dbo].[tblRentriImportazioniAnomalie] CHECK CONSTRAINT [CK_tblRentriImportazioniAnomalie_Livello]
GO
