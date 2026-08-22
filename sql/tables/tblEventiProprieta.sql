SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblEventiProprieta](
	[Id] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdProprieta] [char](3) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Valore] [varchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
 CONSTRAINT [PK_tblEventiProprieta] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdProprieta] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblEventiProprieta]  WITH CHECK ADD  CONSTRAINT [FK_tblEventiProprieta_tblEventi] FOREIGN KEY([Id])
REFERENCES [dbo].[tblEventi] ([Id])
GO

ALTER TABLE [dbo].[tblEventiProprieta] CHECK CONSTRAINT [FK_tblEventiProprieta_tblEventi]
GO

ALTER TABLE [dbo].[tblEventiProprieta]  WITH CHECK ADD  CONSTRAINT [FK_tblEventiProprieta_tblProprieta] FOREIGN KEY([IdProprieta])
REFERENCES [dbo].[tblProprieta] ([Id])
GO

ALTER TABLE [dbo].[tblEventiProprieta] CHECK CONSTRAINT [FK_tblEventiProprieta_tblProprieta]