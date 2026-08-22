SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblSediIndirizzi](
	[Id] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdIndirizzo] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
 CONSTRAINT [PK_tblSediIndirizzi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdIndirizzo] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblSediIndirizzi]  WITH CHECK ADD  CONSTRAINT [FK_tblSediIndirizzi_tblIndirizzi] FOREIGN KEY([IdIndirizzo])
REFERENCES [dbo].[tblIndirizzi] ([Id])
GO

ALTER TABLE [dbo].[tblSediIndirizzi] CHECK CONSTRAINT [FK_tblSediIndirizzi_tblIndirizzi]
GO

ALTER TABLE [dbo].[tblSediIndirizzi]  WITH CHECK ADD  CONSTRAINT [FK_tblSediIndirizzi_tblSedi] FOREIGN KEY([Id])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblSediIndirizzi] CHECK CONSTRAINT [FK_tblSediIndirizzi_tblSedi]