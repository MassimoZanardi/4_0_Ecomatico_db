SET NOCOUNT ON;

-- Modulo Anagrafica estesa / Fatturazione: tabelle di base (create solo se mancano, comprese le tabelle di
-- codici delle fatture tblFattureRaggruppamenti, tblFattureStati, tblFattureTipi, tblFattureTipiDocumenti), dati di base e
-- registrazione del modulo ANX. tblClientiFornitori è creata da anagrafica_estesa_struttura.sql.
-- Rieseguibile.
GO

IF OBJECT_ID('dbo.tblPagamentiModalita') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPagamentiModalita](
	[Id] [char](4) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nome] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblPagamentiModalita] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
SET NOEXEC OFF;
GO

IF OBJECT_ID('dbo.tblPagamentiRate') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPagamentiRate](
	[Id] [char](3) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Numero] [int] NULL,
	[PrimaMesi] [int] NULL,
	[Pos] [tinyint] NULL,
 CONSTRAINT [PK_tblPagamentiRate] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
SET NOEXEC OFF;
GO

IF OBJECT_ID('dbo.tblPagamentiRateInizi') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPagamentiRateInizi](
	[Id] [char](2) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblPagamentiRateInizi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
SET NOEXEC OFF;
GO

IF OBJECT_ID('dbo.tblPagamentiValute') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPagamentiValute](
	[Id] [char](3) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Simbolo] [varchar](5) COLLATE Latin1_General_CI_AS NULL,
	[Pos] [tinyint] NULL,
 CONSTRAINT [PK_tblPagamentiValute] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
SET NOEXEC OFF;
GO

IF OBJECT_ID('dbo.tblAliquoteIvaTipi') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblAliquoteIvaTipi](
	[Id] [char](2) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblAliquoteIvaTipi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
SET NOEXEC OFF;
GO

IF OBJECT_ID('dbo.tblAliquoteIvaNatura') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblAliquoteIvaNatura](
	[Id] [varchar](4) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nome] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblAliquoteIvaNatura] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
SET NOEXEC OFF;
GO

IF OBJECT_ID('dbo.tblBancheCasse') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblBancheCasse](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Tipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Iban] [varchar](34) COLLATE Latin1_General_CI_AS NULL,
	[CodiceSia] [varchar](5) COLLATE Latin1_General_CI_AS NULL,
	[Bic] [varchar](11) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblBancheCasse] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[tblBancheCasse]  WITH CHECK ADD  CONSTRAINT [FK_tblBancheCasse_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO
ALTER TABLE [dbo].[tblBancheCasse] CHECK CONSTRAINT [FK_tblBancheCasse_tblSedi]
GO
SET NOEXEC OFF;
GO

IF OBJECT_ID('dbo.tblAliquoteIva') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblAliquoteIva](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdTipo] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdNatura] [varchar](4) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Codice] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[Valore] [decimal](9, 2) NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblAliquoteIva] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[tblAliquoteIva]  WITH CHECK ADD  CONSTRAINT [FK_tblAliquoteIva_tblAliquoteIvaNatura] FOREIGN KEY([IdNatura])
REFERENCES [dbo].[tblAliquoteIvaNatura] ([Id])
GO
ALTER TABLE [dbo].[tblAliquoteIva] CHECK CONSTRAINT [FK_tblAliquoteIva_tblAliquoteIvaNatura]
GO
ALTER TABLE [dbo].[tblAliquoteIva]  WITH CHECK ADD  CONSTRAINT [FK_tblAliquoteIva_tblAliquoteIvaTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblAliquoteIvaTipi] ([Id])
GO
ALTER TABLE [dbo].[tblAliquoteIva] CHECK CONSTRAINT [FK_tblAliquoteIva_tblAliquoteIvaTipi]
GO
ALTER TABLE [dbo].[tblAliquoteIva]  WITH CHECK ADD  CONSTRAINT [FK_tblAliquoteIva_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO
ALTER TABLE [dbo].[tblAliquoteIva] CHECK CONSTRAINT [FK_tblAliquoteIva_tblSedi]
GO
SET NOEXEC OFF;
GO

IF OBJECT_ID('dbo.tblFattureRaggruppamenti') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblFattureRaggruppamenti](
	[Id] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nome] [varchar](100) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblFattureRaggruppamenti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
SET NOEXEC OFF;
GO

IF OBJECT_ID('dbo.tblFattureStati') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblFattureStati](
	[Id] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblFattureStati] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
SET NOEXEC OFF;
GO

IF OBJECT_ID('dbo.tblFattureTipi') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblFattureTipi](
	[Id] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblFattureTipi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
SET NOEXEC OFF;
GO

IF OBJECT_ID('dbo.tblFattureTipiDocumenti') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblFattureTipiDocumenti](
	[Id] [char](4) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdTipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblFattureTipiDocumenti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
SET NOEXEC OFF;
GO

-- Dati di base
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP01') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP01', 'Contanti');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP02') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP02', 'Assegno');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP03') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP03', 'Assegno circolare');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP04') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP04', 'Contanti presso Tesoreria');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP05') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP05', 'Bonifico');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP07') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP07', 'Bollettino bancario');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP08') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP08', 'Carta di credito');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP09') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP09', 'RID');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP10') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP10', 'RID utenze');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP11') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP11', 'RID veloce');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP12') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP12', 'RiBa');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP13') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP13', 'MAV');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP14') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP14', 'Quietanza erario stato');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP15') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP15', 'Giroconto su conti di contabilità speciale');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP16') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP16', 'Domiciliazione bancaria');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP17') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP17', 'Domiciliazione postale');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP18') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP18', 'Bollettino di c/c postale');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = 'MP19') INSERT INTO dbo.tblPagamentiModalita (Id, Nome) VALUES ('MP19', 'SEPA Direct');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '001') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('001', '0 GG (a vista)', 1, 0, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '002') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('002', '30 GG', 1, 1, 2);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '004') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('004', '60 GG', 1, 2, 3);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '008') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('008', '90 GG', 1, 3, 4);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '016') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('016', '120 GG', 1, 4, 5);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '032') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('032', '150 GG', 1, 5, 6);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '064') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('064', '180 GG', 1, 6, 7);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '006') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('006', '30/60 GG', 2, 1, 8);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '014') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('014', '30/60/90 GG', 3, 1, 9);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '030') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('030', '30/60/90/120 GG', 4, 1, 10);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '012') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('012', '60/90 GG', 2, 2, 11);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '028') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('028', '60/90/120 GG', 3, 2, 12);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '060') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('060', '60/90/120/150 GG', 4, 2, 13);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '034') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('034', '90/120 GG', 2, 3, 14);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '066') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('066', '90/120/150 GG', 3, 3, 15);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '130') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('130', '90/120/150/180 GG', 4, 3, 16);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '048') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('048', '120/150 GG', 2, 4, 17);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '112') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('112', '120/150/180 GG', 3, 4, 18);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = '096') INSERT INTO dbo.tblPagamentiRate (Id, Nome, Numero, PrimaMesi, Pos) VALUES ('096', '150/180 GG', 2, 5, 19);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRateInizi WHERE Id = 'DF') INSERT INTO dbo.tblPagamentiRateInizi (Id, Nome) VALUES ('DF', 'D.F.');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRateInizi WHERE Id = 'FM') INSERT INTO dbo.tblPagamentiRateInizi (Id, Nome) VALUES ('FM', 'F.M.');
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiValute WHERE Id = 'EUR') INSERT INTO dbo.tblPagamentiValute (Id, Nome, Simbolo, Pos) VALUES ('EUR', 'Euro', '€', 1);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiValute WHERE Id = 'USD') INSERT INTO dbo.tblPagamentiValute (Id, Nome, Simbolo, Pos) VALUES ('USD', 'Dollaro americano', '$', 2);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiValute WHERE Id = 'CHF') INSERT INTO dbo.tblPagamentiValute (Id, Nome, Simbolo, Pos) VALUES ('CHF', 'Franco svizzero', 'CHF', 3);
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiValute WHERE Id = 'GBP') INSERT INTO dbo.tblPagamentiValute (Id, Nome, Simbolo, Pos) VALUES ('GBP', 'Sterlina britannica', '£', 4);
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaTipi WHERE Id = 'ES') INSERT INTO dbo.tblAliquoteIvaTipi (Id, Nome) VALUES ('ES', 'Esente');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaTipi WHERE Id = 'EX') INSERT INTO dbo.tblAliquoteIvaTipi (Id, Nome) VALUES ('EX', 'Escluso');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaTipi WHERE Id = 'FC') INSERT INTO dbo.tblAliquoteIvaTipi (Id, Nome) VALUES ('FC', 'Fuori campo iva');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaTipi WHERE Id = 'IM') INSERT INTO dbo.tblAliquoteIvaTipi (Id, Nome) VALUES ('IM', 'Imponibile');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaTipi WHERE Id = 'NI') INSERT INTO dbo.tblAliquoteIvaTipi (Id, Nome) VALUES ('NI', 'Non imponibile');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N1') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N1', 'Escluse ex art.15');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N2') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N2', 'Non soggette (non più valido dal 1° Gen 2021)');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N2.1') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N2.1', 'Non soggette ad IVA ai sensi degli artt. Da 7 a 7- septies del DPR 633/72');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N2.2') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N2.2', 'Non soggette – altri casi');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N3') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N3', 'Non imponibili (non più valido dal 1° Gen 2021)');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N3.1') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N3.1', 'Non imponibili – esportazioni');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N3.2') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N3.2', 'Non imponibili – cessioni intracomunitarie');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N3.3') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N3.3', 'Non imponibili – cessioni verso San Marino');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N3.4') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N3.4', 'Non imponibili – operazioni assimilate alle cessioni all’esportazione');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N3.5') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N3.5', 'Non imponibili – a seguito di dichiarazioni d’intento');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N3.6') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N3.6', 'Non imponibili – altre operazioni che non concorrono alla formazione del plafond');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N4') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N4', 'Esenti');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N5') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N5', 'Regime del margine / IVA non esposta in fattura');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N6') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N6', 'Inversione contabile (non più valido dal 1° Gen 2021)');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N6.1') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N6.1', 'Inversione contabile – cessione di rottami e altri materiali di recupero');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N6.2') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N6.2', 'Inversione contabile – cessione di oro e argento puro');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N6.3') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N6.3', 'Inversione contabile – subappalto nel settore edile');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N6.4') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N6.4', 'Inversione contabile – cessione di fabbricati');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N6.5') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N6.5', 'Inversione contabile – cessione di telefoni cellulari');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N6.6') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N6.6', 'Inversione contabile – cessione di prodotti elettronici');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N6.7') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N6.7', 'Inversione contabile – prestazioni comparto edile e settori connessi');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N6.8') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N6.8', 'Inversione contabile – operazioni settore energetico');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N6.9') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N6.9', 'Inversione contabile – altri casi');
IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = 'N7') INSERT INTO dbo.tblAliquoteIvaNatura (Id, Nome) VALUES ('N7', 'IVA assolta in altro stato UE');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureRaggruppamenti WHERE Id = 'C') INSERT INTO dbo.tblFattureRaggruppamenti (Id, Nome) VALUES ('C', 'Cliente (una fattura per ciascun cliente)');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureRaggruppamenti WHERE Id = 'S') INSERT INTO dbo.tblFattureRaggruppamenti (Id, Nome) VALUES ('S', 'Sede (una fattura per ciascuna sede del cliente)');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureRaggruppamenti WHERE Id = 'T') INSERT INTO dbo.tblFattureRaggruppamenti (Id, Nome) VALUES ('T', 'Contratto (una fattura per ciascun contratto del cliente)');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureStati WHERE Id = 'G') INSERT INTO dbo.tblFattureStati (Id, Nome) VALUES ('G', 'Generata');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureStati WHERE Id = 'S') INSERT INTO dbo.tblFattureStati (Id, Nome) VALUES ('S', 'Spedita');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'F') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('F', 'Fattura');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'N') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('N', 'Nota accredito');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipi WHERE Id = 'P') INSERT INTO dbo.tblFattureTipi (Id, Nome) VALUES ('P', 'Pre-fattura');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipiDocumenti WHERE Id = 'TD00') INSERT INTO dbo.tblFattureTipiDocumenti (Id, IdTipo, Nome) VALUES ('TD00', 'P', 'Pre-fattura');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipiDocumenti WHERE Id = 'TD01') INSERT INTO dbo.tblFattureTipiDocumenti (Id, IdTipo, Nome) VALUES ('TD01', 'F', 'Fattura');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipiDocumenti WHERE Id = 'TD02') INSERT INTO dbo.tblFattureTipiDocumenti (Id, IdTipo, Nome) VALUES ('TD02', 'F', 'Fattura acconto/anticipo');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipiDocumenti WHERE Id = 'TD04') INSERT INTO dbo.tblFattureTipiDocumenti (Id, IdTipo, Nome) VALUES ('TD04', 'N', 'Nota accredito');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipiDocumenti WHERE Id = 'TD17') INSERT INTO dbo.tblFattureTipiDocumenti (Id, IdTipo, Nome) VALUES ('TD17', 'F', 'Autofattura per acquisto di servizi');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipiDocumenti WHERE Id = 'TD18') INSERT INTO dbo.tblFattureTipiDocumenti (Id, IdTipo, Nome) VALUES ('TD18', 'F', 'Autofattura per acquisto beni');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipiDocumenti WHERE Id = 'TD19') INSERT INTO dbo.tblFattureTipiDocumenti (Id, IdTipo, Nome) VALUES ('TD19', 'F', 'Autofattura per acquisto beni art. 17');
IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureTipiDocumenti WHERE Id = 'TD24') INSERT INTO dbo.tblFattureTipiDocumenti (Id, IdTipo, Nome) VALUES ('TD24', 'F', 'Fattura differita');
GO

-- Modulo Anagrafica estesa (ANX): funzioni ANC (clienti) e ANF (fornitori), pagine e voci di menu sotto
-- Anagrafica, dopo Soggetti, Persone e Oggetti
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuli WHERE Id = 'ANX')
	INSERT INTO dbo.tblModuli (Id, Nome, Attivo) VALUES ('ANX', 'Anagrafica estesa', 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'ANC')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('ANC', 'Anagrafica clienti', 0, 0, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'ANF')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('ANF', 'Anagrafica fornitori', 0, 0, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'ANX' AND IdFunzione = 'ANC')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('ANX', 'ANC');

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'ANX' AND IdFunzione = 'ANF')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('ANX', 'ANF');

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'ANC')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('ANC', 'ANC', 'Clienti', NULL, NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'ANF')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('ANF', 'ANF', 'Fornitori', NULL, NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AC2')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AC2', 'AC0', NULL, 'ANC', 3);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AC3')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AC3', 'AC0', NULL, 'ANF', 4);
GO
