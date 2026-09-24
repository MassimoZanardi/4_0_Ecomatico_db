SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- NOTA: [Id] qui è la FK alla riga padre (tblMagazziniMovimentiRighe.Id), non un id
-- proprio della tabella. PK composita (Id, IdLotto): un solo record per coppia
-- riga+lotto, coerente con la ripartizione della riga sui lotti.
CREATE TABLE [dbo].[tblMagazziniMovimentiRigheLotti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdLotto] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Quantita] [decimal](18, 2) NULL,
 CONSTRAINT [PK_tblMagazziniMovimentiRigheLotti] PRIMARY KEY CLUSTERED
(
	[Id] ASC,
	[IdLotto] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheLotti]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheLotti_tblMagazziniMovimentiRighe] FOREIGN KEY([Id])
REFERENCES [dbo].[tblMagazziniMovimentiRighe] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheLotti] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRigheLotti_tblMagazziniMovimentiRighe]
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheLotti]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimentiRigheLotti_tblMagazziniLotti] FOREIGN KEY([IdLotto])
REFERENCES [dbo].[tblMagazziniLotti] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimentiRigheLotti] CHECK CONSTRAINT [FK_tblMagazziniMovimentiRigheLotti_tblMagazziniLotti]
GO
