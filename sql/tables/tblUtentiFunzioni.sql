SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblUtentiFunzioni](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdFunzione] [char](3) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdPermesso] [tinyint] NULL,
 CONSTRAINT [PK_tblUtentiFunzioni_1] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdFunzione] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblUtentiFunzioni]  WITH CHECK ADD  CONSTRAINT [FK_tblUtentiFunzioni_tblFunzioni] FOREIGN KEY([IdFunzione])
REFERENCES [dbo].[tblFunzioni] ([Id])
GO

ALTER TABLE [dbo].[tblUtentiFunzioni] CHECK CONSTRAINT [FK_tblUtentiFunzioni_tblFunzioni]
GO

ALTER TABLE [dbo].[tblUtentiFunzioni]  WITH CHECK ADD  CONSTRAINT [FK_tblUtentiFunzioni_tblPermessi] FOREIGN KEY([IdPermesso])
REFERENCES [dbo].[tblPermessi] ([Id])
GO

ALTER TABLE [dbo].[tblUtentiFunzioni] CHECK CONSTRAINT [FK_tblUtentiFunzioni_tblPermessi]
GO

ALTER TABLE [dbo].[tblUtentiFunzioni]  WITH CHECK ADD  CONSTRAINT [FK_tblUtentiFunzioni_tblUtenti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblUtenti] ([Id])
GO

ALTER TABLE [dbo].[tblUtentiFunzioni] CHECK CONSTRAINT [FK_tblUtentiFunzioni_tblUtenti]