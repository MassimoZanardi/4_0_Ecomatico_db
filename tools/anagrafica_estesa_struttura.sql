SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Modulo Anagrafica estesa: struttura definitiva di tblClientiFornitori.
--   Id               = Id proprio della scheda cliente/fornitore (uspId_get), non più l'Id del soggetto
--   IdAziendaInterna = azienda interna a cui appartiene la scheda (azienda del contesto all'inserimento)
--   IdSede           = soggetto (azienda esterna) di proprietà della stessa azienda interna
--   Tipo             = C cliente, F fornitore: lo stesso soggetto può avere una scheda per tipo
--   Lock             = 0 attivo, 2 bozza, 4 cancellato
-- La tabella viene ricreata (colonne nell'ordine voluto): lo script si ferma se contiene righe.
-- Rieseguibile.

IF OBJECT_ID('dbo.tblClientiFornitori') IS NOT NULL
	AND COL_LENGTH('dbo.tblClientiFornitori', 'IdAziendaInterna') IS NOT NULL
	AND COL_LENGTH('dbo.tblClientiFornitori', 'Lock') IS NOT NULL
BEGIN
	PRINT 'tblClientiFornitori ha già la struttura definitiva: nessuna modifica';
	SET NOEXEC ON;
END
ELSE IF OBJECT_ID('dbo.tblClientiFornitori') IS NOT NULL
BEGIN
	-- SQL dinamico: dove la tabella non esiste ancora il batch non verrebbe nemmeno compilato
	DECLARE @righe INT = 0;
	EXEC sp_executesql N'SELECT @righe = COUNT(*) FROM dbo.tblClientiFornitori', N'@righe INT OUTPUT', @righe = @righe OUTPUT;
	IF @righe > 0
	BEGIN
		-- NOEXEC e non THROW: un errore fermerebbe solo questo batch e il DROP successivo verrebbe eseguito
		RAISERROR('tblClientiFornitori contiene righe: la tabella non può essere ricreata', 16, 1);
		SET NOEXEC ON;
	END
END
GO

IF OBJECT_ID('dbo.tblClientiFornitori') IS NOT NULL
	DROP TABLE dbo.tblClientiFornitori;
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblClientiFornitori](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdAziendaInterna] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Tipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdModalita] [char](4) COLLATE Latin1_General_CI_AS NULL,
	[IdRata] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdRataInizio] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdBancaCassa] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdAliquotaIva] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdValuta] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[SplitPayment] [bit] NULL,
	[Iban] [varchar](34) COLLATE Latin1_General_CI_AS NULL,
	[RataGiorniInizio] [int] NULL,
	[ImportoMinimoFatturabile] [decimal](18, 2) NULL,
	[RitenutaAcconto] [int] NULL,
	[CodiceDestinatario] [varchar](7) COLLATE Latin1_General_CI_AS NULL,
	[PecDestinatario] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
	[Note] [varchar](1000) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblClientiFornitori] PRIMARY KEY CLUSTERED
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

-- IdAziendaInterna è scope Azienda (la scheda appartiene all'azienda interna, non a una singola sede)
ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblSedi_IdAziendaInterna] FOREIGN KEY([IdAziendaInterna])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblSedi_IdAziendaInterna]
GO

-- IdSede è il soggetto (azienda esterna) a cui si riferisce la scheda
ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblSedi_IdSede] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblSedi_IdSede]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblPagamentiModalita] FOREIGN KEY([IdModalita])
REFERENCES [dbo].[tblPagamentiModalita] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblPagamentiModalita]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblPagamentiRate] FOREIGN KEY([IdRata])
REFERENCES [dbo].[tblPagamentiRate] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblPagamentiRate]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblPagamentiRateInizi] FOREIGN KEY([IdRataInizio])
REFERENCES [dbo].[tblPagamentiRateInizi] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblPagamentiRateInizi]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblBancheCasse] FOREIGN KEY([IdBancaCassa])
REFERENCES [dbo].[tblBancheCasse] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblBancheCasse]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblAliquoteIva] FOREIGN KEY([IdAliquotaIva])
REFERENCES [dbo].[tblAliquoteIva] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblAliquoteIva]
GO

ALTER TABLE [dbo].[tblClientiFornitori]  WITH CHECK ADD  CONSTRAINT [FK_tblClientiFornitori_tblPagamentiValute] FOREIGN KEY([IdValuta])
REFERENCES [dbo].[tblPagamentiValute] ([Id])
GO

ALTER TABLE [dbo].[tblClientiFornitori] CHECK CONSTRAINT [FK_tblClientiFornitori_tblPagamentiValute]
GO

-- Una sola scheda attiva per azienda interna + soggetto + tipo; l'indice serve anche l'elenco per azienda
CREATE UNIQUE NONCLUSTERED INDEX [UX_tblClientiFornitori_IdAziendaInterna_IdSede_Tipo] ON [dbo].[tblClientiFornitori]
(
	[IdAziendaInterna] ASC,
	[IdSede] ASC,
	[Tipo] ASC
)
WHERE ([Lock] = (0))
GO

-- Blocco di cancellazione del soggetto: ricerca delle schede per soggetto
CREATE NONCLUSTERED INDEX [IX_tblClientiFornitori_IdSede] ON [dbo].[tblClientiFornitori]
(
	[IdSede] ASC
)
GO

SET NOEXEC OFF;
GO

SELECT c.column_id, c.name, t.name AS tipo, c.max_length, c.is_nullable
FROM
	sys.columns c
	INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.tblClientiFornitori')
ORDER BY c.column_id;
GO
