SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiModelli](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRegistro] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdOperazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NULL,
	[IdStatoFisico] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdAttivita] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdUnitaMisura] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdImballo] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdAdr] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdAutorizzazioneProduttoreDetentore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdAutorizzazioneDestinatario] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdAutorizzazioneTrasportatore1] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdAutorizzazioneIntermediario1] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdTipoTrasporto1] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[UtenteNote] [varchar](500) COLLATE Latin1_General_CI_AS NULL,
	[Etichette] [varchar](2000) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
	[IdProvenienza] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdMateriale] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[MaterialeDescrizione] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	[LuogoDiProduzione] [bit] NULL,
	[Detentore] [bit] NULL,
	[IdAutorizzazioneTrasportatore2] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdAutorizzazioneTrasportatore3] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdTipoTrasporto2] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdTipoTrasporto3] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdAutorizzazioneIntermediario2] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdAutorizzazioneIntermediario3] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdTrasportoTransfrontalieroTipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdRaee] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[AllaRinfusa] [bit] NULL,
	[TrasportoAdr] [bit] NULL,
	[NumeroOnu] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[AdrNote] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	[IdAnalisiTipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[AnalisiData] [date] NULL,
	[AnalisiNumero] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[RegistrazioneNote] [varchar](500) COLLATE Latin1_General_CI_AS NULL,
	[FormularioNote] [varchar](500) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblRifiutiModelli] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RifiutiModelli_IdRegistro_Lock] ON [dbo].[tblRifiutiModelli]
(
	[IdRegistro] ASC
)
WHERE ([Lock]<(2))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblAdr] FOREIGN KEY([IdAdr])
REFERENCES [dbo].[tblAdr] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblAdr]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblImballi] FOREIGN KEY([IdImballo])
REFERENCES [dbo].[tblImballi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblImballi]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAttivitaRecuperoSmaltimento] FOREIGN KEY([IdAttivita])
REFERENCES [dbo].[tblRifiutiAttivitaRecuperoSmaltimento] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAttivitaRecuperoSmaltimento]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni] FOREIGN KEY([IdAutorizzazioneIntermediario1])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneDestinatario] FOREIGN KEY([IdAutorizzazioneDestinatario])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneDestinatario]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneProduttoreDetentore] FOREIGN KEY([IdAutorizzazioneProduttoreDetentore])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneProduttoreDetentore]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneTrasportatore1] FOREIGN KEY([IdAutorizzazioneTrasportatore1])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneTrasportatore1]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiEer] FOREIGN KEY([IdEer])
REFERENCES [dbo].[tblRifiutiEer] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiEer]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiMovimentiTrasportiTipi1] FOREIGN KEY([IdTipoTrasporto1])
REFERENCES [dbo].[tblRifiutiMovimentiTrasportiTipi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiMovimentiTrasportiTipi1]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiOperazioni] FOREIGN KEY([IdOperazione])
REFERENCES [dbo].[tblRifiutiOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiOperazioni]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiRegistri] FOREIGN KEY([IdRegistro])
REFERENCES [dbo].[tblRifiutiRegistri] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiRegistri]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiStatiFisici] FOREIGN KEY([IdStatoFisico])
REFERENCES [dbo].[tblRifiutiStatiFisici] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiStatiFisici]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblUnitaMisura] FOREIGN KEY([IdUnitaMisura])
REFERENCES [dbo].[tblUnitaMisura] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblUnitaMisura]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiProvenienze] FOREIGN KEY([IdProvenienza])
REFERENCES [dbo].[tblRifiutiProvenienze] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiProvenienze]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiMateriali] FOREIGN KEY([IdMateriale])
REFERENCES [dbo].[tblRifiutiMateriali] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiMateriali]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneTrasportatore2] FOREIGN KEY([IdAutorizzazioneTrasportatore2])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneTrasportatore2]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneTrasportatore3] FOREIGN KEY([IdAutorizzazioneTrasportatore3])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneTrasportatore3]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneIntermediario2] FOREIGN KEY([IdAutorizzazioneIntermediario2])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneIntermediario2]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneIntermediario3] FOREIGN KEY([IdAutorizzazioneIntermediario3])
REFERENCES [dbo].[tblRifiutiAutorizzazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAutorizzazioni_IdAutorizzazioneIntermediario3]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiMovimentiTrasportiTipi2] FOREIGN KEY([IdTipoTrasporto2])
REFERENCES [dbo].[tblRifiutiMovimentiTrasportiTipi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiMovimentiTrasportiTipi2]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiMovimentiTrasportiTipi3] FOREIGN KEY([IdTipoTrasporto3])
REFERENCES [dbo].[tblRifiutiMovimentiTrasportiTipi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiMovimentiTrasportiTipi3]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiDocumentiTrasportiTipi] FOREIGN KEY([IdTrasportoTransfrontalieroTipo])
REFERENCES [dbo].[tblRifiutiDocumentiTrasportiTipi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiDocumentiTrasportiTipi]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiRaee] FOREIGN KEY([IdRaee])
REFERENCES [dbo].[tblRifiutiRaee] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiRaee]
GO

ALTER TABLE [dbo].[tblRifiutiModelli]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAnalisiTipi] FOREIGN KEY([IdAnalisiTipo])
REFERENCES [dbo].[tblRifiutiAnalisiTipi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiModelli] CHECK CONSTRAINT [FK_tblRifiutiModelli_tblRifiutiAnalisiTipi]