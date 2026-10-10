SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiModelliClassiPericolo](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdClasse] [char](2) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiModelliClassiPericolo] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdClasse] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiModelliClassiPericolo]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelliClassiPericolo_tblRifiutiClassiPericolo] FOREIGN KEY([IdClasse])
REFERENCES [dbo].[tblRifiutiClassiPericolo] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelliClassiPericolo] CHECK CONSTRAINT [FK_tblRifiutiModelliClassiPericolo_tblRifiutiClassiPericolo]
GO

ALTER TABLE [dbo].[tblRifiutiModelliClassiPericolo]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelliClassiPericolo_tblRifiutiModelli] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiModelli] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelliClassiPericolo] CHECK CONSTRAINT [FK_tblRifiutiModelliClassiPericolo_tblRifiutiModelli]
GO
