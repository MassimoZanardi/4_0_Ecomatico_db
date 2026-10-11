SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblAmministratoriSedi](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[DataInizio] [date] NULL,
	[DataFine] [date] NULL,
 CONSTRAINT [PK_tblAmministratoriSedi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdSede] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_AmministratoriSedi_IdSede] ON [dbo].[tblAmministratoriSedi]
(
	[IdSede] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblAmministratoriSedi]  WITH CHECK ADD  CONSTRAINT [FK_tblAmministratoriSedi_tblAmministratori] FOREIGN KEY([Id])
REFERENCES [dbo].[tblAmministratori] ([Id])
GO

ALTER TABLE [dbo].[tblAmministratoriSedi] CHECK CONSTRAINT [FK_tblAmministratoriSedi_tblAmministratori]
GO

ALTER TABLE [dbo].[tblAmministratoriSedi]  WITH CHECK ADD  CONSTRAINT [FK_tblAmministratoriSedi_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblAmministratoriSedi] CHECK CONSTRAINT [FK_tblAmministratoriSedi_tblSedi]
GO
