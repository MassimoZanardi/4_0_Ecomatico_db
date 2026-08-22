SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiOperazioniRegistriTipi](
	[Id] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdTipo] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiOperazioniRegistriTipi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdTipo] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiOperazioniRegistriTipi]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiOperazioniRegistriTipi_tblRifiutiOperazioni] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiOperazioniRegistriTipi] CHECK CONSTRAINT [FK_tblRifiutiOperazioniRegistriTipi_tblRifiutiOperazioni]
GO

ALTER TABLE [dbo].[tblRifiutiOperazioniRegistriTipi]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiOperazioniRegistriTipi_tblRifiutiRegistriTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblRifiutiRegistriTipi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiOperazioniRegistriTipi] CHECK CONSTRAINT [FK_tblRifiutiOperazioniRegistriTipi_tblRifiutiRegistriTipi]