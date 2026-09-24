SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMagazziniMovimenti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdOperazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
	[Data] [date] NULL,
	[Numero] [int] NULL,
 CONSTRAINT [PK_tblMagazziniMovimenti] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

-- IdSede è scope Azienda. Data = data effettiva del movimento, scelta/editabile
-- dall'utente in testata (coerente con Data su Registrazioni/DDT), obbligatoria per
-- confermare il movimento; usata anche per ordinare l'elenco Movimenti (Id è un GUID
-- troncato via NEWID(), senza alcun significato cronologico). Aggiunta via ALTER TABLE
-- il 2026-09-24, non presente nella creazione originale della tabella. I criteri "per
-- singolo carico" (V/R) restano fuori scope per ora nonostante il campo lo permetterebbe.
-- Numero = progressivo annuale (scope Azienda + anno di Data), proposto automaticamente
-- ma editabile, stesso pattern di massima di Rifiuti/Registrazioni (rinumerazione
-- automatica in caso di collisione esatta, blocco se incoerente con la Data). Assegnato/
-- validato definitivamente solo al momento della conferma (Lock 2->0), non ad ogni
-- salvataggio della testata. Aggiunta via ALTER TABLE il 2026-09-26.
ALTER TABLE [dbo].[tblMagazziniMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimenti_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimenti] CHECK CONSTRAINT [FK_tblMagazziniMovimenti_tblSedi]
GO

ALTER TABLE [dbo].[tblMagazziniMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblMagazziniMovimenti_tblMagazziniOperazioni] FOREIGN KEY([IdOperazione])
REFERENCES [dbo].[tblMagazziniOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblMagazziniMovimenti] CHECK CONSTRAINT [FK_tblMagazziniMovimenti_tblMagazziniOperazioni]
GO
