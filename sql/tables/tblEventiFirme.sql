SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblEventiFirme](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdTipo] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdFirma] [uniqueidentifier] NULL,
 CONSTRAINT [PK_tblEventiFirme] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdTipo] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblEventiFirme]  WITH CHECK ADD  CONSTRAINT [FK_tblEventiFirme_tblEventi] FOREIGN KEY([Id])
REFERENCES [dbo].[tblEventi] ([Id])
GO

ALTER TABLE [dbo].[tblEventiFirme] CHECK CONSTRAINT [FK_tblEventiFirme_tblEventi]
GO

ALTER TABLE [dbo].[tblEventiFirme]  WITH CHECK ADD  CONSTRAINT [FK_tblEventiFirme_tblFirme] FOREIGN KEY([IdFirma])
REFERENCES [dbo].[tblFirme] ([Id])
GO

ALTER TABLE [dbo].[tblEventiFirme] CHECK CONSTRAINT [FK_tblEventiFirme_tblFirme]