SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMagazziniDdt](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdMovimento] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdCausale] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Numero] [int] NULL,
	[NumeroFornitore] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[Sezionale] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Data] [date] NULL,
	[IdMittente] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdDestinatario] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdTrasportatore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[DataInizioTrasporto] [smalldatetime] NULL,
	[Peso] [decimal](18, 2) NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblMagazziniDdt] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

-- IdSede (aggiunta 2026-09-24, rinominata da IdSedeInterna il 2026-09-24 per coerenza con
-- le altre tabelle Magazzini che usano IdSede per il concetto di sede operativa/interna):
-- sede operativa interna da cui parte materialmente la merce, scelta una sola volta alla
-- creazione del DDT (immutabile) - governa sia il vincolo "tutte le righe del movimento
-- sulla stessa sede" sia la numerazione DDT (MAX(Numero)+1 per IdSede+Sezionale).
-- IdMittente resta un campo libero della testata (valore stampato sul documento), senza
-- alcuna relazione con questo vincolo.
-- ATTENZIONE: nessun vincolo UNIQUE su IdMovimento ("0..1 DDT per Movimento" va garantito
-- in SP) né sulla combinazione IdSede+Sezionale+Numero (numerazione per sede, da
-- garantire con MAX(Numero)+1 dentro transazione) - verificato sullo schema reale.
ALTER TABLE [dbo].[tblMagazziniDdt]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniDdt_tblSedi_IdSede] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniDdt] CHECK CONSTRAINT [FK_tblMagazziniDdt_tblSedi_IdSede]
GO
ALTER TABLE [dbo].[tblMagazziniDdt]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniDdt_tblMagazziniMovimenti] FOREIGN KEY([IdMovimento])
REFERENCES [dbo].[tblMagazziniMovimenti] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniDdt] CHECK CONSTRAINT [FK_tblMagazziniDdt_tblMagazziniMovimenti]
GO

ALTER TABLE [dbo].[tblMagazziniDdt]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniDdt_tblMagazziniCausali] FOREIGN KEY([IdCausale])
REFERENCES [dbo].[tblMagazziniCausali] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniDdt] CHECK CONSTRAINT [FK_tblMagazziniDdt_tblMagazziniCausali]
GO

ALTER TABLE [dbo].[tblMagazziniDdt]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniDdt_tblSedi_IdMittente] FOREIGN KEY([IdMittente])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniDdt] CHECK CONSTRAINT [FK_tblMagazziniDdt_tblSedi_IdMittente]
GO

ALTER TABLE [dbo].[tblMagazziniDdt]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniDdt_tblSedi_IdDestinatario] FOREIGN KEY([IdDestinatario])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniDdt] CHECK CONSTRAINT [FK_tblMagazziniDdt_tblSedi_IdDestinatario]
GO

ALTER TABLE [dbo].[tblMagazziniDdt]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniDdt_tblSedi_IdTrasportatore] FOREIGN KEY([IdTrasportatore])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniDdt] CHECK CONSTRAINT [FK_tblMagazziniDdt_tblSedi_IdTrasportatore]
GO
