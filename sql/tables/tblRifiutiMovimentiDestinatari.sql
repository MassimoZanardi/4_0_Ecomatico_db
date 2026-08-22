SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiMovimentiDestinatari](
	[Id] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdAutorizzazione] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Pos] [tinyint] NULL,
 CONSTRAINT [PK_tblRifiutiMovimentiDestinatari] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdAutorizzazione] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiMovimentiDestinatari]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimentiDestinatari_tblRifiutiAutorizzazioni] FOREIGN KEY([IdAutorizzazione])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiDestinatari] CHECK CONSTRAINT [FK_tblRifiutiMovimentiDestinatari_tblRifiutiAutorizzazioni]
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiDestinatari]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimentiDestinatari_tblRifiutiMovimenti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiMovimenti] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiDestinatari] CHECK CONSTRAINT [FK_tblRifiutiMovimentiDestinatari_tblRifiutiMovimenti]