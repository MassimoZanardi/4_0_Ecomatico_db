SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiMovimentiIntermediari](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdAutorizzazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Pos] [tinyint] NOT NULL,
 CONSTRAINT [PK_tblRifiutiMovimentiIntermediari_1] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdAutorizzazione] ASC,
	[Pos] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiMovimentiIntermediari]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimentiIntermediari_tblRifiutiAutorizzazioni] FOREIGN KEY([IdAutorizzazione])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiIntermediari] CHECK CONSTRAINT [FK_tblRifiutiMovimentiIntermediari_tblRifiutiAutorizzazioni]
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiIntermediari]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimentiIntermediari_tblRifiutiMovimenti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiMovimenti] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiIntermediari] CHECK CONSTRAINT [FK_tblRifiutiMovimentiIntermediari_tblRifiutiMovimenti]