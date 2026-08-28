SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiAutorizzazioniEer](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiAutorizzazioniEer] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdEer] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniEer]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiAutorizzazioniEer_tblRifiutiAutorizzazioni] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniEer] CHECK CONSTRAINT [FK_tblRifiutiAutorizzazioniEer_tblRifiutiAutorizzazioni]
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniEer]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiAutorizzazioniEer_tblRifiutiEer] FOREIGN KEY([IdEer])
REFERENCES [dbo].[tblRifiutiEer] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniEer] CHECK CONSTRAINT [FK_tblRifiutiAutorizzazioniEer_tblRifiutiEer]