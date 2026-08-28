SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiAutorizzazioniConducenti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NOT NULL,
	[Cognome] [varchar](50) COLLATE Latin1_General_CI_AS NOT NULL,
	[ScadenzaPatente] [date] NULL,
	[ScadenzaPatenteAdr] [date] NULL,
 CONSTRAINT [PK_tblRifiutiAutorizzazioniConducenti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[Nome] ASC,
	[Cognome] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniConducenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiAutorizzazioniConducenti_tblRifiutiAutorizzazioni] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniConducenti] CHECK CONSTRAINT [FK_tblRifiutiAutorizzazioniConducenti_tblRifiutiAutorizzazioni]