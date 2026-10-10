SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiMovimentiLog](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Data] [datetime2](0) NOT NULL,
	[IdUtente] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NULL,
	[IdStatoFisico] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdMateriale] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdAttivita] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdUnitaMisura] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Quantita] [decimal](18, 2) NULL,
	[QuantitaVerificata] [decimal](18, 2) NULL,
	[IdAutorizzazioneProduttoreDetentore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdAutorizzazioneDestinatario] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdAutorizzazioneTrasportatore1] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdAutorizzazioneIntermediario1] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[RegistrazioneNumero] [int] NULL,
	[RegistrazioneData] [date] NULL,
	[FormularioNumero] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[DataInizioTrasporto] [smalldatetime] NULL,
	[DataFineTrasporto] [smalldatetime] NULL,
 CONSTRAINT [PK_tblRifiutiMovimentiLog] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[Data] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRifiutiMovimentiLog]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiMovimentiLog_tblRifiutiMovimenti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiMovimenti] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiMovimentiLog] CHECK CONSTRAINT [FK_tblRifiutiMovimentiLog_tblRifiutiMovimenti]
GO
