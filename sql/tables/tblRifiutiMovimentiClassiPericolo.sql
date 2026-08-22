SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiMovimentiClassiPericolo](
	[Id] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdClasse] [char](2) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiMovimentiClassiPericolo] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdClasse] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiMovimentiClassiPericolo]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimentiClassiPericolo_tblRifiutiClassiPericolo] FOREIGN KEY([IdClasse])
REFERENCES [dbo].[tblRifiutiClassiPericolo] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiClassiPericolo] CHECK CONSTRAINT [FK_tblRifiutiMovimentiClassiPericolo_tblRifiutiClassiPericolo]
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiClassiPericolo]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimentiClassiPericolo_tblRifiutiMovimenti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiMovimenti] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiClassiPericolo] CHECK CONSTRAINT [FK_tblRifiutiMovimentiClassiPericolo_tblRifiutiMovimenti]