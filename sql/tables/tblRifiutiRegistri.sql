SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiRegistri](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdTipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[ControlloScadenzeAutorizzazioni] [bit] NULL,
	[ControlloTarghe] [bit] NULL,
	[ControlloConducenti] [bit] NULL,
	[ControlloPatenti] [bit] NULL,
	[ControlloAttivitaRs] [bit] NULL,
	[ConservazioniXfirMax] [int] NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblRifiutiRegistri] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RifiutiRegistri_IdSede] ON [dbo].[tblRifiutiRegistri]
(
	[IdSede] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblRifiutiRegistri]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistri_tblRifiutiRegistriTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblRifiutiRegistriTipi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistri] CHECK CONSTRAINT [FK_tblRifiutiRegistri_tblRifiutiRegistriTipi]
GO

ALTER TABLE [dbo].[tblRifiutiRegistri]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistri_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistri] CHECK CONSTRAINT [FK_tblRifiutiRegistri_tblSedi]