SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiRegistrazioni](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdMovimento] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEsito] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdRaee] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdCausaleRespingimento] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdTrasportoTransfrontalieroTipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdMateriale] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdAttivitaProvenienza] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdUnitaMisuraQuantitaRespinta] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[CausaleRespingimentoAltro] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[QuantitaRespinta] [decimal](18, 2) NULL,
	[DataFineTrasporto] [smalldatetime] NULL,
	[Operazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Data] [date] NULL,
	[Numero] [int] NULL,
	[QuantitaVerificata] [decimal](18, 2) NULL,
	[VeicoloFuoriUso] [bit] NULL,
	[VeicoloFuoriUsoNumero] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[VeicoloFuoriUsoData] [date] NULL,
	[MaterialeDescrizione] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	[RentriIdentificativo] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[RentriData] [datetime2](0) NULL,
	[RentriSincronizzata] [bit] NULL,
	[ConservazioneSostitutiva] [bit] NULL,
	[Etichette] [varchar](2000) COLLATE Latin1_General_CI_AS NULL,
	[Note] [varchar](500) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblRifiutiRegistrazioni] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

CREATE NONCLUSTERED INDEX [IX_RifiutiRegistrazioni_Data_Lock] ON [dbo].[tblRifiutiRegistrazioni]
(
	[Data] DESC
)
INCLUDE([IdMovimento],[Numero],[QuantitaVerificata],[Operazione],[Etichette]) 
WHERE ([Lock]<(2))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RifiutiRegistrazioni_IdMovimento_Data_Numero_Lock] ON [dbo].[tblRifiutiRegistrazioni]
(
	[IdMovimento] ASC,
	[Data] ASC,
	[Numero] ASC
)
INCLUDE([QuantitaVerificata],[DataFineTrasporto],[IdTrasportoTransfrontalieroTipo],[Note],[Operazione],[Etichette],[RentriIdentificativo],[RentriData]) 
WHERE ([Lock]<(2))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiAttivitaProvenienze] FOREIGN KEY([IdAttivitaProvenienza])
REFERENCES [dbo].[tblRifiutiAttivitaProvenienze] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiAttivitaProvenienze]
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiDocumentiTrasportiTipi] FOREIGN KEY([IdTrasportoTransfrontalieroTipo])
REFERENCES [dbo].[tblRifiutiDocumentiTrasportiTipi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiDocumentiTrasportiTipi]
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiMateriali] FOREIGN KEY([IdMateriale])
REFERENCES [dbo].[tblRifiutiMateriali] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiMateriali]
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiMovimenti] FOREIGN KEY([IdMovimento])
REFERENCES [dbo].[tblRifiutiMovimenti] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiMovimenti]
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiRaee] FOREIGN KEY([IdRaee])
REFERENCES [dbo].[tblRifiutiRaee] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiRaee]
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiRegistrazioniEsiti] FOREIGN KEY([IdEsito])
REFERENCES [dbo].[tblRifiutiRegistrazioniEsiti] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiRegistrazioniEsiti]
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiRegistrazioniEsitiCausaliRespingimento] FOREIGN KEY([IdCausaleRespingimento])
REFERENCES [dbo].[tblRifiutiRegistrazioniEsitiCausaliRespingimento] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblRifiutiRegistrazioniEsitiCausaliRespingimento]
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioni_tblUnitaMisura] FOREIGN KEY([IdUnitaMisuraQuantitaRespinta])
REFERENCES [dbo].[tblUnitaMisura] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioni_tblUnitaMisura]
GO
