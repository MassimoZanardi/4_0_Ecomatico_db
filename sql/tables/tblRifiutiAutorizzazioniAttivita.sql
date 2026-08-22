SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiAutorizzazioniAttivita](
	[Id] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdAttivita] [char](2) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiAutorizzazioniAttivita] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdAttivita] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniAttivita]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiAutorizzazioniAttivita_tblRifiutiAttivitaRecuperoSmaltimento] FOREIGN KEY([IdAttivita])
REFERENCES [dbo].[tblRifiutiAttivitaRecuperoSmaltimento] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniAttivita] CHECK CONSTRAINT [FK_tblRifiutiAutorizzazioniAttivita_tblRifiutiAttivitaRecuperoSmaltimento]
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniAttivita]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiAutorizzazioniAttivita_tblRifiutiAutorizzazioni] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniAttivita] CHECK CONSTRAINT [FK_tblRifiutiAutorizzazioniAttivita_tblRifiutiAutorizzazioni]