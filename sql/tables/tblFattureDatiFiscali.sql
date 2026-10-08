SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblFattureDatiFiscali](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRegimeFiscale] [char](4) COLLATE Latin1_General_CI_AS NULL,
	[IdProvinciaRea] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdRitenutaTipo] [char](4) COLLATE Latin1_General_CI_AS NULL,
	[IdRitenutaCausale] [varchar](2) COLLATE Latin1_General_CI_AS NULL,
	[NumeroRea] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[CapitaleSociale] [decimal](18, 2) NULL,
	[SocioUnico] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[StatoLiquidazione] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[ProgressivoInvio] [int] NULL,
 CONSTRAINT [PK_tblFattureDatiFiscali] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[tblFattureDatiFiscali]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureDatiFiscali_tblFattureRegimiFiscali] FOREIGN KEY([IdRegimeFiscale])
REFERENCES [dbo].[tblFattureRegimiFiscali] ([Id])
GO
ALTER TABLE [dbo].[tblFattureDatiFiscali] CHECK CONSTRAINT [FK_tblFattureDatiFiscali_tblFattureRegimiFiscali]
GO
ALTER TABLE [dbo].[tblFattureDatiFiscali]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureDatiFiscali_tblFattureRitenuteCausali] FOREIGN KEY([IdRitenutaCausale])
REFERENCES [dbo].[tblFattureRitenuteCausali] ([Id])
GO
ALTER TABLE [dbo].[tblFattureDatiFiscali] CHECK CONSTRAINT [FK_tblFattureDatiFiscali_tblFattureRitenuteCausali]
GO
ALTER TABLE [dbo].[tblFattureDatiFiscali]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureDatiFiscali_tblFattureRitenuteTipi] FOREIGN KEY([IdRitenutaTipo])
REFERENCES [dbo].[tblFattureRitenuteTipi] ([Id])
GO
ALTER TABLE [dbo].[tblFattureDatiFiscali] CHECK CONSTRAINT [FK_tblFattureDatiFiscali_tblFattureRitenuteTipi]
GO
ALTER TABLE [dbo].[tblFattureDatiFiscali]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureDatiFiscali_tblProvince] FOREIGN KEY([IdProvinciaRea])
REFERENCES [dbo].[tblProvince] ([Id])
GO
ALTER TABLE [dbo].[tblFattureDatiFiscali] CHECK CONSTRAINT [FK_tblFattureDatiFiscali_tblProvince]
GO
ALTER TABLE [dbo].[tblFattureDatiFiscali]  WITH CHECK ADD  CONSTRAINT [FK_tblFattureDatiFiscali_tblSedi] FOREIGN KEY([Id])
REFERENCES [dbo].[tblSedi] ([Id])
GO
ALTER TABLE [dbo].[tblFattureDatiFiscali] CHECK CONSTRAINT [FK_tblFattureDatiFiscali_tblSedi]
GO
