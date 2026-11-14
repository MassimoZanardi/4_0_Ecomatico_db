SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioniCausali](
	[IdImportazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Causale] [varchar](5) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdOperazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblRentriImportazioniCausali] PRIMARY KEY CLUSTERED 
(
	[IdImportazione] ASC,
	[Causale] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriImportazioniCausali]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniCausali_tblRentriImportazioni] FOREIGN KEY([IdImportazione])
REFERENCES [dbo].[tblRentriImportazioni] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblRentriImportazioniCausali] CHECK CONSTRAINT [FK_tblRentriImportazioniCausali_tblRentriImportazioni]
GO

ALTER TABLE [dbo].[tblRentriImportazioniCausali]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniCausali_tblRifiutiOperazioni] FOREIGN KEY([IdOperazione])
REFERENCES [dbo].[tblRifiutiOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRentriImportazioniCausali] CHECK CONSTRAINT [FK_tblRentriImportazioniCausali_tblRifiutiOperazioni]
GO
