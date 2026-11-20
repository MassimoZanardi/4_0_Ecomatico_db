SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioniMovimenti](
	[IdImportazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Anno] [smallint] NOT NULL,
	[Progressivo] [int] NOT NULL,
	[Identificativo] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[IsIntervallo] [bit] NOT NULL,
	[Json] [nvarchar](max) COLLATE Latin1_General_CI_AS NULL,
	[JsonDettaglio] [nvarchar](max) COLLATE Latin1_General_CI_AS NULL,
	[JsonValori] [nvarchar](max) COLLATE Latin1_General_CI_AS NULL,
	[Tipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[RettificaAnno] [smallint] NULL,
	[RettificaProgressivo] [int] NULL,
	[Data] [date] NULL,
	[DataOra] [datetime2](0) NULL,
	[DataTrasmissione] [datetime2](0) NULL,
	[Causale] [varchar](5) COLLATE Latin1_General_CI_AS NULL,
	[IdOperazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Eer] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[StatoFisico] [varchar](5) COLLATE Latin1_General_CI_AS NULL,
	[Quantita] [decimal](18, 4) NULL,
	[UnitaMisura] [varchar](5) COLLATE Latin1_General_CI_AS NULL,
	[IsAnnullato] [bit] NULL,
	[IsRettificato] [bit] NULL,
	[Azione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdRegistrazione] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NULL,
	[IdMateriale] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdStatoFisico] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdUnitaMisura] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[JsonFormulario] [nvarchar](max) COLLATE Latin1_General_CI_AS NULL,
	[FormularioStato] [char](1) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblRentriImportazioniMovimenti] PRIMARY KEY CLUSTERED 
(
	[IdImportazione] ASC,
	[Anno] ASC,
	[Progressivo] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO

-- Registrazioni create dalle importazioni (filtro "Importate da RENTRI" e finestra "RENTRI - Stato"). Non filtrato
-- (WHERE IdRegistrazione IS NOT NULL): un indice filtrato farebbe fallire le scritture delle SP installate con
-- QUOTED_IDENTIFIER OFF (default di sqlcmd)
CREATE NONCLUSTERED INDEX [IX_RentriImportazioniMovimenti_IdRegistrazione] ON [dbo].[tblRentriImportazioniMovimenti]
(
	[IdRegistrazione] ASC
)
INCLUDE([Azione])
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblRentriImportazioniMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniMovimenti_tblRentriImportazioni] FOREIGN KEY([IdImportazione])
REFERENCES [dbo].[tblRentriImportazioni] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblRentriImportazioniMovimenti] CHECK CONSTRAINT [FK_tblRentriImportazioniMovimenti_tblRentriImportazioni]
GO
