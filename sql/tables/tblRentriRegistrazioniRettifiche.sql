SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriRegistrazioniRettifiche](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRettifica] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdUnitaMisura] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NULL,
	[IdStatoFisico] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Quantita] [decimal](18, 2) NULL,
	[EerDescrizione] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	[Annullata] [bit] NULL,
 CONSTRAINT [PK_tblRentriRegistrazioniRettifiche] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdRettifica] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE UNIQUE NONCLUSTERED INDEX [IX_RentriRegistrazioniRettifiche_IdRettifica] ON [dbo].[tblRentriRegistrazioniRettifiche]
(
	[IdRettifica] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriRegistrazioniRettifiche]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriRegistrazioniRettifiche_tblRifiutiRegistrazioni_id] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiRegistrazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRentriRegistrazioniRettifiche] CHECK CONSTRAINT [FK_tblRentriRegistrazioniRettifiche_tblRifiutiRegistrazioni_id]
GO

ALTER TABLE [dbo].[tblRentriRegistrazioniRettifiche]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriRegistrazioniRettifiche_tblRifiutiRegistrazioni_idRettifica] FOREIGN KEY([IdRettifica])
REFERENCES [dbo].[tblRifiutiRegistrazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRentriRegistrazioniRettifiche] CHECK CONSTRAINT [FK_tblRentriRegistrazioniRettifiche_tblRifiutiRegistrazioni_idRettifica]
GO
