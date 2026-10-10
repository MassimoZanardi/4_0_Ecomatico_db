SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMenu](
	[Id] [char](3) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdParent] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdArea] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdPagina] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[Pos] [int] NULL,
 CONSTRAINT [PK_tblMenu] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblMenu]  WITH CHECK ADD  CONSTRAINT [FK_tblMenu_tblMenu] FOREIGN KEY([IdParent])
REFERENCES [dbo].[tblMenu] ([Id])
GO

ALTER TABLE [dbo].[tblMenu] CHECK CONSTRAINT [FK_tblMenu_tblMenu]
GO

ALTER TABLE [dbo].[tblMenu]  WITH CHECK ADD  CONSTRAINT [FK_tblMenu_tblPagine] FOREIGN KEY([IdPagina])
REFERENCES [dbo].[tblPagine] ([Id])
GO

ALTER TABLE [dbo].[tblMenu] CHECK CONSTRAINT [FK_tblMenu_tblPagine]
GO

ALTER TABLE [dbo].[tblMenu]  WITH CHECK ADD  CONSTRAINT [FK_tblMenu_tblPagineAree] FOREIGN KEY([IdArea])
REFERENCES [dbo].[tblPagineAree] ([Id])
GO

ALTER TABLE [dbo].[tblMenu] CHECK CONSTRAINT [FK_tblMenu_tblPagineAree]
GO
