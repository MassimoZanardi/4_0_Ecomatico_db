SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioni](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRegistro] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdUtente] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[DalAnno] [smallint] NOT NULL,
	[DalNumero] [int] NOT NULL,
	[AlAnno] [smallint] NOT NULL,
	[AlNumero] [int] NOT NULL,
	[Stato] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[FinoAlPrimoProblema] [bit] NULL,
	[DataCreazione] [datetime2](0) NOT NULL,
	[DataAnalisi] [datetime2](0) NULL,
	[DataEsecuzione] [datetime2](0) NULL,
	[Modalita] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRentriImportazioni] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RentriImportazioni_IdRegistro_Stato] ON [dbo].[tblRentriImportazioni]
(
	[IdRegistro] ASC,
	[Stato] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriImportazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioni_tblRifiutiRegistri] FOREIGN KEY([IdRegistro])
REFERENCES [dbo].[tblRifiutiRegistri] ([Id])
GO

ALTER TABLE [dbo].[tblRentriImportazioni] CHECK CONSTRAINT [FK_tblRentriImportazioni_tblRifiutiRegistri]
GO

ALTER TABLE [dbo].[tblRentriImportazioni]  WITH CHECK ADD  CONSTRAINT [CK_tblRentriImportazioni_Modalita] CHECK  (([Modalita]='F' OR [Modalita]='I'))
GO

ALTER TABLE [dbo].[tblRentriImportazioni] CHECK CONSTRAINT [CK_tblRentriImportazioni_Modalita]
GO

ALTER TABLE [dbo].[tblRentriImportazioni]  WITH CHECK ADD  CONSTRAINT [CK_tblRentriImportazioni_Stato] CHECK  (([Stato]='P' OR [Stato]='E'))
GO

ALTER TABLE [dbo].[tblRentriImportazioni] CHECK CONSTRAINT [CK_tblRentriImportazioni_Stato]
GO
