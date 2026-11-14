SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioniMovimentiSoggetti](
	[IdImportazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Anno] [smallint] NOT NULL,
	[Progressivo] [int] NOT NULL,
	[Ruolo] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[Pos] [tinyint] NOT NULL,
	[IdSoggetto] [int] NOT NULL,
 CONSTRAINT [PK_tblRentriImportazioniMovimentiSoggetti] PRIMARY KEY CLUSTERED 
(
	[IdImportazione] ASC,
	[Anno] ASC,
	[Progressivo] ASC,
	[Ruolo] ASC,
	[Pos] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriImportazioniMovimentiSoggetti]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniMovimentiSoggetti_tblRentriImportazioni] FOREIGN KEY([IdImportazione])
REFERENCES [dbo].[tblRentriImportazioni] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblRentriImportazioniMovimentiSoggetti] CHECK CONSTRAINT [FK_tblRentriImportazioniMovimentiSoggetti_tblRentriImportazioni]
GO
