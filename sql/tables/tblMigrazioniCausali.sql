SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMigrazioniCausali](
	[Versione] [char](2) COLLATE Latin1_General_CI_AS NOT NULL,
	[CausaleOrigine] [varchar](20) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdOperazione] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblMigrazioniCausali] PRIMARY KEY CLUSTERED 
(
	[Versione] ASC,
	[CausaleOrigine] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblMigrazioniCausali]  WITH CHECK ADD  CONSTRAINT [FK_tblMigrazioniCausali_tblRifiutiOperazioni] FOREIGN KEY([IdOperazione])
REFERENCES [dbo].[tblRifiutiOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblMigrazioniCausali] CHECK CONSTRAINT [FK_tblMigrazioniCausali_tblRifiutiOperazioni]
GO
