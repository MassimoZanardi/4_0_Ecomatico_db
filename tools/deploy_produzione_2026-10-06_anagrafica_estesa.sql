/*
Deploy produzione 2026-10-06 - Modulo Anagrafica estesa (clienti e fornitori) e configurazione Fatturazione

Rieseguibile. Da eseguire con sqlcmd -I (QUOTED_IDENTIFIER ON) e -f 65001, oppure da SSMS.

0. Tabelle di base, create solo se mancano: tblPagamentiModalita, tblPagamentiRate, tblPagamentiRateInizi,
   tblPagamentiValute, tblAliquoteIvaTipi, tblAliquoteIvaNatura, tblBancheCasse, tblAliquoteIva e le tabelle di
   codici delle fatture tblFattureRaggruppamenti, tblFattureStati, tblFattureTipi, tblFattureTipiDocumenti; relativi
   dati di base (inseriti solo se mancano); registrazione del modulo ANX "Anagrafica estesa" con le funzioni
   ANC e ANF, le pagine Clienti e Fornitori e le voci di menu sotto Anagrafica.
1. tblClientiFornitori nella struttura definitiva: Id proprio della scheda, IdAziendaInterna, IdSede = soggetto,
   Tipo C/F, Lock; indice unico filtrato su azienda + soggetto + tipo. Se la tabella esiste con la vecchia
   struttura viene ricreata; lo script si ferma se contiene righe. Le colonne Iban di tblClientiFornitori e
   tblBancheCasse passano a 34 caratteri (lunghezza massima di un IBAN) dove sono ancora a 30.
2. Registrazione: ANX richiede ANA; modulo FAT "Fatturazione" con la funzione FTC "Configurazione", le pagine
   Banche e casse e Aliquote IVA e l'area di menu Fatturazione dopo Magazzino (Rentri e Impostazioni scendono
   di una posizione); FAT richiede ANX e ANA. Nessun modulo viene attivato sui domini.
3. Aliquote IVA di sistema (22%, 10%, 4%, Esente con natura N4), con Id fissi registrati anche in tblId.
4. Stored procedure nuove: uspClientiFornitori_* (11), uspBancheCasse_* (7), uspAliquoteIva_* (9). I controlli di
   formato (IBAN, BIC, codice SIA, codice destinatario, PEC) sono nell'applicazione, non nelle SP.
5. Stored procedure modificate: uspSedi_del_SediEsterne (un soggetto con una scheda cliente o fornitore non si
   cancella) e uspSedi_del_SediInterne (un'azienda con clienti o fornitori, banche o casse, aliquote proprie
   non si cancella).

Va deployato insieme all'app: le voci di menu Clienti, Fornitori, Banche e casse e Aliquote IVA aprono pagine
che esistono solo nell'app nuova. Lo script da solo non crea errori sulle pagine esistenti.

Dopo il deploy:
- attivare i moduli Anagrafica estesa e/o Fatturazione sui domini da Impostazioni > Domini;
- eseguire tools\verifica_crlf_accenti.sql: deve dare 0 righe.
*/

PRINT 'Tabelle di base, dati di base e registrazione modulo ANX';
GO
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

PRINT 'Struttura tblClientiFornitori';
GO
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

PRINT 'Colonne Iban a 34 caratteri';
GO
SET NOCOUNT ON;

-- Colonne Iban di tblClientiFornitori e tblBancheCasse da 30 a 34 caratteri: è la lunghezza massima di un
-- IBAN (ISO 13616); con 30 non entravano gli IBAN dei paesi che ne usano di più (es. Malta, 31).
-- Rieseguibile: modifica solo le colonne ancora più corte di 34.

IF COL_LENGTH('dbo.tblClientiFornitori', 'Iban') < 34
	ALTER TABLE dbo.tblClientiFornitori ALTER COLUMN Iban VARCHAR(34) COLLATE Latin1_General_CI_AS NULL;

IF COL_LENGTH('dbo.tblBancheCasse', 'Iban') < 34
	ALTER TABLE dbo.tblBancheCasse ALTER COLUMN Iban VARCHAR(34) COLLATE Latin1_General_CI_AS NULL;

SELECT
	Tabella = OBJECT_NAME(c.object_id),
	Colonna = c.name,
	Lunghezza = c.max_length,
	Collation = c.collation_name
FROM sys.columns c
WHERE
	c.name = 'Iban'
	AND c.object_id IN (OBJECT_ID('dbo.tblClientiFornitori'), OBJECT_ID('dbo.tblBancheCasse'));
GO

PRINT 'Registrazione dipendenze, modulo FAT, pagine e menu';
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Modulo Anagrafica estesa (ANX) e prima configurazione del modulo Fatturazione (FAT).
--   ANX richiede ANA: le voci Clienti e Fornitori stanno nell'area di menu Anagrafica, visibile solo con ANA attivo.
--   FAT "Fatturazione": nuova area di menu dopo Magazzino, con la funzione FTC "Configurazione" che governa
--   le pagine Banche e casse e Aliquote IVA. FAT richiede ANX e ANA (uspDomini_ins_Modulo risolve un solo
--   livello di dipendenze, quindi vanno indicate entrambe).
-- In tblModuliRelazioni Id = modulo richiesto, IdParent = modulo che lo richiede.
-- Nessuna attivazione sui domini: i moduli si attivano da Impostazioni > Domini.
-- Rieseguibile.

BEGIN TRANSACTION;

-- Dipendenza ANX -> ANA
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliRelazioni WHERE Id = 'ANA' AND IdParent = 'ANX')
	INSERT INTO dbo.tblModuliRelazioni (Id, IdParent) VALUES ('ANA', 'ANX');

-- Modulo, area di menu e funzione
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuli WHERE Id = 'FAT')
	INSERT INTO dbo.tblModuli (Id, Nome, Attivo) VALUES ('FAT', 'Fatturazione', 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagineAree WHERE Id = 'FAT')
	INSERT INTO dbo.tblPagineAree (Id, Nome, Icon) VALUES ('FAT', 'Fatturazione', 'fal fa-file-invoice');

IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'FTC')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('FTC', 'Configurazione', 0, 0, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'FAT' AND IdFunzione = 'FTC')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('FAT', 'FTC');

-- Dipendenze FAT -> ANX e FAT -> ANA
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliRelazioni WHERE Id = 'ANX' AND IdParent = 'FAT')
	INSERT INTO dbo.tblModuliRelazioni (Id, IdParent) VALUES ('ANX', 'FAT');

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliRelazioni WHERE Id = 'ANA' AND IdParent = 'FAT')
	INSERT INTO dbo.tblModuliRelazioni (Id, IdParent) VALUES ('ANA', 'FAT');

-- Pagine: Url esplicito perché il nome contiene spazi ("/fatturazione/banche-casse", "/fatturazione/aliquote-iva")
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTB')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTB', 'FTC', 'Banche e casse', 'banche-casse', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'FTI')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note) VALUES ('FTI', 'FTC', 'Aliquote IVA', 'aliquote-iva', NULL);

-- Menu: Fatturazione dopo Magazzino; Rentri e Impostazioni scendono di una posizione
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ0')
BEGIN
	UPDATE dbo.tblMenu SET Pos = 8 WHERE Id = 'AG0' AND Pos = 7;
	UPDATE dbo.tblMenu SET Pos = 9 WHERE Id = 'AZ0' AND Pos = 8;
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ0', NULL, 'FAT', NULL, 7);
END

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ1')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ1', 'AJ0', NULL, 'FTB', 0);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AJ2')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AJ2', 'AJ0', NULL, 'FTI', 1);

COMMIT TRANSACTION;

SELECT m.Id, m.Pos, Area = a.Nome
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagineAree a ON m.IdArea = a.Id
WHERE m.IdParent IS NULL
ORDER BY m.Pos;

SELECT m.Id, m.Pos, p.Nome, p.Url, p.IdFunzione
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
WHERE m.IdParent IN ('AC0', 'AJ0')
ORDER BY m.IdParent, m.Pos;

SELECT Id, IdParent FROM dbo.tblModuliRelazioni ORDER BY IdParent, Id;
GO

PRINT 'Aliquote IVA di sistema';
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Modulo Fatturazione: aliquote IVA di sistema (IdSede NULL = valide per tutti i domini).
-- Gli Id sono fissi e vengono registrati anche in tblId, così uspId_get non li assegna ad altre entità.
-- Nessuna riga in tblIdLog: dato di sistema senza sessione né utente.
-- L'aliquota "Esente" ha natura N4 (Esenti), richiesta dalla fattura elettronica per le aliquote a zero.
-- Rieseguibile.

DECLARE @aliquote TABLE (
	Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	IdTipo CHAR(2) COLLATE DATABASE_DEFAULT NOT NULL,
	IdNatura VARCHAR(4) COLLATE DATABASE_DEFAULT NULL,
	Nome VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
	Codice VARCHAR(20) COLLATE DATABASE_DEFAULT NOT NULL,
	Valore DECIMAL(9, 2) NOT NULL
);

INSERT INTO @aliquote (Id, IdTipo, IdNatura, Nome, Codice, Valore)
VALUES
	('003c400231134eac', 'IM', NULL, 'Iva 22%', '22000', 22.00),
	('54de2336ccc94971', 'ES', 'N4', 'Esente', '00000', 0.00),
	('636d843fca6b488c', 'IM', NULL, 'Iva 4%', '04000', 4.00),
	('dd5fd1d8c64848d0', 'IM', NULL, 'Iva 10%', '10000', 10.00);

-- Un Id già registrato in tblId ma assente da tblAliquoteIva appartiene a un'altra entità
IF EXISTS (
	SELECT 1
	FROM @aliquote a
	INNER JOIN dbo.tblId i ON i.Id = a.Id
	WHERE NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIva ai WHERE ai.Id = a.Id)
)
	THROW 50001, 'Uno o più Id delle aliquote IVA sono già assegnati ad altre entità', 1;

BEGIN TRANSACTION;

INSERT INTO dbo.tblId (Id)
SELECT a.Id
FROM @aliquote a
WHERE NOT EXISTS (SELECT 1 FROM dbo.tblId i WHERE i.Id = a.Id);

INSERT INTO dbo.tblAliquoteIva (Id, IdSede, IdTipo, IdNatura, Nome, Codice, Valore, Lock)
SELECT a.Id, NULL, a.IdTipo, a.IdNatura, a.Nome, a.Codice, a.Valore, 0
FROM @aliquote a
WHERE NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIva ai WHERE ai.Id = a.Id);

COMMIT TRANSACTION;

SELECT ai.Id, ai.IdSede, ai.IdTipo, ai.IdNatura, ai.Nome, ai.Codice, ai.Valore, ai.Lock,
	CASE WHEN i.Id IS NULL THEN 0 ELSE 1 END AS InTblId
FROM dbo.tblAliquoteIva ai
LEFT JOIN dbo.tblId i ON i.Id = ai.Id
ORDER BY ai.Valore DESC;
GO

PRINT 'uspClientiFornitori_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_del
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità): scope azienda interna corrente della sessione
		DECLARE @tipo CHAR(1);
		DECLARE @lock INT;
		SELECT
			@tipo = c.Tipo,
			@lock = c.Lock
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @tipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: ANC per i clienti, ANF per i fornitori
		DECLARE @idFunzione CHAR(3) = IIF(@tipo = 'C', 'ANC', 'ANF');
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- ── CASO 1: scheda attiva (Lock = 0) → soft delete ───────────────────
		IF @lock = 0
		BEGIN
			BEGIN TRANSACTION;
				UPDATE dbo.tblClientiFornitori
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = IIF(@tipo = 'C', 'Cliente non trovato o già eliminato', 'Fornitore non trovato o già eliminato');
					GOTO BRANCH_END;
				END

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END

		-- ── CASO 2: scheda in bozza (Lock = 2) → hard delete ─────────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblClientiFornitori
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellata (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La scheda è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
			GOTO BRANCH_END;
		END

		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspClientiFornitori_del_Undo';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_del_Undo
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Dopo la cancellazione lo stesso soggetto può essere stato reinserito: il ripristino creerebbe
		-- due schede attive per soggetto e tipo nella stessa azienda
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblClientiFornitori i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
				INNER JOIN dbo.tblClientiFornitori a ON i.IdAziendaInterna = a.IdAziendaInterna
													 AND i.IdSede = a.IdSede
													 AND i.Tipo = a.Tipo
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4
				AND a.Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ripristino non possibile: il soggetto è già stato reinserito';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblClientiFornitori i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4;

			DELETE i
			FROM dbo.tblIdLog i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;
			DECLARE @ripristinate INT = @@ROWCOUNT;

		COMMIT TRANSACTION;

		SET @returnMessage = CASE @ripristinate
			WHEN 0 THEN 'Nessuna entità da ripristinare'
			WHEN 1 THEN 'Entità ripristinata'
			ELSE FORMAT(@ripristinate, 'N0', 'it-IT') + ' entità ripristinate'
		END;

		SELECT @returnMessage AS ReturnMessage;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspClientiFornitori_get';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_get
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @tipo CHAR(1);
		SELECT @tipo = c.Tipo
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @tipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: ANC per i clienti, ANF per i fornitori
		DECLARE @idFunzione CHAR(3) = IIF(@tipo = 'C', 'ANC', 'ANF');
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE Id = @Id AND Lock <= 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'C', 'Cliente non trovato', 'Fornitore non trovato');
			GOTO BRANCH_END;
		END

		-- I dati anagrafici del soggetto sono in sola lettura: si modificano in Anagrafica > Soggetti
		SELECT
			c.Id,
			c.IdAziendaInterna,
			c.IdSede,
			c.Tipo,
			c.IdModalita,
			c.IdRata,
			c.IdRataInizio,
			c.IdBancaCassa,
			c.IdAliquotaIva,
			c.IdValuta,
			SplitPayment = ISNULL(c.SplitPayment, 0),
			c.Iban,
			RataGiorniInizio = ISNULL(c.RataGiorniInizio, 0),
			ImportoMinimoFatturabile = ISNULL(c.ImportoMinimoFatturabile, 0),
			RitenutaAcconto = ISNULL(c.RitenutaAcconto, 0),
			c.CodiceDestinatario,
			c.PecDestinatario,
			c.Note,
			c.Lock,
			SedeNomeCompleto = s.NomeCompleto,
			SedeIndirizzoCompleto = s.IndirizzoCompleto,
			SedeCodiceFiscale = s.CodiceFiscale,
			SedePartitaIva = s.PartitaIva,
			SedeDisabilitata = ISNULL(s.Disabilitata, 0)
		FROM
			dbo.tblClientiFornitori c
			LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE
			c.Id = @Id
			AND c.Lock <= 2;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspClientiFornitori_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Indirizzo VARCHAR(50) = NULL,
	@CodiceFiscale VARCHAR(50) = NULL,
	@Note VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Indirizzo = dbo.ufnStringhe_get_SenzaSpazi(@Indirizzo, 0, 1);
		SET @CodiceFiscale = dbo.ufnStringhe_get_SenzaSpazi(@CodiceFiscale, 0, 1);
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'F')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (cliente) o F (fornitore)';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione: ANC per i clienti, ANF per i fornitori
		DECLARE @idFunzione CHAR(3) = IIF(@Tipo = 'C', 'ANC', 'ANF');
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga.
		-- Codice fiscale e partita IVA si cercano con lo stesso filtro
		SELECT
			c.Id,
			StatoValore = CASE WHEN s.Disabilitata = 1 THEN 2 ELSE 0 END,
			StatoDescrizione = CASE WHEN s.Disabilitata = 1 THEN 'Anagrafica del soggetto disabilitata' ELSE 'OK' END,
			s.NomeCompleto,
			s.IndirizzoCompleto,
			s.CodiceFiscale,
			s.PartitaIva,
			ModalitaNome = m.Nome,
			RataNome = r.Nome,
			c.Note,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			LEFT JOIN dbo.tblPagamentiModalita m ON c.IdModalita = m.Id
			LEFT JOIN dbo.tblPagamentiRate r ON c.IdRata = r.Id
		WHERE
			e.Id = @IdSessione
			AND c.Tipo = @Tipo
			AND c.Lock = 0
			AND (@Nome IS NULL OR s.NomeCompleto LIKE '%' + @Nome + '%')
			AND (@Indirizzo IS NULL OR s.IndirizzoCompleto LIKE '%' + @Indirizzo + '%')
			AND
				(
				@CodiceFiscale IS NULL
				OR s.CodiceFiscale LIKE '%' + @CodiceFiscale + '%'
				OR s.PartitaIva LIKE '%' + @CodiceFiscale + '%'
				)
			AND (@Note IS NULL OR c.Note LIKE '%' + @Note + '%')
		ORDER BY s.NomeCompleto
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspClientiFornitori_get_Modalita_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_get_Modalita_SelectList
	@IdSelected CHAR(4) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST('0000' AS CHAR(4)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected IS NULL OR @IdSelected = '0000', 1, 0) AS BIT),
				Pos = 0,
				Ordine = CAST(NULL AS VARCHAR(100))

			UNION ALL

			SELECT
				Id,
				[Text] = CAST(Nome AS VARCHAR(100)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1,
				Ordine = CAST(Id AS VARCHAR(100))
			FROM dbo.tblPagamentiModalita
		) t
		ORDER BY Pos, Ordine;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspClientiFornitori_get_RateInizi_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_get_RateInizi_SelectList
	@IdSelected CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		SELECT
			Id,
			[Text] = Nome,
			Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblPagamentiRateInizi
		ORDER BY Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspClientiFornitori_get_Rate_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_get_Rate_SelectList
	@IdSelected CHAR(3) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST('000' AS CHAR(3)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected IS NULL OR @IdSelected = '000', 1, 0) AS BIT),
				Pos = 0,
				Ordine = CAST(NULL AS VARCHAR(100))

			UNION ALL

			SELECT
				Id,
				[Text] = CAST(Nome AS VARCHAR(100)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1,
				Ordine = RIGHT('000' + CAST(Pos AS VARCHAR(3)), 3)
			FROM dbo.tblPagamentiRate
		) t
		ORDER BY Pos, Ordine;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspClientiFornitori_get_Soggetti_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_get_Soggetti_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: basta la lettura su clienti (ANC) o fornitori (ANF)
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'ANF',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		-- Solo i soggetti di cui l'azienda del contesto è proprietaria: quelli visti tramite un'area
		-- appartengono a un'altra azienda e non possono diventare clienti o fornitori
		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(500)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- soggetto selezionato: sempre presente, anche se disabilitato o fuori da @Search

			SELECT
				s.Id,
				[Text] = CAST(s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') AS VARCHAR(500)),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM
				dbo.tblSedi s
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				e.Id = @IdSessione
				AND s.Id = @IdSelected
				AND s.InternaEsterna = 'E'
				AND s.IdParent IS NULL
				AND s.Lock = 0

			UNION ALL -- altri soggetti attivi dell'azienda, filtrabili per @Search

			SELECT
				s.Id,
				[Text] = CAST(s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') AS VARCHAR(500)),
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblSedi s
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
			WHERE
				e.Id = @IdSessione
				AND s.InternaEsterna = 'E'
				AND s.IdParent IS NULL
				AND s.Lock = 0
				AND ISNULL(s.Disabilitata, 0) = 0
				AND s.Id <> @IdSelected
				AND
					(
					@Search IS NULL
					OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%'
					OR s.PartitaIva LIKE '%' + @Search + '%'
					OR s.CodiceFiscale LIKE '%' + @Search + '%'
					)
		)
		SELECT TOP 50 Id, [Text], Selected
		FROM cte
		ORDER BY Pos, [Text]
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspClientiFornitori_get_Valute_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_get_Valute_SelectList
	@IdSelected CHAR(3) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		SELECT
			Id,
			[Text] = Nome,
			Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblPagamentiValute
		ORDER BY Pos;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspClientiFornitori_ins';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_ins
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'F')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (cliente) o F (fornitore)';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: ANC per i clienti, ANF per i fornitori
		DECLARE @idFunzione CHAR(3) = IIF(@Tipo = 'C', 'ANC', 'ANF');
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La scheda appartiene all'azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		-- Bozza: il soggetto si sceglie nella scheda. Valori predefiniti: valuta euro; decorrenza delle rate dalla data fattura (DF); giorno del mese, importo minimo fatturabile e ritenuta d'acconto a 0
		BEGIN TRANSACTION;
			INSERT dbo.tblClientiFornitori (Id, IdAziendaInterna, Tipo, IdValuta, IdRataInizio, SplitPayment, RataGiorniInizio, ImportoMinimoFatturabile, RitenutaAcconto, Lock)
			VALUES (@returnId, @idAzienda, @Tipo, 'EUR', 'DF', 0, 0, 0, 0, 2);
		COMMIT TRANSACTION;

		SELECT Id = @returnId;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspClientiFornitori_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspClientiFornitori_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@IdModalita CHAR(4) = NULL,
	@IdRata CHAR(3) = NULL,
	@IdRataInizio CHAR(2) = NULL,
	@IdBancaCassa CHAR(16) = NULL,
	@IdAliquotaIva CHAR(16) = NULL,
	@IdValuta CHAR(3) = NULL,
	@SplitPayment BIT = 0,
	@Iban VARCHAR(50) = NULL,
	@RataGiorniInizio INT = NULL,
	@ImportoMinimoFatturabile DECIMAL(18, 2) = NULL,
	@RitenutaAcconto INT = NULL,
	@CodiceDestinatario VARCHAR(20) = NULL,
	@PecDestinatario VARCHAR(100) = NULL,
	@Note VARCHAR(1000) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Le select propongono come prima voce "(Selezionare)" con Id a zeri: vale come non indicato
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSede = NULLIF(NULLIF(LTRIM(RTRIM(@IdSede)), ''), REPLICATE('0', 16));
		SET @IdModalita = NULLIF(NULLIF(LTRIM(RTRIM(@IdModalita)), ''), REPLICATE('0', 4));
		SET @IdRata = NULLIF(NULLIF(LTRIM(RTRIM(@IdRata)), ''), REPLICATE('0', 3));
		SET @IdRataInizio = NULLIF(NULLIF(LTRIM(RTRIM(@IdRataInizio)), ''), REPLICATE('0', 2));
		SET @IdBancaCassa = NULLIF(NULLIF(LTRIM(RTRIM(@IdBancaCassa)), ''), REPLICATE('0', 16));
		SET @IdAliquotaIva = NULLIF(NULLIF(LTRIM(RTRIM(@IdAliquotaIva)), ''), REPLICATE('0', 16));
		SET @IdValuta = NULLIF(NULLIF(LTRIM(RTRIM(@IdValuta)), ''), REPLICATE('0', 3));
		SET @SplitPayment = ISNULL(@SplitPayment, 0);
		-- Giorno del mese, importo minimo fatturabile e ritenuta d'acconto non indicati valgono 0
		SET @RataGiorniInizio = ISNULL(@RataGiorniInizio, 0);
		SET @ImportoMinimoFatturabile = ISNULL(@ImportoMinimoFatturabile, 0);
		SET @RitenutaAcconto = ISNULL(@RitenutaAcconto, 0);
		-- IBAN e codice destinatario: maiuscolo e senza spazi interni
		SET @Iban = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@Iban)), ' ', '')), '');
		SET @CodiceDestinatario = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@CodiceDestinatario)), ' ', '')), '');
		SET @PecDestinatario = NULLIF(LOWER(LTRIM(RTRIM(@PecDestinatario))), '');
		SET @Note = dbo.ufnStringhe_get_SenzaSpazi(@Note, 0, 1);

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @tipo CHAR(1);
		DECLARE @idSedeAttuale CHAR(16);
		SELECT
			@idAzienda = c.IdAziendaInterna,
			@tipo = c.Tipo,
			@idSedeAttuale = c.IdSede
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: ANC per i clienti, ANF per i fornitori
		DECLARE @idFunzione CHAR(3) = IIF(@tipo = 'C', 'ANC', 'ANF');
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = @idFunzione,
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Soggetto: obbligatorio e di proprietà dell'azienda della scheda. Un soggetto visto tramite
		-- un'area appartiene a un'altra azienda e non può diventare cliente o fornitore
		IF @IdSede IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il soggetto';
			GOTO BRANCH_END;
		END

		DECLARE @sedeDisabilitata BIT;
		DECLARE @sedeTrovata BIT = 0;
		SELECT
			@sedeTrovata = 1,
			@sedeDisabilitata = ISNULL(s.Disabilitata, 0)
		FROM dbo.tblSedi s
		WHERE
			s.Id = @IdSede
			AND s.InternaEsterna = 'E'
			AND s.IdParent IS NULL
			AND s.Lock = 0
			AND s.IdAziendaInterna = @idAzienda;

		IF @sedeTrovata = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il soggetto non appartiene all''azienda';
			GOTO BRANCH_END;
		END
		-- Un soggetto disabilitato resta sulla scheda che lo ha già, ma non si sceglie su un'altra
		IF @sedeDisabilitata = 1 AND (@idSedeAttuale IS NULL OR @idSedeAttuale <> @IdSede)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il soggetto è disabilitato';
			GOTO BRANCH_END;
		END

		-- Una sola scheda attiva per soggetto e tipo nella stessa azienda
		IF EXISTS (
			SELECT 1
			FROM dbo.tblClientiFornitori
			WHERE
				Id <> @Id
				AND IdAziendaInterna = @idAzienda
				AND IdSede = @IdSede
				AND Tipo = @tipo
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'C', 'Il soggetto è già presente tra i clienti', 'Il soggetto è già presente tra i fornitori');
			GOTO BRANCH_END;
		END

		-- Condizioni di pagamento: la modalità è obbligatoria
		IF @IdModalita IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la modalità di pagamento';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiModalita WHERE Id = @IdModalita)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La modalità di pagamento indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @IdRata IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRate WHERE Id = @IdRata)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La rateizzazione indicata non esiste';
			GOTO BRANCH_END;
		END
		-- Decorrenza delle rate (campo "Da"): obbligatoria
		IF @IdRataInizio IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la decorrenza delle rate (campo Da)';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiRateInizi WHERE Id = @IdRataInizio)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La decorrenza delle rate indicata non esiste';
			GOTO BRANCH_END;
		END
		IF @IdValuta IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la valuta';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblPagamentiValute WHERE Id = @IdValuta)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La valuta indicata non esiste';
			GOTO BRANCH_END;
		END
		-- Giorno del mese per le scadenze posticipate rispetto alla fine del mese (0 o vuoto = nessuno)
		IF @RataGiorniInizio < 0 OR @RataGiorniInizio > 31
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il giorno del mese deve essere compreso tra 0 e 31';
			GOTO BRANCH_END;
		END
		IF @ImportoMinimoFatturabile < 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo minimo fatturabile non può essere negativo';
			GOTO BRANCH_END;
		END
		IF @RitenutaAcconto < 0 OR @RitenutaAcconto > 100
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La ritenuta d''acconto deve essere compresa tra 0 e 100';
			GOTO BRANCH_END;
		END

		-- Banca/cassa: solo dell'azienda della scheda
		IF @IdBancaCassa IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblBancheCasse
			WHERE
				Id = @IdBancaCassa
				AND IdSede = @idAzienda
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La banca o cassa indicata non esiste';
			GOTO BRANCH_END;
		END

		-- Aliquota IVA: di sistema (IdSede NULL) o dell'azienda della scheda
		IF @IdAliquotaIva IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblAliquoteIva
			WHERE
				Id = @IdAliquotaIva
				AND (IdSede IS NULL OR IdSede = @idAzienda)
				AND Lock = 0
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''aliquota IVA indicata non esiste';
			GOTO BRANCH_END;
		END

		-- Il formato di IBAN, codice destinatario e PEC è controllato dall'applicazione (Strings.cs): qui si
		-- protegge solo la lunghezza delle colonne
		IF LEN(@Iban) > 34
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''IBAN non può superare i 34 caratteri';
			GOTO BRANCH_END;
		END
		-- RiBa (MP12) su un cliente: serve l'IBAN della sua banca d'appoggio
		IF @tipo = 'C' AND @IdModalita = 'MP12' AND @Iban IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Con il pagamento RiBa indicare l''IBAN del cliente';
			GOTO BRANCH_END;
		END

		IF LEN(@CodiceDestinatario) > 7
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice destinatario non può superare i 7 caratteri';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblClientiFornitori
			SET
				Lock = 0,
				IdSede = @IdSede,
				IdModalita = @IdModalita,
				IdRata = @IdRata,
				IdRataInizio = @IdRataInizio,
				IdBancaCassa = @IdBancaCassa,
				IdAliquotaIva = @IdAliquotaIva,
				IdValuta = @IdValuta,
				SplitPayment = @SplitPayment,
				Iban = @Iban,
				RataGiorniInizio = @RataGiorniInizio,
				ImportoMinimoFatturabile = @ImportoMinimoFatturabile,
				RitenutaAcconto = @RitenutaAcconto,
				CodiceDestinatario = @CodiceDestinatario,
				PecDestinatario = @PecDestinatario,
				Note = @Note
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = IIF(@tipo = 'C', 'Cliente non trovato o già eliminato', 'Fornitore non trovato o già eliminato');
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspBancheCasse_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_del
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistita o già cancellata viene trattata come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblBancheCasse WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblBancheCasse c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock FROM dbo.tblBancheCasse WHERE Id = @Id);

		-- ── CASO 1: banca o cassa attiva (Lock = 0) → soft delete ────────────
		IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE IdBancaCassa = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una banca o cassa associata a clienti o fornitori non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblBancheCasse
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Banca o cassa non trovata o già eliminata';
					GOTO BRANCH_END;
				END

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END

		-- ── CASO 2: banca o cassa in bozza (Lock = 2) → hard delete ──────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblBancheCasse
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellata (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La banca o cassa è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
			GOTO BRANCH_END;
		END

		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspBancheCasse_del_Undo';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_del_Undo
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblBancheCasse i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4;

			DELETE i
			FROM dbo.tblIdLog i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;
			DECLARE @ripristinate INT = @@ROWCOUNT;

		COMMIT TRANSACTION;

		SET @returnMessage = CASE @ripristinate
			WHEN 0 THEN 'Nessuna entità da ripristinare'
			WHEN 1 THEN 'Entità ripristinata'
			ELSE FORMAT(@ripristinate, 'N0', 'it-IT') + ' entità ripristinate'
		END;

		SELECT @returnMessage AS ReturnMessage;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspBancheCasse_get';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_get
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblBancheCasse c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblBancheCasse WHERE Id = @Id AND Lock <= 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Banca o cassa non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			b.Id,
			b.IdSede,
			b.Tipo,
			b.Nome,
			b.Iban,
			b.CodiceSia,
			b.Bic,
			b.Lock
		FROM dbo.tblBancheCasse b
		WHERE
			b.Id = @Id
			AND b.Lock <= 2;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspBancheCasse_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione (tblSessioni.IdAzienda); senza azienda nessuna riga
		SELECT
			b.Id,
			StatoValore = 0,
			StatoDescrizione = 'OK',
			b.Tipo,
			TipoNome = CASE b.Tipo WHEN 'B' THEN 'Banca' WHEN 'C' THEN 'Cassa' END,
			b.Nome,
			b.Iban,
			b.Bic,
			b.CodiceSia,
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblBancheCasse b
			INNER JOIN dbo.tblSessioni e ON b.IdSede = e.IdAzienda
		WHERE
			e.Id = @IdSessione
			AND b.Lock = 0
			AND (@Search IS NULL OR b.Nome LIKE '%' + @Search + '%' OR b.Iban LIKE '%' + REPLACE(@Search, ' ', '') + '%')
		ORDER BY b.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspBancheCasse_get_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_get_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: la select serve alla scheda cliente (ANC) e fornitore (ANF)
		-- oltre che alla configurazione (FTC); basta la lettura su una delle tre
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'ANF',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'FTC',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		-- Scope: banche e casse dell'azienda interna corrente della sessione
		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				b.Id,
				[Text] = CAST(b.Nome AS VARCHAR(100)),
				Selected = CAST(IIF(b.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM
				dbo.tblBancheCasse b
				INNER JOIN dbo.tblSessioni e ON b.IdSede = e.IdAzienda
			WHERE
				e.Id = @IdSessione
				AND b.Lock = 0
		) t
		ORDER BY Pos, [Text];

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspBancheCasse_ins';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_ins
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La banca o cassa appartiene all'azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		-- Bozza: tipo predefinito banca
		BEGIN TRANSACTION;
			INSERT dbo.tblBancheCasse (Id, IdSede, Tipo, Lock)
			VALUES (@returnId, @idAzienda, 'B', 2);
		COMMIT TRANSACTION;

		SELECT Id = @returnId;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspBancheCasse_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspBancheCasse_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Iban VARCHAR(50) = NULL,
	@CodiceSia VARCHAR(20) = NULL,
	@Bic VARCHAR(20) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		-- IBAN, codice SIA e BIC: maiuscolo e senza spazi interni
		SET @Iban = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@Iban)), ' ', '')), '');
		SET @CodiceSia = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@CodiceSia)), ' ', '')), '');
		SET @Bic = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@Bic)), ' ', '')), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('B', 'C')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il tipo (banca o cassa)';
			GOTO BRANCH_END;
		END
		IF @Nome IS NULL OR LEN(@Nome) < 3
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@Tipo = 'B', 'Indicare il nome della banca (almeno 3 caratteri)', 'Indicare il nome della cassa (almeno 3 caratteri)');
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = c.IdSede
		FROM
			dbo.tblBancheCasse c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Una cassa non ha coordinate bancarie
		IF @Tipo = 'C'
		BEGIN
			SET @Iban = NULL;
			SET @CodiceSia = NULL;
			SET @Bic = NULL;
		END

		-- Banca: IBAN obbligatorio. Il formato di IBAN, BIC e codice SIA è controllato dall'applicazione
		-- (Strings.cs): qui si protegge solo la lunghezza delle colonne
		IF @Tipo = 'B' AND @Iban IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il codice IBAN';
			GOTO BRANCH_END;
		END
		IF LEN(@Iban) > 34
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''IBAN non può superare i 34 caratteri';
			GOTO BRANCH_END;
		END
		IF LEN(@Bic) > 11
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice BIC non può superare gli 11 caratteri';
			GOTO BRANCH_END;
		END
		IF LEN(@CodiceSia) > 5
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice SIA non può superare i 5 caratteri';
			GOTO BRANCH_END;
		END

		-- Controlla che non esista un'altra banca o cassa attiva con lo stesso nome nella stessa azienda
		IF EXISTS (
			SELECT 1
			FROM dbo.tblBancheCasse
			WHERE
				Id <> @Id
				AND IdSede = @idAzienda
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra banca o cassa con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblBancheCasse
			SET
				Lock = 0,
				Tipo = @Tipo,
				Nome = @Nome,
				Iban = @Iban,
				CodiceSia = @CodiceSia,
				Bic = @Bic
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Banca o cassa non trovata o già eliminata';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspAliquoteIva_del';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_del
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistita o già cancellata viene trattata come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIva WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Le aliquote di sistema (IdSede NULL) non si cancellano mai, da nessun utente
		IF EXISTS (SELECT 1 FROM dbo.tblAliquoteIva WHERE Id = @Id AND IdSede IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''aliquota di sistema non può essere cancellata';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblAliquoteIva c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock FROM dbo.tblAliquoteIva WHERE Id = @Id);

		-- ── CASO 1: aliquota attiva (Lock = 0) → soft delete ──────────────────
		IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE IdAliquotaIva = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''aliquota associata a clienti o fornitori non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblAliquoteIva
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Aliquota non trovata o già eliminata';
					GOTO BRANCH_END;
				END

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END

		-- ── CASO 2: aliquota in bozza (Lock = 2) → hard delete ────────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblAliquoteIva
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellata (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''aliquota è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
			GOTO BRANCH_END;
		END

		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspAliquoteIva_del_Undo';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_del_Undo
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblAliquoteIva i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4;

			DELETE i
			FROM dbo.tblIdLog i
			INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
			WHERE
				c.IdSessione = @IdSessione
				AND i.Operazione = 'D';

			DELETE dbo.tblIdCancellati
			WHERE IdSessione = @IdSessione;
			DECLARE @ripristinate INT = @@ROWCOUNT;

		COMMIT TRANSACTION;

		SET @returnMessage = CASE @ripristinate
			WHEN 0 THEN 'Nessuna entità da ripristinare'
			WHEN 1 THEN 'Entità ripristinata'
			ELSE FORMAT(@ripristinate, 'N0', 'it-IT') + ' entità ripristinate'
		END;

		SELECT @returnMessage AS ReturnMessage;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspAliquoteIva_get';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_get
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: aliquota di sistema (IdSede NULL, visibile a tutti in sola
		-- lettura) oppure dell'azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblAliquoteIva c
				INNER JOIN dbo.tblSessioni e ON c.IdSede IS NULL OR c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIva WHERE Id = @Id AND Lock <= 2)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Aliquota non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			a.Id,
			a.IdSede,
			a.IdTipo,
			a.IdNatura,
			a.Nome,
			a.Codice,
			a.Valore,
			a.Lock,
			IsSistema = CAST(IIF(a.IdSede IS NULL, 1, 0) AS BIT)
		FROM dbo.tblAliquoteIva a
		WHERE
			a.Id = @Id
			AND a.Lock <= 2;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspAliquoteIva_get_List';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		SET @PageNumber = ISNULL(@PageNumber, 1);
		SET @RowsPerPage = ISNULL(@RowsPerPage, 50);
		IF @PageNumber < 1 SET @PageNumber = 1;
		IF @RowsPerPage < 1 SET @RowsPerPage = 50;

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Aliquote di sistema (IdSede NULL, sola lettura) più quelle dell'azienda interna corrente della
		-- sessione, dalla più alta alla più bassa; senza azienda nel contesto nessuna riga
		SELECT
			a.Id,
			StatoValore = 0,
			StatoDescrizione = 'OK',
			a.Nome,
			a.Codice,
			a.Valore,
			TipoNome = t.Nome,
			a.IdNatura,
			NaturaNome = n.Nome,
			IsSistema = CAST(IIF(a.IdSede IS NULL, 1, 0) AS BIT),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.tblAliquoteIva a
			INNER JOIN dbo.tblSessioni e ON a.IdSede IS NULL OR a.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblAliquoteIvaTipi t ON a.IdTipo = t.Id
			LEFT JOIN dbo.tblAliquoteIvaNatura n ON a.IdNatura = n.Id
		WHERE
			e.Id = @IdSessione
			AND e.IdAzienda IS NOT NULL
			AND a.Lock = 0
			AND (@Search IS NULL OR a.Nome LIKE '%' + @Search + '%' OR a.Codice LIKE '%' + @Search + '%')
		ORDER BY a.Valore DESC, a.Nome
		OFFSET (@PageNumber - 1) * @RowsPerPage ROWS
		FETCH NEXT @RowsPerPage ROWS ONLY
		OPTION (RECOMPILE);

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH

	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspAliquoteIva_get_Natura_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_get_Natura_SelectList
	@IdSelected VARCHAR(4) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		-- Codici natura della fattura elettronica (N1...N7), preceduti dal codice
		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST('0000' AS VARCHAR(4)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(200)),
				Selected = CAST(IIF(@IdSelected IS NULL OR @IdSelected = '0000', 1, 0) AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				Id,
				[Text] = CAST(Id + ' - ' + Nome AS VARCHAR(200)),
				Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM dbo.tblAliquoteIvaNatura
		) t
		ORDER BY Pos, Id;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspAliquoteIva_get_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_get_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: la select serve alla scheda cliente (ANC) e fornitore (ANF)
		-- oltre che alla configurazione (FTC); basta la lettura su una delle tre
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'ANF',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'FTC',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Aliquote di sistema (IdSede NULL) più quelle dell'azienda interna corrente della sessione,
		-- dalla più alta alla più bassa
		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0,
				Valore = CAST(NULL AS DECIMAL(9, 2))

			UNION ALL

			SELECT
				a.Id,
				[Text] = CAST(a.Nome AS VARCHAR(100)),
				Selected = CAST(IIF(a.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1,
				a.Valore
			FROM dbo.tblAliquoteIva a
			WHERE
				(a.IdSede IS NULL OR a.IdSede = @idAzienda)
				AND a.Lock = 0
		) t
		ORDER BY Pos, Valore DESC, [Text];

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspAliquoteIva_get_Tipi_SelectList';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_get_Tipi_SelectList
	@IdSelected CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		-- Imponibile per primo, poi gli altri in ordine alfabetico
		SELECT
			Id,
			[Text] = Nome,
			Selected = CAST(IIF(Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblAliquoteIvaTipi
		ORDER BY IIF(Id = 'IM', 0, 1), Nome;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspAliquoteIva_ins';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_ins
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Una nuova aliquota appartiene sempre all'azienda interna corrente della sessione:
		-- le aliquote di sistema (IdSede NULL) non si creano dall'applicazione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare l''azienda';
			GOTO BRANCH_END;
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		-- Bozza: tipo predefinito imponibile
		BEGIN TRANSACTION;
			INSERT dbo.tblAliquoteIva (Id, IdSede, IdTipo, Lock)
			VALUES (@returnId, @idAzienda, 'IM', 2);
		COMMIT TRANSACTION;

		SELECT Id = @returnId;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END

END;
GO

PRINT 'uspAliquoteIva_upd';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspAliquoteIva_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdTipo CHAR(2) = NULL,
	@IdNatura VARCHAR(4) = NULL,
	@Nome VARCHAR(50) = NULL,
	@Codice VARCHAR(20) = NULL,
	@Valore DECIMAL(9, 2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		-- Le select propongono come prima voce "(Selezionare)" con Id a zeri: vale come non indicato
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdTipo = UPPER(NULLIF(NULLIF(LTRIM(RTRIM(@IdTipo)), ''), REPLICATE('0', 2)));
		SET @IdNatura = UPPER(NULLIF(NULLIF(LTRIM(RTRIM(@IdNatura)), ''), REPLICATE('0', 4)));
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @Codice = dbo.ufnStringhe_get_SenzaSpazi(@Codice, 0, 1);

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Le aliquote di sistema (IdSede NULL) non si modificano mai, da nessun utente
		IF EXISTS (SELECT 1 FROM dbo.tblAliquoteIva WHERE Id = @Id AND IdSede IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''aliquota di sistema non può essere modificata';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = c.IdSede
		FROM
			dbo.tblAliquoteIva c
			INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
		WHERE
			c.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @Nome IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il nome';
			GOTO BRANCH_END;
		END
		IF @IdTipo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il tipo';
			GOTO BRANCH_END;
		END
		IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaTipi WHERE Id = @IdTipo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il tipo indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Regola della fattura elettronica: la natura si indica solo con aliquota zero, e allora è obbligatoria.
		--   Imponibile (IM): valore maggiore di zero, nessuna natura
		--   Altri tipi (esente, escluso, fuori campo, non imponibile): valore zero, natura obbligatoria
		IF @IdTipo = 'IM'
		BEGIN
			IF @Valore IS NULL OR @Valore <= 0 OR @Valore > 100
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Per un''aliquota imponibile indicare un valore maggiore di 0 e non superiore a 100';
				GOTO BRANCH_END;
			END
			SET @IdNatura = NULL;
		END
		ELSE
		BEGIN
			IF ISNULL(@Valore, 0) <> 0
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Solo un''aliquota imponibile può avere un valore diverso da 0';
				GOTO BRANCH_END;
			END
			SET @Valore = 0;

			IF @IdNatura IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Selezionare la natura';
				GOTO BRANCH_END;
			END
			IF NOT EXISTS (SELECT 1 FROM dbo.tblAliquoteIvaNatura WHERE Id = @IdNatura)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La natura indicata non esiste';
				GOTO BRANCH_END;
			END
		END

		-- Nome (e codice, se indicato) unici tra le aliquote di sistema e quelle attive dell'azienda
		IF EXISTS (
			SELECT 1
			FROM dbo.tblAliquoteIva
			WHERE
				Id <> @Id
				AND (IdSede IS NULL OR IdSede = @idAzienda)
				AND Lock = 0
				AND Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra aliquota con lo stesso nome è già presente';
			GOTO BRANCH_END;
		END
		IF @Codice IS NOT NULL AND EXISTS (
			SELECT 1
			FROM dbo.tblAliquoteIva
			WHERE
				Id <> @Id
				AND (IdSede IS NULL OR IdSede = @idAzienda)
				AND Lock = 0
				AND Codice = @Codice
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Un''altra aliquota con lo stesso codice è già presente';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblAliquoteIva
			SET
				Lock = 0,
				IdTipo = @IdTipo,
				IdNatura = @IdNatura,
				Nome = @Nome,
				Codice = @Codice,
				Valore = @Valore
			WHERE
				Id = @Id
				AND IdSede IS NOT NULL
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Aliquota non trovata o già eliminata';
				GOTO BRANCH_END;
			END
		COMMIT TRANSACTION;

		-- Log FUORI dalla transazione
		EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'U';

		SELECT ReturnValue = @returnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1;
	END
END;
GO

PRINT 'uspSedi_del_SediEsterne';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspSedi_del_SediEsterne]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'ANS',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblSedi
		WHERE Id = @Id);

		IF @lock IS NULL
		BEGIN
			-- Idempotenza: sede mai esistita o già cancellata (es. doppio invio della richiesta
			-- di annullamento lato UI, senza protezione anti-doppio-submit sul pulsante) — la
			-- si tratta come cancellazione già avvenuta con successo, non come errore: lo stato
			-- desiderato ("questa sede non esiste") è già raggiunto.
			SET @returnValue = 0;
		END
		ELSE IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblSedi
			WHERE
				IdParent = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede non può essere cancellata se contiene altre sedi';
				GOTO BRANCH_END;
			END

			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi s
				INNER JOIN dbo.tblSessioni e ON s.IdAziendaInterna = e.IdAzienda
				WHERE
					s.Id = @Id
					AND e.Id = @IdSessione
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede condivisa da altre aziende non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblAreeOsepe ao
				INNER JOIN dbo.tblAree a ON ao.Id = a.Id
				WHERE
					ao.IdOsepe = @Id
					AND a.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un''area non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiAutorizzazioni
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un''autorizzazione rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRentriCredenzialiSedi
			WHERE IdSede = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con credenziali RENTRI associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Magazzino: una sede esterna può comparire solo come destinatario o
			-- trasportatore di un DDT (Articoli/Lotti/Movimenti/Righe sono sempre su sedi interne)
			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniDdt WHERE IdDestinatario = @Id OR IdTrasportatore = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a un DDT di magazzino (destinatario/trasportatore) non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Anagrafica estesa: un soggetto con una scheda cliente o fornitore attiva
			IF EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede presente tra i clienti o i fornitori non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblSedi
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END
		ELSE IF @lock = 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				-- Modulo Magazzino: DDT dove questa sede esterna compare come destinatario o
				-- trasportatore. Ramo di fatto irraggiungibile in pratica (blocco sopra su
				-- Lock=0), mantenuto per difesa dalla FK.
				DELETE dbo.tblMagazziniDdt
				WHERE IdDestinatario = @Id OR IdTrasportatore = @Id;

				DELETE dbo.tblAreeOsepe
				WHERE IdOsepe = @Id;

				-- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL. In
				-- pratica non popolata per una sede esterna (blocco sopra su Lock=0 comunque già la
				-- impedisce), mantenuta per difesa dalla FK NO_ACTION.
				DELETE dbo.tblRentriCredenzialiSedi
				WHERE IdSede = @Id;

				DELETE dbo.tblSediEsterne
				WHERE Id = @Id;
				DELETE dbo.tblSedi
				WHERE Id = @Id;
				DELETE dbo.tblOsepe
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
GO

PRINT 'uspSedi_del_SediInterne';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[uspSedi_del_SediInterne]
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Reset BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'AZI',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock
		FROM dbo.tblSedi
		WHERE Id = @Id);

		IF @lock IS NULL
		BEGIN
			-- Idempotenza: sede mai esistita o già cancellata (es. doppio invio della richiesta
			-- di annullamento lato UI) — trattata come cancellazione già avvenuta con successo,
			-- non come errore.
			SET @returnValue = 0;
		END
		ELSE IF @lock = 0
		BEGIN
			IF EXISTS (SELECT 1
			FROM dbo.tblSedi
			WHERE
				IdParent = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede non può essere cancellata se contiene altre sedi';
				GOTO BRANCH_END;
			END

			-- Titolarità: Admin dello stesso Dominio della sede, oppure Admin di un Dominio Master.
			-- Il bypass Master è intenzionale (confermato dall'utente): un Master-admin deve poter
			-- cancellare/modificare aziende interne di qualsiasi dominio, non solo del proprio.
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.tblSedi s
				INNER JOIN dbo.tblSediInterne i ON ISNULL(s.IdParent, s.Id) = i.Id
				INNER JOIN dbo.tblUtenti a ON i.IdDominio = a.IdDominio
				INNER JOIN dbo.tblSessioni e ON a.Id = e.IdUtente
				WHERE
					s.Id = @Id
					AND e.Id = @IdSessione
					AND a.IdRuolo = 'AD'
					AND a.Lock = 0
			)
			AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblSessioni e
				INNER JOIN dbo.tblUtenti ut ON e.IdUtente = ut.Id
				INNER JOIN dbo.tblDomini d ON ut.IdDominio = d.Id
				WHERE
					e.Id = @IdSessione
					AND ut.IdRuolo = 'AD'
					AND ut.Lock = 0
					AND d.[Master] = 1
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblSediEsterne e INNER JOIN dbo.tblSedi s ON e.Id = s.Id
			WHERE
				e.IdSedeInterna = @Id
				AND s.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''azienda con soggetti associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblOggetti
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con oggetti associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblPersone
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con persone associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblCalendari
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con calendari associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Magazzino: Articoli/Movimenti hanno IdSede = Azienda; Lotti/Righe hanno
			-- IdSede = sede operativa (può essere una sede figlia diversa dall'Azienda)
			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniArticoli WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con articoli di magazzino associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniLotti WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con lotti di magazzino associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con movimenti di magazzino associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRighe WHERE IdSede = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con righe di magazzino associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniMovimentiRigheEoW WHERE IdSede = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con righe EoW di magazzino associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniDdt WHERE IdSede = @Id OR IdMittente = @Id OR IdDestinatario = @Id OR IdTrasportatore = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a un DDT di magazzino non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Moduli Anagrafica estesa e Fatturazione: schede clienti/fornitori, banche e casse,
			-- aliquote IVA proprie appartengono all'azienda interna
			IF EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE IdAziendaInterna = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con clienti o fornitori associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblBancheCasse WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con banche o casse associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblAliquoteIva WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con aliquote IVA associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Gestione EoW: stesso controllo del magazzino tradizionale, su lotti/allocazioni EoW
			-- proprie della sede (IdSede è sempre la Sede Interna, non quella esterna condivisa)
			IF EXISTS (SELECT 1
			FROM dbo.tblEoWLotti
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con lotti EoW associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblEoWAllocazioni
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con allocazioni EoW associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblEoWMagazzini
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con magazzini EoW associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiRegistri
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con registri c/s rifiuti associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblEtichette
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con etichette associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblTipi
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con tipi di scadenze/servizi associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblAreeSediInterne ai
				INNER JOIN dbo.tblAree a ON ai.Id = a.Id
				WHERE
					ai.IdSede = @Id
					AND a.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un''area non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiAutorizzazioni
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con autorizzazioni rifiuti associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiLimiti
			WHERE
				IdSede = @Id
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con limiti rifiuti associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblRentriRegistri rr
				INNER JOIN dbo.tblRifiutiRegistri r ON rr.Id = r.Id
				WHERE r.IdSede = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con registri RENTRI associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1
			FROM dbo.tblRentriCredenzialiSedi
			WHERE IdSede = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con credenziali RENTRI associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblSedi
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @Reset = 1
					DELETE dbo.tblIdCancellati
					WHERE IdSessione = @IdSessione;
				ELSE
					DELETE dbo.tblIdCancellati
					WHERE Id = @Id;

				INSERT INTO dbo.tblIdCancellati (Id, IdSessione, [Data])
				VALUES (@Id, @IdSessione, GETDATE());
			COMMIT TRANSACTION;

			EXEC dbo.uspId_upd @Id = @Id, @IdSessione = @IdSessione, @Operazione = 'D';
		END
		ELSE IF @lock = 2
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM dbo.tblRifiutiMovimenti
				WHERE
					IdSedeProduttoreDetentore = @Id
					OR IdSedeDestinatario = @Id
					OR IdSedeTrasportatore1 = @Id
					OR IdSedeIntermediario1 = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a movimenti rifiuti non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblServizi s
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					s.IdRichiedente = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad un servizio non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM dbo.tblScadenzeOsepe o
				INNER JOIN dbo.tblScadenze s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
					AND e.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata ad una scadenza non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				DELETE dbo.tblUtentiSediInterne
				WHERE IdSede = @Id;
				DELETE dbo.tblAreeSediInterne
				WHERE IdSede = @Id;
				DELETE dbo.tblCalendari
				WHERE IdSede = @Id;
				DELETE dbo.tblEtichette
				WHERE IdSede = @Id;

				-- Modulo Magazzino: cascata figlio->genitore (FK NO_ACTION, nessun ON DELETE
				-- CASCADE). Ramo di fatto irraggiungibile in pratica (i blocchi sopra su Lock=0
				-- impediscono di arrivare in bozza con dati di magazzino già associati),
				-- mantenuto per difesa dalla FK.
				DELETE rel
				FROM dbo.tblMagazziniMovimentiRigheRelazioni rel
				INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rel.Id = r.Id OR rel.IdParent = r.Id
				WHERE r.IdSede = @Id OR r.IdMovimento IN (SELECT Id FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id);

				DELETE rel
				FROM dbo.tblMagazziniMovimentiRigheEoWLotti rel
				INNER JOIN dbo.tblMagazziniMovimentiRigheEoW re ON rel.Id = re.Id
				WHERE re.IdSede = @Id;

				DELETE dbo.tblMagazziniDdt
				WHERE
					IdMittente = @Id
					OR IdDestinatario = @Id
					OR IdTrasportatore = @Id
					OR IdMovimento IN (SELECT Id FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id);

				DELETE dbo.tblMagazziniMovimentiRighe
				WHERE
					IdSede = @Id
					OR IdMovimento IN (SELECT Id FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id);

				DELETE dbo.tblMagazziniMovimentiRigheEoW
				WHERE
					IdSede = @Id
					OR IdMovimento IN (SELECT Id FROM dbo.tblMagazziniMovimenti WHERE IdSede = @Id);

				DELETE dbo.tblMagazziniMovimenti
				WHERE IdSede = @Id;

				DELETE dbo.tblMagazziniLotti
				WHERE IdSede = @Id;

				DELETE dbo.tblMagazziniArticoli
				WHERE IdSede = @Id;

				-- Anagrafica estesa e Fatturazione: in bozza l'azienda non dovrebbe averne, mantenuto
				-- per difesa dalle FK (prima le schede, che referenziano banche/casse e aliquote)
				DELETE dbo.tblClientiFornitori
				WHERE IdAziendaInterna = @Id;

				DELETE dbo.tblBancheCasse
				WHERE IdSede = @Id;

				DELETE dbo.tblAliquoteIva
				WHERE IdSede = @Id;

				-- Gestione EoW: lotti/allocazioni EoW di proprietà esclusiva della sede (IdSede sempre
				-- Sede Interna) e le loro righe di collegamento M:N, nell'ordine figlio->padre richiesto
				-- dalle FK NO_ACTION (stesso ordine/logica di uspSYS_del_SedeInternaCascade).
				DELETE lrr
				FROM dbo.tblEoWLottiRifiutiRegistrazioni lrr
				INNER JOIN dbo.tblEoWLotti l ON lrr.IdLotto = l.Id
				WHERE l.IdSede = @Id;

				DELETE la
				FROM dbo.tblEoWLottiAllocazioni la
				LEFT JOIN dbo.tblEoWLotti l ON la.IdLotto = l.Id
				LEFT JOIN dbo.tblEoWAllocazioni al ON la.IdAllocazione = al.Id
				WHERE
					l.IdSede = @Id
					OR al.IdSede = @Id;

				DELETE dbo.tblEoWLotti
				WHERE IdSede = @Id;

				DELETE dbo.tblEoWAllocazioni
				WHERE IdSede = @Id;

				-- tblEoWLotti.IdMagazzino (FK NO_ACTION) va rimosso prima: i Lotti di questa sede sono
				-- già stati cancellati sopra, un eventuale Lotto esterno che referenziasse un Magazzino
				-- di questa sede è di fatto irraggiungibile in pratica (bozza non linkabile da UI prima
				-- della finalizzazione), mantenuto per difesa dalla FK.
				DELETE dbo.tblEoWMagazzini
				WHERE IdSede = @Id;

				DELETE dbo.tblRifiutiAutorizzazioni
				WHERE IdSede = @Id;

				-- tblRifiutiLimiti* va rimosso prima di tblRifiutiRegistri: FK NO_ACTION su IdRegistro
				-- bloccherebbe altrimenti la cancellazione del registro sottostante.
				DELETE dbo.tblRifiutiLimitiEer
				WHERE IdLimite IN (SELECT Id FROM dbo.tblRifiutiLimiti WHERE IdSede = @Id);
				DELETE dbo.tblRifiutiLimitiEtichette
				WHERE IdLimite IN (SELECT Id FROM dbo.tblRifiutiLimiti WHERE IdSede = @Id);
				DELETE dbo.tblRifiutiLimitiOperazioni
				WHERE IdLimite IN (SELECT Id FROM dbo.tblRifiutiLimiti WHERE IdSede = @Id);
				DELETE dbo.tblRifiutiLimiti
				WHERE IdSede = @Id;

				-- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL,
				-- nessun ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante
				-- fallisce per FK. Ramo di fatto irraggiungibile in pratica (il blocco sopra su
				-- Lock=0 impedisce di arrivare in bozza con registri RENTRI già associati).
				DELETE dbo.tblRentriRegistri
				WHERE Id IN (SELECT Id FROM dbo.tblRifiutiRegistri WHERE IdSede = @Id);

				DELETE dbo.tblRifiutiRegistri
				WHERE IdSede = @Id;
				DELETE dbo.tblTipi
				WHERE IdSede = @Id;
				DELETE dbo.tblOggetti
				WHERE IdSede = @Id;
				DELETE dbo.tblPersone
				WHERE IdSede = @Id;
				DELETE dbo.tblSediEsterne
				WHERE IdSedeInterna = @Id;

				-- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL
				-- (nessuna colonna da azzerare) - si cancella la riga di associazione, mai
				-- tblRentriCredenziali stessa. Ramo di fatto irraggiungibile in pratica (blocco
				-- sopra su Lock=0), mantenuto per difesa dalla FK NO_ACTION.
				DELETE dbo.tblRentriCredenzialiSedi
				WHERE IdSede = @Id;

				DELETE dbo.tblSediInterne
				WHERE Id = @Id;
				DELETE dbo.tblSedi
				WHERE Id = @Id;
				DELETE dbo.tblOsepe
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La sede è già in uno stato non modificabile (Lock = ' + CAST(@lock AS VARCHAR(5)) + ')';
			GOTO BRANCH_END;
		END

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
	BRANCH_END:
	SET NOCOUNT, XACT_ABORT OFF;
	IF @returnValue < 0
	BEGIN
		SET @returnMessage = ISNULL(@returnMessage, 'Database exception');
		THROW 50001, @returnMessage, 1
	END

END;
GO
