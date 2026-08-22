SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiModelli](
	[Id] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdRegistro] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdOperazione] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdEer] [char](6) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdStatoFisico] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdAttivita] [char](2) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdUnitaMisura] [char](2) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdImballo] [char](2) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdAdr] [char](2) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdAutorizzazioneProduttoreDetentore] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdAutorizzazioneDestinatario] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdAutorizzazioneTrasportatore1] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdAutorizzazioneIntermediario1] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdTipoTrasporto1] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Nome] [varchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Note] [varchar](500) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[UtenteNote] [varchar](500) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Etichette] [varchar](2000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Lock] [tinyint] NULL,
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