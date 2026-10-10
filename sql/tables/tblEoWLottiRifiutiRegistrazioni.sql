SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblEoWLottiRifiutiRegistrazioni](
	[IdRegistrazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdLotto] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Quantita] [decimal](18, 2) NULL,
	[Pos] [int] NULL,
	[IdAllocazioneTipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblEoWLottiRifiutiRegistrazioni] PRIMARY KEY CLUSTERED 
(
	[IdRegistrazione] ASC,
	[IdLotto] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_EoWLottiRifiutiRegistrazioni_IdLotto] ON [dbo].[tblEoWLottiRifiutiRegistrazioni]
(
	[IdLotto] ASC
)
INCLUDE([Quantita]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblEoWLottiRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWLottiRifiutiRegistrazioni_tblEoWAllocazioniTipi] FOREIGN KEY([IdAllocazioneTipo])
REFERENCES [dbo].[tblEoWAllocazioniTipi] ([Id])
GO

ALTER TABLE [dbo].[tblEoWLottiRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblEoWLottiRifiutiRegistrazioni_tblEoWAllocazioniTipi]
GO

ALTER TABLE [dbo].[tblEoWLottiRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWLottiRifiutiRegistrazioni_tblEoWLotti] FOREIGN KEY([IdLotto])
REFERENCES [dbo].[tblEoWLotti] ([Id])
GO

ALTER TABLE [dbo].[tblEoWLottiRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblEoWLottiRifiutiRegistrazioni_tblEoWLotti]
GO

ALTER TABLE [dbo].[tblEoWLottiRifiutiRegistrazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblEoWLottiRifiutiRegistrazioni_tblRifiutiRegistrazioni] FOREIGN KEY([IdRegistrazione])
REFERENCES [dbo].[tblRifiutiRegistrazioni] ([Id])
GO

ALTER TABLE [dbo].[tblEoWLottiRifiutiRegistrazioni] CHECK CONSTRAINT [FK_tblEoWLottiRifiutiRegistrazioni_tblRifiutiRegistrazioni]
GO
