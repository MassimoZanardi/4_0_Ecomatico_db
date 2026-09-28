SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriFirmeOperazioni](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdUtente] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[DataOra] [datetime2](0) NOT NULL,
	[Handle] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Esito] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[Note] [varchar](200) COLLATE Latin1_General_CI_AS NULL
 CONSTRAINT [PK_tblRentriFirmeOperazioni] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

CREATE NONCLUSTERED INDEX [IX_RentriFirmeOperazioni_IdUtente] ON [dbo].[tblRentriFirmeOperazioni]
(
	[IdUtente] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblRentriFirmeOperazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriFirmeOperazioni_tblUtenti] FOREIGN KEY([IdUtente])
REFERENCES [dbo].[tblUtenti] ([Id])
GO

ALTER TABLE [dbo].[tblRentriFirmeOperazioni] CHECK CONSTRAINT [FK_tblRentriFirmeOperazioni_tblUtenti]
GO
