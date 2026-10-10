SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblSessioniFunzioniPermessi](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdFunzione] [char](3) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdPermesso] [tinyint] NOT NULL,
 CONSTRAINT [PK_tblSessioniFunzioniPermessi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdFunzione] ASC,
	[IdPermesso] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblSessioniFunzioniPermessi]  WITH CHECK ADD  CONSTRAINT [FK_tblSessioniFunzioniPermessi_tblFunzioni] FOREIGN KEY([IdFunzione])
REFERENCES [dbo].[tblFunzioni] ([Id])
GO

ALTER TABLE [dbo].[tblSessioniFunzioniPermessi] CHECK CONSTRAINT [FK_tblSessioniFunzioniPermessi_tblFunzioni]
GO

ALTER TABLE [dbo].[tblSessioniFunzioniPermessi]  WITH CHECK ADD  CONSTRAINT [FK_tblSessioniFunzioniPermessi_tblPermessi] FOREIGN KEY([IdPermesso])
REFERENCES [dbo].[tblPermessi] ([Id])
GO

ALTER TABLE [dbo].[tblSessioniFunzioniPermessi] CHECK CONSTRAINT [FK_tblSessioniFunzioniPermessi_tblPermessi]
GO

ALTER TABLE [dbo].[tblSessioniFunzioniPermessi]  WITH CHECK ADD  CONSTRAINT [FK_tblSessioniFunzioniPermessi_tblSessioni] FOREIGN KEY([Id])
REFERENCES [dbo].[tblSessioni] ([Id])
GO

ALTER TABLE [dbo].[tblSessioniFunzioniPermessi] CHECK CONSTRAINT [FK_tblSessioniFunzioniPermessi_tblSessioni]
GO
