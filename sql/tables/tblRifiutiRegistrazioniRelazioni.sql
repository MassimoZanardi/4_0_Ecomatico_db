SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRifiutiRegistrazioniRelazioni](
	[Id] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdParent] [char](16) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Operazione] [char](1) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Quantita] [decimal](18, 2) NULL,
	[Pos] [int] NULL,
 CONSTRAINT [PK_tblRifiutiRegistrazioniRelazioni] PRIMARY KEY CLUSTERED 
(
	[Id] ASC,
	[IdParent] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RifiutiRegistrazioniRelazioni_IdParent] ON [dbo].[tblRifiutiRegistrazioniRelazioni]
(
	[IdParent] ASC
)
INCLUDE([Id],[Quantita],[Pos],[Operazione]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioniRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioniRelazioni_tblRifiutiRegistrazioni_Id] FOREIGN KEY([Id])
REFERENCES [dbo].[tblRifiutiRegistrazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioniRelazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioniRelazioni_tblRifiutiRegistrazioni_Id]
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioniRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRifiutiRegistrazioniRelazioni_tblRifiutiRegistrazioni_IdParent] FOREIGN KEY([IdParent])
REFERENCES [dbo].[tblRifiutiRegistrazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRifiutiRegistrazioniRelazioni] CHECK CONSTRAINT [FK_tblRifiutiRegistrazioniRelazioni_tblRifiutiRegistrazioni_IdParent]