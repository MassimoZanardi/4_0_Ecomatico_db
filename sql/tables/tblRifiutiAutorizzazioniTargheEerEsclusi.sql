SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiAutorizzazioniTargheEerEsclusi](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Targa] [varchar](20) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRifiutiAutorizzazioniTargheEerEsclusi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[Targa] ASC,
	[IdEer] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniTargheEerEsclusi]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiAutorizzazioniTargheEerEsclusi_tblRifiutiAutorizzazioni] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniTargheEerEsclusi] CHECK CONSTRAINT [FK_tblRifiutiAutorizzazioniTargheEerEsclusi_tblRifiutiAutorizzazioni]
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniTargheEerEsclusi]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiAutorizzazioniTargheEerEsclusi_tblRifiutiEer] FOREIGN KEY([IdEer])
REFERENCES [dbo].[tblRifiutiEer] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioniTargheEerEsclusi] CHECK CONSTRAINT [FK_tblRifiutiAutorizzazioniTargheEerEsclusi_tblRifiutiEer]
GO
