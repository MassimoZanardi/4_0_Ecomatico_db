SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblDiwassAllegatiVii](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdAziendaInterna] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRegistrazione] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Numero] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Stato] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[DataInvio] [smalldatetime] NULL,
	[DataStato] [smalldatetime] NULL,
	[TipoDestinazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[DataSpedizione] [date] NULL,
	[Quantita] [decimal](18, 5) NULL,
	[UnitaQuantita] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Contenitore] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[LuogoPartenza] [varchar](300) COLLATE Latin1_General_CI_AS NULL,
	[ResponsabileNome] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[ResponsabileTelefono] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[ResponsabileEmail] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NULL,
	[Descrizione] [varchar](500) COLLATE Latin1_General_CI_AS NULL,
	[CodiceDoganale] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[IdNazioneSpedizione] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdNazioneDestinazione] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdNazioneTransito1] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdNazioneTransito2] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdAttivita] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[ListaCodice] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[Codice] [nvarchar](20) COLLATE Latin1_General_CI_AS NULL,
	[FirmaNome] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[FirmaRuolo] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[FirmaEmail] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[FirmaData] [datetime2](0) NULL,
	[ProduttoreFirmaNome] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[ProduttoreFirmaRuolo] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[ProduttoreFirmaData] [datetime2](0) NULL,
	[Note] [varchar](500) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
	[DaInviare] [bit] NULL,
	[Ricevuto] [bit] NULL,
	[Ruoli] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[DataLettura] [datetime2](0) NULL,
 CONSTRAINT [PK_tblDiwassAllegatiVii] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_DiwassAllegatiVii_IdAziendaInterna_Lock] ON [dbo].[tblDiwassAllegatiVii]
(
	[IdAziendaInterna] ASC,
	[Lock] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_DiwassAllegatiVii_IdRegistrazione] ON [dbo].[tblDiwassAllegatiVii]
(
	[IdRegistrazione] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_DiwassAllegatiVii_Numero] ON [dbo].[tblDiwassAllegatiVii]
(
	[Numero] ASC,
	[IdAziendaInterna] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblDiwassAllegatiVii]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassAllegatiVii_tblDiwassCodiciRifiuti] FOREIGN KEY([ListaCodice], [Codice])
REFERENCES [dbo].[tblDiwassCodiciRifiuti] ([Lista], [Codice])
GO

ALTER TABLE [dbo].[tblDiwassAllegatiVii] CHECK CONSTRAINT [FK_tblDiwassAllegatiVii_tblDiwassCodiciRifiuti]
GO

ALTER TABLE [dbo].[tblDiwassAllegatiVii]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassAllegatiVii_tblRifiutiAttivitaRecuperoSmaltimento] FOREIGN KEY([IdAttivita])
REFERENCES [dbo].[tblRifiutiAttivitaRecuperoSmaltimento] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassAllegatiVii] CHECK CONSTRAINT [FK_tblDiwassAllegatiVii_tblRifiutiAttivitaRecuperoSmaltimento]
GO

ALTER TABLE [dbo].[tblDiwassAllegatiVii]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassAllegatiVii_tblRifiutiEer] FOREIGN KEY([IdEer])
REFERENCES [dbo].[tblRifiutiEer] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassAllegatiVii] CHECK CONSTRAINT [FK_tblDiwassAllegatiVii_tblRifiutiEer]
GO

ALTER TABLE [dbo].[tblDiwassAllegatiVii]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassAllegatiVii_tblRifiutiRegistrazioni] FOREIGN KEY([IdRegistrazione])
REFERENCES [dbo].[tblRifiutiRegistrazioni] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassAllegatiVii] CHECK CONSTRAINT [FK_tblDiwassAllegatiVii_tblRifiutiRegistrazioni]
GO

ALTER TABLE [dbo].[tblDiwassAllegatiVii]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassAllegatiVii_tblSediInterne] FOREIGN KEY([IdAziendaInterna])
REFERENCES [dbo].[tblSediInterne] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassAllegatiVii] CHECK CONSTRAINT [FK_tblDiwassAllegatiVii_tblSediInterne]
GO
