SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRicorrenze](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdParent] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdIntervallo] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Frequenza] [int] NULL,
	[DataFine] [smalldatetime] NULL,
	[Ripetizioni] [int] NULL,
	[Relativo] [int] NULL,
 CONSTRAINT [PK_tblRicorrenze] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_Ricorrenze_Id_DataFine] ON [dbo].[tblRicorrenze]
(
	[Id] ASC,
	[DataFine] ASC
)
INCLUDE([IdIntervallo],[Frequenza],[Ripetizioni],[Relativo]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblRicorrenze]  WITH CHECK ADD  CONSTRAINT [FK_tblRicorrenze_tblEventi] FOREIGN KEY([Id])
REFERENCES [dbo].[tblEventi] ([Id])
GO

ALTER TABLE [dbo].[tblRicorrenze] CHECK CONSTRAINT [FK_tblRicorrenze_tblEventi]
GO

ALTER TABLE [dbo].[tblRicorrenze]  WITH CHECK ADD  CONSTRAINT [FK_tblRicorrenze_tblRicorrenze] FOREIGN KEY([IdParent])
REFERENCES [dbo].[tblRicorrenze] ([Id])
GO

ALTER TABLE [dbo].[tblRicorrenze] CHECK CONSTRAINT [FK_tblRicorrenze_tblRicorrenze]
GO

ALTER TABLE [dbo].[tblRicorrenze]  WITH CHECK ADD  CONSTRAINT [FK_tblRicorrenze_tblRicorrenzeIntervalli] FOREIGN KEY([IdIntervallo])
REFERENCES [dbo].[tblRicorrenzeIntervalli] ([Id])
GO

ALTER TABLE [dbo].[tblRicorrenze] CHECK CONSTRAINT [FK_tblRicorrenze_tblRicorrenzeIntervalli]