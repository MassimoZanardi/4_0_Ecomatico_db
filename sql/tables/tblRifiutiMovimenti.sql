SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiMovimenti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRegistro] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdOperazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdModello] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NULL,
	[IdStatoFisico] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdAttivita] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdSedeProduttoreDetentore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSedeDestinatario] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSedeTrasportatore1] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSedeIntermediario1] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdUnitaMisura] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdProvenienza] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Quantita] [decimal](18, 2) NULL,
	[EerDescrizione] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	[FormularioNumero] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[DataInizioTrasporto] [smalldatetime] NULL,
	[Note] [varchar](500) COLLATE Latin1_General_CI_AS NULL,
	[RentriFormularioStato] [varchar](40) COLLATE Latin1_General_CI_AS NULL,
	[RentriFormularioDataCopia] [smalldatetime] NULL,
	[RentriFormularioDataTrasmissione] [smalldatetime] NULL,
	[RentriFormularioDataPresaVisione] [smalldatetime] NULL,
	[RentriFormularioDataConservazione] [smalldatetime] NULL,
	[RentriFormularioInviiConservazione] [int] NULL,
 CONSTRAINT [PK_tblRifiutiMovimenti] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RifiutiMovimenti_IdRegistro] ON [dbo].[tblRifiutiMovimenti]
(
	[IdRegistro] ASC
)
INCLUDE([IdOperazione],[IdEer],[IdStatoFisico],[IdUnitaMisura],[Quantita],[IdSedeDestinatario],[IdSedeIntermediario1],[FormularioNumero],[IdAttivita],[IdSedeProduttoreDetentore],[IdSedeTrasportatore1],[IdProvenienza]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiAttivitaRecuperoSmaltimento] FOREIGN KEY([IdAttivita])
REFERENCES [dbo].[tblRifiutiAttivitaRecuperoSmaltimento] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti] CHECK CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiAttivitaRecuperoSmaltimento]
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiEer] FOREIGN KEY([IdEer])
REFERENCES [dbo].[tblRifiutiEer] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti] CHECK CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiEer]
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiModelli] FOREIGN KEY([IdModello])
REFERENCES [dbo].[tblRifiutiModelli] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti] CHECK CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiModelli]
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiOperazioni] FOREIGN KEY([IdOperazione])
REFERENCES [dbo].[tblRifiutiOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti] CHECK CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiOperazioni]
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiProvenienze] FOREIGN KEY([IdProvenienza])
REFERENCES [dbo].[tblRifiutiProvenienze] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti] CHECK CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiProvenienze]
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiRegistri] FOREIGN KEY([IdRegistro])
REFERENCES [dbo].[tblRifiutiRegistri] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti] CHECK CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiRegistri]
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiStatiFisici] FOREIGN KEY([IdStatoFisico])
REFERENCES [dbo].[tblRifiutiStatiFisici] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti] CHECK CONSTRAINT [FK_tblRifiutiMovimenti_tblRifiutiStatiFisici]
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimenti_tblSedi_IdSedeDestinatario] FOREIGN KEY([IdSedeDestinatario])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti] CHECK CONSTRAINT [FK_tblRifiutiMovimenti_tblSedi_IdSedeDestinatario]
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimenti_tblSedi_IdSedeIntermediario1] FOREIGN KEY([IdSedeIntermediario1])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti] CHECK CONSTRAINT [FK_tblRifiutiMovimenti_tblSedi_IdSedeIntermediario1]
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimenti_tblSedi_IdSedeProduttoreDetentore] FOREIGN KEY([IdSedeProduttoreDetentore])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti] CHECK CONSTRAINT [FK_tblRifiutiMovimenti_tblSedi_IdSedeProduttoreDetentore]
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimenti_tblSedi_IdSedeTrasportatore1] FOREIGN KEY([IdSedeTrasportatore1])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti] CHECK CONSTRAINT [FK_tblRifiutiMovimenti_tblSedi_IdSedeTrasportatore1]
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimenti_tblUnitaMisura] FOREIGN KEY([IdUnitaMisura])
REFERENCES [dbo].[tblUnitaMisura] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimenti] CHECK CONSTRAINT [FK_tblRifiutiMovimenti_tblUnitaMisura]