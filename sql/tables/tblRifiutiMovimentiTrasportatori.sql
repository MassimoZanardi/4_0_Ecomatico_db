SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiMovimentiTrasportatori](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdAutorizzazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Pos] [tinyint] NOT NULL,
	[IdTipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblRifiutiMovimentiTrasportatori] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdAutorizzazione] ASC,
	[Pos] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiMovimentiTrasportatori]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimentiTrasportatori_tblRifiutiAutorizzazioni] FOREIGN KEY([IdAutorizzazione])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiTrasportatori] CHECK CONSTRAINT [FK_tblRifiutiMovimentiTrasportatori_tblRifiutiAutorizzazioni]
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiTrasportatori]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimentiTrasportatori_tblRifiutiMovimenti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiMovimenti] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiTrasportatori] CHECK CONSTRAINT [FK_tblRifiutiMovimentiTrasportatori_tblRifiutiMovimenti]
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiTrasportatori]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimentiTrasportatori_tblRifiutiMovimentiTrasportiTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblRifiutiMovimentiTrasportiTipi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiTrasportatori] CHECK CONSTRAINT [FK_tblRifiutiMovimentiTrasportatori_tblRifiutiMovimentiTrasportiTipi]