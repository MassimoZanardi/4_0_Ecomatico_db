SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblEoWAllocazioni](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdAllocazioneTipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblEoWAllocazioni] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_EoWAllocazioni_IdSede_Lock] ON [dbo].[tblEoWAllocazioni]
(
	[IdSede] ASC,
	[Lock] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblEoWAllocazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWAllocazioni_tblEoWAllocazioniTipi] FOREIGN KEY([IdAllocazioneTipo])
REFERENCES [dbo].[tblEoWAllocazioniTipi] ([Id])
GO

ALTER TABLE [dbo].[tblEoWAllocazioni] CHECK CONSTRAINT [FK_tblEoWAllocazioni_tblEoWAllocazioniTipi]
GO

ALTER TABLE [dbo].[tblEoWAllocazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWAllocazioni_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblEoWAllocazioni] CHECK CONSTRAINT [FK_tblEoWAllocazioni_tblSedi]
GO
