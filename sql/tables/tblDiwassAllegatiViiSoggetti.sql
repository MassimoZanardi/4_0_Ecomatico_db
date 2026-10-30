SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblDiwassAllegatiViiSoggetti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Ruolo] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[Pos] [tinyint] NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[PartyUuid] [uniqueidentifier] NOT NULL,
	[ContattoNome] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[ContattoTelefono] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[ContattoEmail] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[MezzoTrasporto] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[ImpiantoIntermedio] [bit] NULL,
	[NomeRiservato] [bit] NULL,
	[MotivoRiservatezza] [varchar](500) COLLATE Latin1_General_CI_AS NULL,
	[OperatorInternalId] [bigint] NULL,
	[Nome] [nvarchar](250) COLLATE Latin1_General_CI_AS NULL,
	[Indirizzo] [nvarchar](500) COLLATE Latin1_General_CI_AS NULL,
	[Paese] [char](2) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblDiwassAllegatiViiSoggetti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[Ruolo] ASC,
	[Pos] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblDiwassAllegatiViiSoggetti] ADD  CONSTRAINT [DF_tblDiwassAllegatiViiSoggetti_PartyUuid]  DEFAULT (newid()) FOR [PartyUuid]
GO

ALTER TABLE [dbo].[tblDiwassAllegatiViiSoggetti]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassAllegatiViiSoggetti_tblDiwassAllegatiVii] FOREIGN KEY([Id])
REFERENCES [dbo].[tblDiwassAllegatiVii] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassAllegatiViiSoggetti] CHECK CONSTRAINT [FK_tblDiwassAllegatiViiSoggetti_tblDiwassAllegatiVii]
GO

ALTER TABLE [dbo].[tblDiwassAllegatiViiSoggetti]  WITH CHECK ADD  CONSTRAINT [FK_tblDiwassAllegatiViiSoggetti_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblDiwassAllegatiViiSoggetti] CHECK CONSTRAINT [FK_tblDiwassAllegatiViiSoggetti_tblSedi]
GO
