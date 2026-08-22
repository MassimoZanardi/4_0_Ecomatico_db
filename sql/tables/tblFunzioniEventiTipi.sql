SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblFunzioniEventiTipi](
	[Id] [char](3) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdTipo] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
 CONSTRAINT [PK_tblFunzioniEventiTipi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdTipo] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblFunzioniEventiTipi]  WITH CHECK ADD  CONSTRAINT [FK_tblFunzioniEventiTipi_tblEventiTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblEventiTipi] ([Id])
GO

ALTER TABLE [dbo].[tblFunzioniEventiTipi] CHECK CONSTRAINT [FK_tblFunzioniEventiTipi_tblEventiTipi]
GO

ALTER TABLE [dbo].[tblFunzioniEventiTipi]  WITH CHECK ADD  CONSTRAINT [FK_tblFunzioniEventiTipi_tblFunzioni] FOREIGN KEY([Id])
REFERENCES [dbo].[tblFunzioni] ([Id])
GO

ALTER TABLE [dbo].[tblFunzioniEventiTipi] CHECK CONSTRAINT [FK_tblFunzioniEventiTipi_tblFunzioni]