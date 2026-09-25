-- Magazzino - relazioni carico/scarico, tranche 1 (righe tradizionali): struttura.
-- Stessa logica di tblRifiutiRegistrazioniRelazioni: la riga di carico indica il proprio
-- lotto (IdLotto) ed è essa stessa la giacenza; la riga di scarico si relaziona alle righe
-- di carico che consuma (IdParent = scarico, Id = carico). tblMagazziniMovimentiRigheLotti
-- viene eliminata a fine tranche (tools/magazzino_relazioni_t1_drop.sql), dopo le SP.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF COL_LENGTH('dbo.tblMagazziniMovimentiRighe', 'IdLotto') IS NULL
	ALTER TABLE [dbo].[tblMagazziniMovimentiRighe] ADD [IdLotto] [char](16) COLLATE Latin1_General_CI_AS NULL;
GO

IF OBJECT_ID('dbo.FK_tblMagazziniMovimentiRighe_tblMagazziniLotti', 'F') IS NULL
	ALTER TABLE [dbo].[tblMagazziniMovimentiRighe]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRighe_tblMagazziniLotti] FOREIGN KEY([IdLotto])
	REFERENCES [dbo].[tblMagazziniLotti] ([Id]);
GO

IF OBJECT_ID('dbo.tblMagazziniMovimentiRigheRelazioni', 'U') IS NULL
BEGIN
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
	) ON [PRIMARY];

	ALTER TABLE [dbo].[tblMagazziniMovimentiRigheRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheRelazioni_tblMagazziniMovimentiRighe] FOREIGN KEY([Id])
	REFERENCES [dbo].[tblMagazziniMovimentiRighe] ([Id]);

	ALTER TABLE [dbo].[tblMagazziniMovimentiRigheRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheRelazioni_tblMagazziniMovimentiRighe_Parent] FOREIGN KEY([IdParent])
	REFERENCES [dbo].[tblMagazziniMovimentiRighe] ([Id]);

	CREATE NONCLUSTERED INDEX [IX_MagazziniMovimentiRigheRelazioni_IdParent] ON [dbo].[tblMagazziniMovimentiRigheRelazioni]
	(
		[IdParent] ASC
	)
	INCLUDE([Id],[Quantita],[Pos]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];
END
GO
