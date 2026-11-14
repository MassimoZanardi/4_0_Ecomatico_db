SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioniSoggetti](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[IdImportazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Ruolo] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[CodiceFiscale] [varchar](20) COLLATE Latin1_General_CI_AS NOT NULL,
	[Numero] [varchar](50) COLLATE Latin1_General_CI_AS NOT NULL,
	[Denominazione] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	[NazioneId] [varchar](5) COLLATE Latin1_General_CI_AS NULL,
	[IndirizzoJson] [nvarchar](1000) COLLATE Latin1_General_CI_AS NULL,
	[Stato] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdAutorizzazione] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IsModificato] [bit] NOT NULL,
	[PartitaIva] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[IdNazione] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdComune] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Localita] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[CAP] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[Indirizzo] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[NumeroCivico] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblRentriImportazioniSoggetti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE UNIQUE NONCLUSTERED INDEX [IX_RentriImportazioniSoggetti_Chiave] ON [dbo].[tblRentriImportazioniSoggetti]
(
	[IdImportazione] ASC,
	[Ruolo] ASC,
	[CodiceFiscale] ASC,
	[Numero] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriImportazioniSoggetti]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniSoggetti_tblRentriImportazioni] FOREIGN KEY([IdImportazione])
REFERENCES [dbo].[tblRentriImportazioni] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblRentriImportazioniSoggetti] CHECK CONSTRAINT [FK_tblRentriImportazioniSoggetti_tblRentriImportazioni]
GO

ALTER TABLE [dbo].[tblRentriImportazioniSoggetti]  WITH CHECK ADD  CONSTRAINT [CK_tblRentriImportazioniSoggetti_Stato] CHECK  (([Stato]='A' OR [Stato]='N' OR [Stato]='M' OR [Stato]='U' OR [Stato]='C'))
GO

ALTER TABLE [dbo].[tblRentriImportazioniSoggetti] CHECK CONSTRAINT [CK_tblRentriImportazioniSoggetti_Stato]
GO
