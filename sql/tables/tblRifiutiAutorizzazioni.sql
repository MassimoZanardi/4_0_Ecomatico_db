SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiAutorizzazioni](
	[Id] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdRuolo] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdTipo] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IdNumeroTipo] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Numero] [varchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Identificativo] [varchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[DataInizio] [date] NULL,
	[DataFine] [date] NULL,
	[Note] [varchar](500) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Nessuna] [bit] NULL,
	[Disabilitata] [bit] NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblRifiutiAutorizzazioni] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RifiutiAutorizzazioni_IdSede_IdRuolo_Lock] ON [dbo].[tblRifiutiAutorizzazioni]
(
	[IdSede] ASC,
	[IdRuolo] ASC
)
INCLUDE([Numero],[Identificativo],[Disabilitata],[Nessuna]) 
WHERE ([Lock]<(2))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiAutorizzazioni_tblRifiutiAutorizzazioniNumeriTipi] FOREIGN KEY([IdNumeroTipo])
REFERENCES [dbo].[tblRifiutiAutorizzazioniNumeriTipi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioni] CHECK CONSTRAINT [FK_tblRifiutiAutorizzazioni_tblRifiutiAutorizzazioniNumeriTipi]
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiAutorizzazioni_tblRifiutiAutorizzazioniTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblRifiutiAutorizzazioniTipi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioni] CHECK CONSTRAINT [FK_tblRifiutiAutorizzazioni_tblRifiutiAutorizzazioniTipi]
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiAutorizzazioni_tblRifiutiRuoli] FOREIGN KEY([IdRuolo])
REFERENCES [dbo].[tblRifiutiRuoli] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioni] CHECK CONSTRAINT [FK_tblRifiutiAutorizzazioni_tblRifiutiRuoli]
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiAutorizzazioni_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiAutorizzazioni] CHECK CONSTRAINT [FK_tblRifiutiAutorizzazioni_tblSedi]