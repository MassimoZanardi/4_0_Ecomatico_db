SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiAutorizzazioniTarghe](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Targa] [varchar](20) COLLATE Latin1_General_CI_AS NOT NULL,
	[Rimorchio] [bit] NULL,
 CONSTRAINT [PK_tblRifiutiAutorizzazioniTarghe_1] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[Targa] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniTarghe]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiAutorizzazioniTarghe_tblRifiutiAutorizzazioni] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniTarghe] CHECK CONSTRAINT [FK_tblRifiutiAutorizzazioniTarghe_tblRifiutiAutorizzazioni]