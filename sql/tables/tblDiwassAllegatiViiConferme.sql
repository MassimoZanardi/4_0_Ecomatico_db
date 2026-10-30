SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblDiwassAllegatiViiConferme](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Tipo] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[Pos] [tinyint] NOT NULL,
	[Numero] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[OperatorInternalId] [bigint] NULL,
	[Data] [date] NULL,
	[MezzoTrasporto] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Targhe] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	[UnitaQuantita] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[QuantitaAccettata] [decimal](18, 5) NULL,
	[QuantitaRespinta] [decimal](18, 5) NULL,
	[MotivoRespingimento] [nvarchar](500) COLLATE Latin1_General_CI_AS NULL,
	[QuantitaRiutilizzo] [decimal](18, 5) NULL,
	[QuantitaRecupero] [decimal](18, 5) NULL,
	[Descrizione] [nvarchar](500) COLLATE Latin1_General_CI_AS NULL,
	[ContattoNome] [nvarchar](100) COLLATE Latin1_General_CI_AS NULL,
	[ContattoTelefono] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[ContattoEmail] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[FirmaNome] [nvarchar](100) COLLATE Latin1_General_CI_AS NULL,
	[FirmaRuolo] [nvarchar](100) COLLATE Latin1_General_CI_AS NULL,
	[FirmaData] [datetime2](0) NULL,
	[FirmaEmail] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblDiwassAllegatiViiConferme] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[Tipo] ASC,
	[Pos] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblDiwassAllegatiViiConferme]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassAllegatiViiConferme_tblDiwassAllegatiVii] FOREIGN KEY([Id])
REFERENCES [dbo].[tblDiwassAllegatiVii] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassAllegatiViiConferme] CHECK CONSTRAINT [FK_tblDiwassAllegatiViiConferme_tblDiwassAllegatiVii]
GO
