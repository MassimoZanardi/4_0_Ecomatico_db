SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblDiwassOperatori](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[OperatorInternalId] [bigint] NOT NULL,
	[LinkedOperatorInternalId] [bigint] NULL,
	[Nome] [varchar](250) COLLATE Latin1_General_CI_AS NULL,
	[Indirizzo] [varchar](500) COLLATE Latin1_General_CI_AS NULL,
	[Paese] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Identificativo] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[Stato] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[DataVerifica] [smalldatetime] NULL,
 CONSTRAINT [PK_tblDiwassOperatori] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

CREATE NONCLUSTERED INDEX [IX_DiwassOperatori_OperatorInternalId] ON [dbo].[tblDiwassOperatori]
(
	[OperatorInternalId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblDiwassOperatori]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassOperatori_tblSedi] FOREIGN KEY([Id])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassOperatori] CHECK CONSTRAINT [FK_tblDiwassOperatori_tblSedi]
GO
