SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiFormulari](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdMovimento] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdImballo] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdAdr] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdAnalisiTipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[TrasportoAdr] [bit] NULL,
	[DataEmissione] [date] NULL,
	[AnalisiData] [date] NULL,
	[AnalisiNumero] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Detentore] [bit] NULL,
	[LuogoDiProduzione] [bit] NULL,
	[VerificatoInPartenza] [bit] NULL,
	[NumeroOnu] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[AdrNote] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	[ColliNumero] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[AllaRinfusa] [bit] NULL,
	[Note] [varchar](500) COLLATE Latin1_General_CI_AS NULL,
	[Etichette] [varchar](2000) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblRifiutiFormulari] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

CREATE NONCLUSTERED INDEX [IX_RifiutiFormulari_DataEmissione_Lock] ON [dbo].[tblRifiutiFormulari]
(
	[DataEmissione] DESC
)
INCLUDE([IdMovimento],[Etichette]) 
WHERE ([Lock]<(2))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RifiutiFormulari_IdMovimento_Lock] ON [dbo].[tblRifiutiFormulari]
(
	[IdMovimento] ASC
)
INCLUDE([DataEmissione]) 
WHERE ([Lock]<(2))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblRifiutiFormulari]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiFormulari_tblAdr] FOREIGN KEY([IdAdr])
REFERENCES [dbo].[tblAdr] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiFormulari] CHECK CONSTRAINT [FK_tblRifiutiFormulari_tblAdr]
GO

ALTER TABLE [dbo].[tblRifiutiFormulari]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiFormulari_tblImballi] FOREIGN KEY([IdImballo])
REFERENCES [dbo].[tblImballi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiFormulari] CHECK CONSTRAINT [FK_tblRifiutiFormulari_tblImballi]
GO

ALTER TABLE [dbo].[tblRifiutiFormulari]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiFormulari_tblRifiutiAnalisiTipi] FOREIGN KEY([IdAnalisiTipo])
REFERENCES [dbo].[tblRifiutiAnalisiTipi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiFormulari] CHECK CONSTRAINT [FK_tblRifiutiFormulari_tblRifiutiAnalisiTipi]
GO

ALTER TABLE [dbo].[tblRifiutiFormulari]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiFormulari_tblRifiutiMovimenti] FOREIGN KEY([IdMovimento])
REFERENCES [dbo].[tblRifiutiMovimenti] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiFormulari] CHECK CONSTRAINT [FK_tblRifiutiFormulari_tblRifiutiMovimenti]