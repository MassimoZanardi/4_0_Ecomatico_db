SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiMudRegistri](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRegistro] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiMudRegistri] PRIMARY KEY CLUSTERED
(
	[Id] ASC,
	[IdRegistro] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiMudRegistri]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMudRegistri_tblRifiutiMud] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiMud] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMudRegistri] CHECK CONSTRAINT [FK_tblRifiutiMudRegistri_tblRifiutiMud]
GO

ALTER TABLE [dbo].[tblRifiutiMudRegistri]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMudRegistri_tblRifiutiRegistri] FOREIGN KEY([IdRegistro])
REFERENCES [dbo].[tblRifiutiRegistri] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMudRegistri] CHECK CONSTRAINT [FK_tblRifiutiMudRegistri_tblRifiutiRegistri]
GO
