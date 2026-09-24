SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblMagazziniCriteriScarichiLotti](
	[Id] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nome] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[Pos] [tinyint] NULL,
 CONSTRAINT [PK_tblMagazziniCriteriScarichiLotti] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

-- Lookup con 5 righe: F=FIFO per lotto (DataApertura), L=LIFO per lotto (DataApertura),
-- E=FEFO per lotto (DataChiusura), V=FIFO per singolo carico, R=LIFO per singolo carico.
-- IdCriterio NULL sulla riga di movimento = allocazione manuale.
-- Fase 1/2 del modulo Magazzino implementano solo F/L/E; V/R fuori scope (nessun campo
-- data su Movimenti/Righe per ordinare i singoli carichi).
