SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioniRelazioni](
	[IdImportazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[PadreAnno] [smallint] NOT NULL,
	[PadreProgressivo] [int] NOT NULL,
	[FiglioAnno] [smallint] NOT NULL,
	[FiglioProgressivo] [int] NOT NULL,
	[FiglioIdentificativo] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[IdRegistrazioneFiglio] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Pos] [int] NOT NULL,
	[Operazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[DisponibilePrima] [decimal](18, 4) NULL,
	[QuantitaProposta] [decimal](18, 4) NULL,
	[Quantita] [decimal](18, 4) NULL,
	[IsModificata] [bit] NOT NULL,
 CONSTRAINT [PK_tblRentriImportazioniRelazioni] PRIMARY KEY CLUSTERED 
(
	[IdImportazione] ASC,
	[PadreAnno] ASC,
	[PadreProgressivo] ASC,
	[FiglioAnno] ASC,
	[FiglioProgressivo] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriImportazioniRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniRelazioni_tblRentriImportazioni] FOREIGN KEY([IdImportazione])
REFERENCES [dbo].[tblRentriImportazioni] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblRentriImportazioniRelazioni] CHECK CONSTRAINT [FK_tblRentriImportazioniRelazioni_tblRentriImportazioni]
GO
