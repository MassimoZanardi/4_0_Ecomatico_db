SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblModuliFunzioni](
	[Id] [char](3) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdFunzione] [char](3) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
 CONSTRAINT [PK_tblModuliFunzioni] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdFunzione] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblModuliFunzioni]  WITH CHECK ADD  CONSTRAINT [FK_tblModuliFunzioni_tblFunzioni] FOREIGN KEY([IdFunzione])
REFERENCES [dbo].[tblFunzioni] ([Id])
GO

ALTER TABLE [dbo].[tblModuliFunzioni] CHECK CONSTRAINT [FK_tblModuliFunzioni_tblFunzioni]
GO

ALTER TABLE [dbo].[tblModuliFunzioni]  WITH CHECK ADD  CONSTRAINT [FK_tblModuliFunzioni_tblModuli] FOREIGN KEY([Id])
REFERENCES [dbo].[tblModuli] ([Id])
GO

ALTER TABLE [dbo].[tblModuliFunzioni] CHECK CONSTRAINT [FK_tblModuliFunzioni_tblModuli]