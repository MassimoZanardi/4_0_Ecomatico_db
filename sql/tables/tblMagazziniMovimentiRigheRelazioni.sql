SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- Relazioni carico/scarico tra righe di magazzino, stessa struttura di
-- tblRifiutiRegistrazioniRelazioni: [IdParent] è la riga di scarico, [Id] la riga di
-- carico consumata. Quantita = quanto lo scarico preleva da quel carico, Pos = ordine
-- di consumo (dal criterio di scarico, o dall'associazione manuale).
CREATE TABLE [dbo].[tblMagazziniMovimentiRigheRelazioni](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdParent] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Quantita] [decimal](18, 2) NULL,
	[Pos] [int] NULL,
 CONSTRAINT [PK_tblMagazziniMovimentiRigheRelazioni] PRIMARY KEY CLUSTERED
(
	[Id] ASC,
	[IdParent] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheRelazioni_tblMagazziniMovimentiRighe] FOREIGN KEY([Id])
REFERENCES [dbo].[tblMagazziniMovimentiRighe] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheRelazioni] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRigheRelazioni_tblMagazziniMovimentiRighe]
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheRelazioni_tblMagazziniMovimentiRighe_Parent] FOREIGN KEY([IdParent])
REFERENCES [dbo].[tblMagazziniMovimentiRighe] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheRelazioni] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRigheRelazioni_tblMagazziniMovimentiRighe_Parent]
GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_MagazziniMovimentiRigheRelazioni_IdParent] ON [dbo].[tblMagazziniMovimentiRigheRelazioni]
(
	[IdParent] ASC
)
INCLUDE([Id],[Quantita],[Pos]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
