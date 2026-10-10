SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiOperazioniRelazioni](
	[Id] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdParent] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiOperazioniRelazioni] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdParent] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiOperazioniRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiOperazioniRelazioni_tblRifiutiOperazioni_Id] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiOperazioniRelazioni] CHECK CONSTRAINT [FK_tblRifiutiOperazioniRelazioni_tblRifiutiOperazioni_Id]
GO

ALTER TABLE [dbo].[tblRifiutiOperazioniRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiOperazioniRelazioni_tblRifiutiOperazioni_IdParent] FOREIGN KEY([IdParent])
REFERENCES [dbo].[tblRifiutiOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiOperazioniRelazioni] CHECK CONSTRAINT [FK_tblRifiutiOperazioniRelazioni_tblRifiutiOperazioni_IdParent]
GO
