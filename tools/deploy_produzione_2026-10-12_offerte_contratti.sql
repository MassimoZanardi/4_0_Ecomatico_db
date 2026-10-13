/*
Deploy produzione 2026-10-12 - Modulo Offerte e contratti (importi, contratti e offerte dei clienti, fatturazione
automatica dalle registrazioni dei rifiuti) e Fatturazione > Rinumera le fatture

Da eseguire DOPO gli script del 2026-10-11. Rieseguibile.
Eseguire con sqlcmd -f 65001 -I (oppure da SSMS). Va deployato insieme all'app.

1. Tabelle del modulo, create solo se mancano: tblImportiPriorita, tblImportiRigheTipi, tblImporti,
   tblImportiRifiuti, tblImportiMagazzino, tblImportiServizi, tblImportiRighe, tblImportiRigheDettagli,
   tblOfferteContratti, tblOfferteContrattiImporti.
2. Valori di riferimento: priorita' degli importi e tipi di riga.
3. Struttura e registrazione del modulo: tblRifiutiOperazioni.IsFatturabile (T*, T*aT, TR),
   tblClientiFornitori.IdRaggruppamento, tblImportiRighe.Pos, tblImportiRifiuti.IdSede (azienda dell'importo,
   copiata sulle variabili), tblFattureDocumenti, tblPagine.IdModulo, indici (compresi quelli sulle chiavi esterne
   di tblFattureDocumenti e IX_ImportiRifiuti_IdSede), modulo OFC con le funzioni OCC e OCI, pagine e menu
   (Offerte e contratti prima di Fatturazione).
4. Funzioni: elenchi di importi e contratti, importi che coincidono con i valori di un documento
   (ufnImportiRifiuti_get_Coincidenti), importo e cliente applicati alle registrazioni con un confronto a insiemi
   (ufnImportiRifiuti_get_Applicazione_List), righe di fattura dell'importo applicato
   (ufnImportiRifiuti_get_RigheImporto), documenti da fatturare.
5. Stored procedure nuove: importi rifiuti e righe (con il conteggio di quelli di contratti scaduti, la verifica
   degli importi uspImportiRifiuti_get_Verifica e i conflitti uspImportiRifiuti_get_Conflitti), contratti e
   offerte, blocco "Cliente a cui fatturare" (uspFattureDocumenti_*), verifica e generazione delle fatture
   (uspFatture_get_Genera_Riepilogo, uspFatture_get_Genera_Fatture_List, uspFatture_get_Genera_List,
   uspFatture_ins_Genera), rinumerazione delle fatture (uspFatture_upd_Numerazione).
6. Stored procedure modificate: uspMenu_get (voci che richiedono un secondo modulo), select di aliquote IVA,
   conti e clienti leggibili con i permessi del modulo, blocchi di cancellazione (soggetti, aziende, conti,
   aliquote, clienti), uspFattureRate_ins_Genera (parametro @Interno), cancellazioni a cascata di sviluppo.

Il modulo non viene attivato su nessun dominio: si attiva da Impostazioni > Domini con un utente Master.
Lo script del report ORSO Impianti (deploy_produzione_2026-10-12_report_orso_impianti.sql) e' separato.

Dopo il deploy: eseguire tools\verifica_crlf_accenti.sql, che deve dare 0 righe.
*/

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

PRINT 'sql/tables/tblImportiPriorita.sql (solo se la tabella manca)';
GO
IF OBJECT_ID('dbo.tblImportiPriorita') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiPriorita](
	[Id] [int] NOT NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblImportiPriorita] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
GO
SET NOEXEC OFF;
GO

PRINT 'sql/tables/tblImportiRigheTipi.sql (solo se la tabella manca)';
GO
IF OBJECT_ID('dbo.tblImportiRigheTipi') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiRigheTipi](
	[Id] [char](2) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdModulo] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Pos] [int] NULL,
 CONSTRAINT [PK_tblImportiRigheTipi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImportiRigheTipi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRigheTipi_tblModuli] FOREIGN KEY([IdModulo])
REFERENCES [dbo].[tblModuli] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRigheTipi] CHECK CONSTRAINT [FK_tblImportiRigheTipi_tblModuli]
GO
GO
SET NOEXEC OFF;
GO

PRINT 'sql/tables/tblImporti.sql (solo se la tabella manca)';
GO
IF OBJECT_ID('dbo.tblImporti') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImporti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdPriorita] [int] NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblImporti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_Importi_IdSede] ON [dbo].[tblImporti]
(
	[IdSede] ASC
)
INCLUDE([IdPriorita],[Lock]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImporti]  WITH CHECK ADD  CONSTRAINT [FK_tblImporti_tblImportiPriorita] FOREIGN KEY([IdPriorita])
REFERENCES [dbo].[tblImportiPriorita] ([Id])
GO

ALTER TABLE [dbo].[tblImporti] CHECK CONSTRAINT [FK_tblImporti_tblImportiPriorita]
GO

ALTER TABLE [dbo].[tblImporti]  WITH CHECK ADD  CONSTRAINT [FK_tblImporti_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImporti] CHECK CONSTRAINT [FK_tblImporti_tblSedi]
GO
GO
SET NOEXEC OFF;
GO

PRINT 'sql/tables/tblImportiRifiuti.sql (solo se la tabella manca)';
GO
IF OBJECT_ID('dbo.tblImportiRifiuti') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiRifiuti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NULL,
	[IdProduttoreParent] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdProduttore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdTrasportatore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdDestinatario] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdIntermediario] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEtichetta] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblImportiRifiuti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_ImportiRifiuti_IdSede] ON [dbo].[tblImportiRifiuti]
(
	[IdSede] ASC
)
INCLUDE([IdEer],[IdProduttoreParent],[IdProduttore],[IdTrasportatore],[IdDestinatario],[IdIntermediario],[IdEtichetta]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblEtichette] FOREIGN KEY([IdEtichetta])
REFERENCES [dbo].[tblEtichette] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblEtichette]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblImporti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblImporti] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblImporti]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblRifiutiEer] FOREIGN KEY([IdEer])
REFERENCES [dbo].[tblRifiutiEer] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblRifiutiEer]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdDestinatario] FOREIGN KEY([IdDestinatario])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdDestinatario]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdIntermediario] FOREIGN KEY([IdIntermediario])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdIntermediario]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdProduttore] FOREIGN KEY([IdProduttore])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdProduttore]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdProduttoreParent] FOREIGN KEY([IdProduttoreParent])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdProduttoreParent]
GO

ALTER TABLE [dbo].[tblImportiRifiuti]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdTrasportatore] FOREIGN KEY([IdTrasportatore])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRifiuti] CHECK CONSTRAINT [FK_tblImportiRifiuti_tblSedi_IdTrasportatore]
GO
GO
SET NOEXEC OFF;
GO

PRINT 'sql/tables/tblImportiMagazzino.sql (solo se la tabella manca)';
GO
IF OBJECT_ID('dbo.tblImportiMagazzino') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiMagazzino](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdMittenteParent] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdMittente] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdDestinatarioParent] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdDestinatario] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEtichetta] [char](16) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblImportiMagazzino] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImportiMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiMagazzino_tblEtichette] FOREIGN KEY([IdEtichetta])
REFERENCES [dbo].[tblEtichette] ([Id])
GO

ALTER TABLE [dbo].[tblImportiMagazzino] CHECK CONSTRAINT [FK_tblImportiMagazzino_tblEtichette]
GO

ALTER TABLE [dbo].[tblImportiMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiMagazzino_tblImporti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblImporti] ([Id])
GO

ALTER TABLE [dbo].[tblImportiMagazzino] CHECK CONSTRAINT [FK_tblImportiMagazzino_tblImporti]
GO

ALTER TABLE [dbo].[tblImportiMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdDestinatario] FOREIGN KEY([IdDestinatario])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiMagazzino] CHECK CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdDestinatario]
GO

ALTER TABLE [dbo].[tblImportiMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdDestinatarioParent] FOREIGN KEY([IdDestinatarioParent])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiMagazzino] CHECK CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdDestinatarioParent]
GO

ALTER TABLE [dbo].[tblImportiMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdMittente] FOREIGN KEY([IdMittente])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiMagazzino] CHECK CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdMittente]
GO

ALTER TABLE [dbo].[tblImportiMagazzino]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdMittenteParent] FOREIGN KEY([IdMittenteParent])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiMagazzino] CHECK CONSTRAINT [FK_tblImportiMagazzino_tblSedi_IdMittenteParent]
GO
GO
SET NOEXEC OFF;
GO

PRINT 'sql/tables/tblImportiServizi.sql (solo se la tabella manca)';
GO
IF OBJECT_ID('dbo.tblImportiServizi') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiServizi](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdTipo] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdRichiedenteParent] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdRichiedente] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEsecutore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEtichetta] [char](16) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblImportiServizi] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblEtichette] FOREIGN KEY([IdEtichetta])
REFERENCES [dbo].[tblEtichette] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblEtichette]
GO

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblImporti] FOREIGN KEY([Id])
REFERENCES [dbo].[tblImporti] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblImporti]
GO

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblSedi_IdEsecutore] FOREIGN KEY([IdEsecutore])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblSedi_IdEsecutore]
GO

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblSedi_IdRichiedente] FOREIGN KEY([IdRichiedente])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblSedi_IdRichiedente]
GO

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblSedi_IdRichiedenteParent] FOREIGN KEY([IdRichiedenteParent])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblSedi_IdRichiedenteParent]
GO

ALTER TABLE [dbo].[tblImportiServizi]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiServizi_tblTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblTipi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiServizi] CHECK CONSTRAINT [FK_tblImportiServizi_tblTipi]
GO
GO
SET NOEXEC OFF;
GO

PRINT 'sql/tables/tblImportiRighe.sql (solo se la tabella manca)';
GO
IF OBJECT_ID('dbo.tblImportiRighe') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiRighe](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdImporto] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdTipo] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Importo] [decimal](18, 4) NULL,
	[MinimoFatturabile] [bit] NULL,
	[Lock] [tinyint] NULL,
	[Pos] [int] NULL,
 CONSTRAINT [PK_tblImportiRighe] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_ImportiRighe_IdImporto] ON [dbo].[tblImportiRighe]
(
	[IdImporto] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImportiRighe]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRighe_tblImporti] FOREIGN KEY([IdImporto])
REFERENCES [dbo].[tblImporti] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRighe] CHECK CONSTRAINT [FK_tblImportiRighe_tblImporti]
GO

ALTER TABLE [dbo].[tblImportiRighe]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRighe_tblImportiRigheTipi] FOREIGN KEY([IdTipo])
REFERENCES [dbo].[tblImportiRigheTipi] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRighe] CHECK CONSTRAINT [FK_tblImportiRighe_tblImportiRigheTipi]
GO
GO
SET NOEXEC OFF;
GO

PRINT 'sql/tables/tblImportiRigheDettagli.sql (solo se la tabella manca)';
GO
IF OBJECT_ID('dbo.tblImportiRigheDettagli') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblImportiRigheDettagli](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdAliquotaIva] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdConto] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Descrizione] [varchar](1000) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblImportiRigheDettagli] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblImportiRigheDettagli]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRigheDettagli_tblAliquoteIva] FOREIGN KEY([IdAliquotaIva])
REFERENCES [dbo].[tblAliquoteIva] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRigheDettagli] CHECK CONSTRAINT [FK_tblImportiRigheDettagli_tblAliquoteIva]
GO

ALTER TABLE [dbo].[tblImportiRigheDettagli]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRigheDettagli_tblFattureConti] FOREIGN KEY([IdConto])
REFERENCES [dbo].[tblFattureConti] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRigheDettagli] CHECK CONSTRAINT [FK_tblImportiRigheDettagli_tblFattureConti]
GO

ALTER TABLE [dbo].[tblImportiRigheDettagli]  WITH CHECK ADD  CONSTRAINT [FK_tblImportiRigheDettagli_tblImportiRighe] FOREIGN KEY([Id])
REFERENCES [dbo].[tblImportiRighe] ([Id])
GO

ALTER TABLE [dbo].[tblImportiRigheDettagli] CHECK CONSTRAINT [FK_tblImportiRigheDettagli_tblImportiRighe]
GO
GO
SET NOEXEC OFF;
GO

PRINT 'sql/tables/tblOfferteContratti.sql (solo se la tabella manca)';
GO
IF OBJECT_ID('dbo.tblOfferteContratti') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblOfferteContratti](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdClienteFornitore] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Tipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[ClienteFornitoreTipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[DataInizio] [date] NULL,
	[DataFine] [date] NULL,
	[Descrizione] [varchar](1000) COLLATE Latin1_General_CI_AS NULL,
	[Protocollo] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Ordine] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[DataOrdine] [date] NULL,
	[CodiceCig] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[CodiceCup] [varchar](15) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblOfferteContratti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_OfferteContratti_IdSede] ON [dbo].[tblOfferteContratti]
(
	[IdSede] ASC
)
INCLUDE([IdClienteFornitore],[Tipo],[Lock]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblOfferteContratti]  WITH CHECK ADD  CONSTRAINT [FK_tblOfferteContratti_tblClientiFornitori] FOREIGN KEY([IdClienteFornitore])
REFERENCES [dbo].[tblClientiFornitori] ([Id])
GO

ALTER TABLE [dbo].[tblOfferteContratti] CHECK CONSTRAINT [FK_tblOfferteContratti_tblClientiFornitori]
GO

ALTER TABLE [dbo].[tblOfferteContratti]  WITH CHECK ADD  CONSTRAINT [FK_tblOfferteContratti_tblSedi] FOREIGN KEY([IdSede])
REFERENCES [dbo].[tblSedi] ([Id])
GO

ALTER TABLE [dbo].[tblOfferteContratti] CHECK CONSTRAINT [FK_tblOfferteContratti_tblSedi]
GO
GO
SET NOEXEC OFF;
GO

PRINT 'sql/tables/tblOfferteContrattiImporti.sql (solo se la tabella manca)';
GO
IF OBJECT_ID('dbo.tblOfferteContrattiImporti') IS NOT NULL SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblOfferteContrattiImporti](
	[IdOffertaContratto] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdImporto] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblOfferteContrattiImporti] PRIMARY KEY CLUSTERED 
(
	[IdOffertaContratto] ASC,
	[IdImporto] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE UNIQUE NONCLUSTERED INDEX [UX_OfferteContrattiImporti_IdImporto] ON [dbo].[tblOfferteContrattiImporti]
(
	[IdImporto] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblOfferteContrattiImporti]  WITH CHECK ADD  CONSTRAINT [FK_tblOfferteContrattiImporti_tblImporti] FOREIGN KEY([IdImporto])
REFERENCES [dbo].[tblImporti] ([Id])
GO

ALTER TABLE [dbo].[tblOfferteContrattiImporti] CHECK CONSTRAINT [FK_tblOfferteContrattiImporti_tblImporti]
GO

ALTER TABLE [dbo].[tblOfferteContrattiImporti]  WITH CHECK ADD  CONSTRAINT [FK_tblOfferteContrattiImporti_tblOfferteContratti] FOREIGN KEY([IdOffertaContratto])
REFERENCES [dbo].[tblOfferteContratti] ([Id])
GO

ALTER TABLE [dbo].[tblOfferteContrattiImporti] CHECK CONSTRAINT [FK_tblOfferteContrattiImporti_tblOfferteContratti]
GO
GO
SET NOEXEC OFF;
GO

PRINT 'tools/offerte_contratti_dati.sql';
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Modulo Offerte e contratti: valori delle tabelle di riferimento degli importi.
--   tblImportiPriorita: priorità con cui la fatturazione automatica sceglie l'importo (la più alta vince)
--   tblImportiRigheTipi: per che cosa si moltiplica l'importo di una riga, per modulo dei documenti
--     (rifiuti: una volta per registrazione, per i chilogrammi, le tonnellate o i litri; magazzino: per
--     movimento o per articolo; servizi: per servizio o per unità)
-- Rieseguibile: inserisce le righe mancanti e riallinea i nomi.

BEGIN TRANSACTION;

IF NOT EXISTS (SELECT 1 FROM dbo.tblImportiPriorita WHERE Id = 2)
	INSERT INTO dbo.tblImportiPriorita (Id, Nome) VALUES (2, 'Bassa');
IF NOT EXISTS (SELECT 1 FROM dbo.tblImportiPriorita WHERE Id = 4)
	INSERT INTO dbo.tblImportiPriorita (Id, Nome) VALUES (4, 'Media');
IF NOT EXISTS (SELECT 1 FROM dbo.tblImportiPriorita WHERE Id = 6)
	INSERT INTO dbo.tblImportiPriorita (Id, Nome) VALUES (6, 'Alta');

DECLARE @tipi TABLE (
	Id CHAR(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	IdModulo CHAR(3) COLLATE DATABASE_DEFAULT NOT NULL,
	Nome VARCHAR(50) NOT NULL,
	Pos INT NOT NULL
);
INSERT @tipi (Id, IdModulo, Nome, Pos)
VALUES
	('MM', 'MAG', 'Movimento', 1),
	('MA', 'MAG', 'Articolo', 2),
	('RM', 'RIF', 'Movimento', 1),
	('RK', 'RIF', 'KG (Kilogrammo)', 2),
	('RT', 'RIF', 'T (Tonnellata)', 3),
	('RL', 'RIF', 'L (Litro)', 4),
	('SM', 'SRV', 'Servizio', 1),
	('SU', 'SRV', 'Unità', 2);

INSERT INTO dbo.tblImportiRigheTipi (Id, IdModulo, Nome, Pos)
SELECT t.Id, t.IdModulo, t.Nome, t.Pos
FROM @tipi t
WHERE NOT EXISTS (SELECT 1 FROM dbo.tblImportiRigheTipi x WHERE x.Id = t.Id);

UPDATE x
SET
	IdModulo = t.IdModulo,
	Nome = t.Nome,
	Pos = t.Pos
FROM
	dbo.tblImportiRigheTipi x
	INNER JOIN @tipi t ON x.Id = t.Id
WHERE
	ISNULL(x.IdModulo, '') <> t.IdModulo
	OR ISNULL(x.Nome, '') <> t.Nome COLLATE Latin1_General_BIN2
	OR ISNULL(x.Pos, 0) <> t.Pos;

COMMIT TRANSACTION;
GO

SELECT Id, Nome FROM dbo.tblImportiPriorita ORDER BY Id DESC;
SELECT Id, IdModulo, Nome, Pos FROM dbo.tblImportiRigheTipi ORDER BY IdModulo, Pos;
GO
GO

PRINT 'tools/offerte_contratti_struttura.sql';
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Modulo Offerte e contratti (OFC): struttura mancante e registrazione di modulo, funzioni, pagine e menu.
--   Le tabelle tblOfferteContratti* e tblImporti* esistono gia'; qui si aggiunge solo quello che manca.
--   1. tblRifiutiOperazioni.IsFatturabile: operazioni le cui registrazioni entrano nella fatturazione (T*, T*aT, TR)
--   2. tblClientiFornitori.IdRaggruppamento: una fattura per cliente (C), per sede (S) o per contratto (T)
--   3. tblImportiRighe.Pos: ordine delle righe dell'importo
--   3b. tblImportiRifiuti.IdSede: azienda dell'importo, copiata sulle variabili per il confronto con i documenti
--   4. tblFattureDocumenti: legame tra il documento fatturabile (registrazione, movimento con DDT, servizio)
--      e la fattura, con "non fatturabile" e cliente indicato sul documento
--   5. tblPagine.IdModulo: modulo che il dominio deve avere attivo, oltre a quello dell'area, per vedere la voce
--   6. Indici
--   7. Modulo OFC, area di menu prima di Fatturazione, funzioni OCC e OCI, pagine e voci di menu
-- In tblModuliRelazioni Id = modulo richiesto, IdParent = modulo che lo richiede.
-- Nessuna attivazione sui domini: il modulo si attiva da Impostazioni > Domini.
-- Rieseguibile.

BEGIN TRANSACTION;

-- 1. Operazioni fatturabili
IF COL_LENGTH('dbo.tblRifiutiOperazioni', 'IsFatturabile') IS NULL
	ALTER TABLE dbo.tblRifiutiOperazioni ADD IsFatturabile BIT NULL;

-- 2. Raggruppamento delle fatture generate, sulla scheda del cliente
IF COL_LENGTH('dbo.tblClientiFornitori', 'IdRaggruppamento') IS NULL
BEGIN
	ALTER TABLE dbo.tblClientiFornitori ADD IdRaggruppamento CHAR(1) COLLATE Latin1_General_CI_AS NULL;

	ALTER TABLE dbo.tblClientiFornitori WITH CHECK ADD CONSTRAINT FK_tblClientiFornitori_tblFattureRaggruppamenti
		FOREIGN KEY (IdRaggruppamento) REFERENCES dbo.tblFattureRaggruppamenti (Id);
END

-- 3. Ordine delle righe dell'importo
IF COL_LENGTH('dbo.tblImportiRighe', 'Pos') IS NULL
	ALTER TABLE dbo.tblImportiRighe ADD Pos INT NULL;

-- 3b. Azienda dell'importo copiata sulle variabili dei rifiuti: il confronto con i documenti legge con un solo
--     accesso gli importi dell'azienda (ufnImportiRifiuti_get_Coincidenti). La scrive uspImportiRifiuti_ins e non
--     cambia più, come tblImporti.IdSede di cui è la copia
IF COL_LENGTH('dbo.tblImportiRifiuti', 'IdSede') IS NULL
	ALTER TABLE dbo.tblImportiRifiuti ADD IdSede CHAR(16) COLLATE Latin1_General_CI_AS NULL;

-- 4. Documenti fatturabili: Id = Id del documento (registrazione, movimento di magazzino, servizio)
IF OBJECT_ID('dbo.tblFattureDocumenti', 'U') IS NULL
BEGIN
	CREATE TABLE dbo.tblFattureDocumenti (
		Id CHAR(16) COLLATE Latin1_General_CI_AS NOT NULL,
		IdModulo CHAR(3) COLLATE Latin1_General_CI_AS NOT NULL,
		IdFattura CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		IdClienteFornitore CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		IdImporto CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		IdOffertaContratto CHAR(16) COLLATE Latin1_General_CI_AS NULL,
		NonFatturabile BIT NULL,
		CONSTRAINT PK_tblFattureDocumenti PRIMARY KEY CLUSTERED (Id ASC)
	);

	ALTER TABLE dbo.tblFattureDocumenti WITH CHECK ADD CONSTRAINT FK_tblFattureDocumenti_tblId
		FOREIGN KEY (Id) REFERENCES dbo.tblId (Id);
	ALTER TABLE dbo.tblFattureDocumenti WITH CHECK ADD CONSTRAINT FK_tblFattureDocumenti_tblModuli
		FOREIGN KEY (IdModulo) REFERENCES dbo.tblModuli (Id);
	ALTER TABLE dbo.tblFattureDocumenti WITH CHECK ADD CONSTRAINT FK_tblFattureDocumenti_tblFatture
		FOREIGN KEY (IdFattura) REFERENCES dbo.tblFatture (Id);
	ALTER TABLE dbo.tblFattureDocumenti WITH CHECK ADD CONSTRAINT FK_tblFattureDocumenti_tblClientiFornitori
		FOREIGN KEY (IdClienteFornitore) REFERENCES dbo.tblClientiFornitori (Id);
	ALTER TABLE dbo.tblFattureDocumenti WITH CHECK ADD CONSTRAINT FK_tblFattureDocumenti_tblImporti
		FOREIGN KEY (IdImporto) REFERENCES dbo.tblImporti (Id);
	ALTER TABLE dbo.tblFattureDocumenti WITH CHECK ADD CONSTRAINT FK_tblFattureDocumenti_tblOfferteContratti
		FOREIGN KEY (IdOffertaContratto) REFERENCES dbo.tblOfferteContratti (Id);
END

-- 5. Modulo richiesto dalla pagina oltre a quello dell'area di menu
IF COL_LENGTH('dbo.tblPagine', 'IdModulo') IS NULL
BEGIN
	ALTER TABLE dbo.tblPagine ADD IdModulo CHAR(3) COLLATE Latin1_General_CI_AS NULL;

	ALTER TABLE dbo.tblPagine WITH CHECK ADD CONSTRAINT FK_tblPagine_tblModuli
		FOREIGN KEY (IdModulo) REFERENCES dbo.tblModuli (Id);
END

COMMIT TRANSACTION;
GO

BEGIN TRANSACTION;

-- 1. T* (Z), T*aT (T), TR (I)
UPDATE dbo.tblRifiutiOperazioni
SET IsFatturabile = IIF(Id IN ('Z', 'T', 'I'), 1, 0)
WHERE IsFatturabile IS NULL;

-- 2. Schede esistenti dei clienti: una fattura per cliente
UPDATE dbo.tblClientiFornitori
SET IdRaggruppamento = 'C'
WHERE
	Tipo = 'C'
	AND IdRaggruppamento IS NULL;

-- 3b. Importi rifiuti esistenti: l'azienda dell'importo
UPDATE r
SET IdSede = i.IdSede
FROM
	dbo.tblImportiRifiuti r
	INNER JOIN dbo.tblImporti i ON r.Id = i.Id
WHERE r.IdSede IS NULL;

-- Tipo di riga a litri: stesso stile di "KG (Kilogrammo)" e "T (Tonnellata)"
UPDATE dbo.tblImportiRigheTipi SET Nome = 'L (Litro)' WHERE Id = 'RL' AND Nome <> 'L (Litro)';

-- 6. Indici
-- Un importo sta in un solo contratto o offerta
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_OfferteContrattiImporti_IdImporto')
	CREATE UNIQUE NONCLUSTERED INDEX UX_OfferteContrattiImporti_IdImporto ON dbo.tblOfferteContrattiImporti (IdImporto);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Importi_IdSede')
	CREATE NONCLUSTERED INDEX IX_Importi_IdSede ON dbo.tblImporti (IdSede) INCLUDE (IdPriorita, Lock);

-- Importi rifiuti dell'azienda con le loro variabili: il confronto con ogni documento legge solo questi, non
-- le variabili degli importi di tutte le aziende
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiRifiuti_IdSede')
	CREATE NONCLUSTERED INDEX IX_ImportiRifiuti_IdSede ON dbo.tblImportiRifiuti (IdSede)
		INCLUDE (IdEer, IdProduttoreParent, IdProduttore, IdTrasportatore, IdDestinatario, IdIntermediario, IdEtichetta);

-- Righe dell'importo applicato, lette per ogni documento da ufnImportiRifiuti_get_RigheImporto: con le
-- colonne incluse non serve il lookup per riga. L'indice nato senza colonne incluse viene ricreato
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiRighe_IdImporto')
	AND NOT EXISTS (
		SELECT 1
		FROM
			sys.indexes i
			INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id
											AND i.index_id = ic.index_id
		WHERE
			i.name = 'IX_ImportiRighe_IdImporto'
			AND ic.is_included_column = 1
	)
	DROP INDEX IX_ImportiRighe_IdImporto ON dbo.tblImportiRighe;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ImportiRighe_IdImporto')
	CREATE NONCLUSTERED INDEX IX_ImportiRighe_IdImporto ON dbo.tblImportiRighe (IdImporto) INCLUDE (Pos, IdTipo, Importo, MinimoFatturabile, Lock);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_OfferteContratti_IdSede')
	CREATE NONCLUSTERED INDEX IX_OfferteContratti_IdSede ON dbo.tblOfferteContratti (IdSede) INCLUDE (IdClienteFornitore, Tipo, Lock);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FattureDocumenti_IdFattura')
	CREATE NONCLUSTERED INDEX IX_FattureDocumenti_IdFattura ON dbo.tblFattureDocumenti (IdFattura);

-- Chiavi esterne di tblFattureDocumenti: senza indice, cancellare la bozza di un importo, di un contratto o di
-- un cliente legge tutta la tabella, che cresce di una riga per ogni documento fatturato. Filtrati: le tre
-- colonne sono vuote finche' il documento non viene fatturato o non gli si indica un cliente
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FattureDocumenti_IdImporto')
	CREATE NONCLUSTERED INDEX IX_FattureDocumenti_IdImporto ON dbo.tblFattureDocumenti (IdImporto) WHERE IdImporto IS NOT NULL;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FattureDocumenti_IdOffertaContratto')
	CREATE NONCLUSTERED INDEX IX_FattureDocumenti_IdOffertaContratto ON dbo.tblFattureDocumenti (IdOffertaContratto) WHERE IdOffertaContratto IS NOT NULL;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FattureDocumenti_IdClienteFornitore')
	CREATE NONCLUSTERED INDEX IX_FattureDocumenti_IdClienteFornitore ON dbo.tblFattureDocumenti (IdClienteFornitore) WHERE IdClienteFornitore IS NOT NULL;

-- Contratti e offerte di un cliente: controllo di uspClientiFornitori_del e chiave esterna sul cliente
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_OfferteContratti_IdClienteFornitore')
	CREATE NONCLUSTERED INDEX IX_OfferteContratti_IdClienteFornitore ON dbo.tblOfferteContratti (IdClienteFornitore) INCLUDE (Lock);

-- 7. Modulo, area di menu, funzioni
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuli WHERE Id = 'OFC')
	INSERT INTO dbo.tblModuli (Id, Nome, Attivo) VALUES ('OFC', 'Offerte e contratti', 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagineAree WHERE Id = 'OFC')
	INSERT INTO dbo.tblPagineAree (Id, Nome, Icon) VALUES ('OFC', 'Offerte e contratti', 'fal fa-file-signature');

IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'OCC')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('OCC', 'Offerte e contratti', 0, 0, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblFunzioni WHERE Id = 'OCI')
	INSERT INTO dbo.tblFunzioni (Id, Nome, Master, Admin, Attiva) VALUES ('OCI', 'Importi', 0, 0, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'OFC' AND IdFunzione = 'OCC')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('OFC', 'OCC');

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliFunzioni WHERE Id = 'OFC' AND IdFunzione = 'OCI')
	INSERT INTO dbo.tblModuliFunzioni (Id, IdFunzione) VALUES ('OFC', 'OCI');

-- Dipendenze OFC -> FAT, ANX, ANA (uspDomini_ins_Modulo risolve un solo livello: vanno indicate tutte)
IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliRelazioni WHERE Id = 'FAT' AND IdParent = 'OFC')
	INSERT INTO dbo.tblModuliRelazioni (Id, IdParent) VALUES ('FAT', 'OFC');

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliRelazioni WHERE Id = 'ANX' AND IdParent = 'OFC')
	INSERT INTO dbo.tblModuliRelazioni (Id, IdParent) VALUES ('ANX', 'OFC');

IF NOT EXISTS (SELECT 1 FROM dbo.tblModuliRelazioni WHERE Id = 'ANA' AND IdParent = 'OFC')
	INSERT INTO dbo.tblModuliRelazioni (Id, IdParent) VALUES ('ANA', 'OFC');

-- Pagine: le voci Importi richiedono anche il modulo dei documenti a cui si applicano
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'OCK')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note, IdModulo) VALUES ('OCK', 'OCC', 'Contratti clienti', 'contratti-clienti', NULL, NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'OCO')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note, IdModulo) VALUES ('OCO', 'OCC', 'Offerte clienti', 'offerte-clienti', NULL, NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'OCR')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note, IdModulo) VALUES ('OCR', 'OCI', 'Importi rifiuti', 'importi-rifiuti', NULL, 'RIF');

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'OCM')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note, IdModulo) VALUES ('OCM', 'OCI', 'Importi magazzino', 'importi-magazzino', NULL, 'MAG');

IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'OCS')
	INSERT INTO dbo.tblPagine (Id, IdFunzione, Nome, Url, Note, IdModulo) VALUES ('OCS', 'OCI', 'Importi servizi', 'importi-servizi', NULL, 'SRV');

-- Menu: Offerte e contratti prima di Fatturazione; Fatturazione, Rentri e Impostazioni scendono di una posizione
IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AK0')
BEGIN
	UPDATE dbo.tblMenu SET Pos = 10 WHERE Id = 'AZ0' AND Pos = 9;
	UPDATE dbo.tblMenu SET Pos = 9 WHERE Id = 'AG0' AND Pos = 8;
	UPDATE dbo.tblMenu SET Pos = 8 WHERE Id = 'AJ0' AND Pos = 7;
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AK0', NULL, 'OFC', NULL, 7);
END

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AK1')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AK1', 'AK0', NULL, 'OCK', 0);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AK2')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AK2', 'AK0', NULL, 'OCO', 1);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AK3')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AK3', 'AK0', NULL, 'OCR', 2);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AK4')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AK4', 'AK0', NULL, 'OCM', 3);

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AK5')
	INSERT INTO dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos) VALUES ('AK5', 'AK0', NULL, 'OCS', 4);

COMMIT TRANSACTION;
GO

SELECT m.Id, m.Pos, Area = a.Nome
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagineAree a ON m.IdArea = a.Id
WHERE m.IdParent IS NULL
ORDER BY m.Pos;

SELECT m.Id, m.Pos, p.Nome, p.Url, p.IdFunzione, p.IdModulo
FROM
	dbo.tblMenu m
	INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
WHERE m.IdParent = 'AK0'
ORDER BY m.Pos;

SELECT Id, Codice, Nome, IsFatturabile FROM dbo.tblRifiutiOperazioni ORDER BY Pos;

SELECT Id, IdModulo, Nome, Pos FROM dbo.tblImportiRigheTipi ORDER BY IdModulo, Pos;

SELECT Id, IdParent FROM dbo.tblModuliRelazioni WHERE IdParent = 'OFC' ORDER BY Id;
GO
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

PRINT 'sql/functions/ufnImportiRifiuti_get_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Importi rifiuti dell'azienda interna corrente della sessione: righe comuni all'elenco
-- (uspImportiRifiuti_get_List) e all'esportazione (uspImportiRifiuti_get_Esportazione), così scope e
-- criteri di ricerca stanno in un posto solo. Senza azienda nel contesto nessuna riga.
-- Una variabile non indicata nell'importo (NULL) vale "qualsiasi".
-- @SoloContrattoScaduto = 1: solo gli importi di un contratto scaduto (collegamento del riquadro giallo della
-- procedura automatica di fatturazione e spunta della ricerca).
-- Contratto: al massimo uno per importo (UX_OfferteContrattiImporti_IdImporto); Tipo C contratto, O offerta.
CREATE OR ALTER FUNCTION dbo.ufnImportiRifiuti_get_List (
	@IdSessione CHAR(16),
	@Search VARCHAR(50),
	@SoloContrattoScaduto BIT)
RETURNS TABLE
AS
RETURN
(
	SELECT
		i.Id,
		StatoValore = CASE
			WHEN g.Righe IS NULL THEN 1
			WHEN c.Tipo = 'O' THEN 1
			WHEN c.DataFine < CAST(GETDATE() AS DATE) THEN 1
			ELSE 0
		END,
		StatoDescrizione = CASE
			WHEN g.Righe IS NULL THEN 'Importo senza righe: non genera righe in fattura'
			WHEN c.Tipo = 'O' THEN 'Importo di un''offerta: non viene applicato nella fatturazione'
			WHEN c.DataFine < CAST(GETDATE() AS DATE) THEN 'Contratto scaduto il ' + CONVERT(VARCHAR(10), c.DataFine, 103)
			ELSE 'OK'
		END,
		i.Nome,
		i.IdPriorita,
		Priorita = p.Nome,
		Eer = e.Nome + IIF(e.Pericoloso = 1, '*', ''),
		EerDescrizione = e.Descrizione,
		Produttore = IIF(r.IdProduttore IS NULL, pa.NomeCompleto, ps.NomeCompleto + ISNULL(' ' + ps.IndirizzoCompleto, '')),
		Trasportatore = tr.NomeCompleto + ISNULL(' ' + tr.IndirizzoCompleto, ''),
		Destinatario = de.NomeCompleto + ISNULL(' ' + de.IndirizzoCompleto, ''),
		Intermediario = im.NomeCompleto + ISNULL(' ' + im.IndirizzoCompleto, ''),
		Etichetta = et.Nome,
		c.Cliente,
		ContrattoTipo = c.Tipo,
		ContrattoDataInizio = c.DataInizio,
		ContrattoDataFine = c.DataFine,
		Righe = ISNULL(g.Righe, 0)
	FROM
		dbo.tblImporti i
		INNER JOIN dbo.tblSessioni s ON i.IdSede = s.IdAzienda
		INNER JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
		LEFT JOIN dbo.tblImportiPriorita p ON i.IdPriorita = p.Id
		LEFT JOIN dbo.tblRifiutiEer e ON r.IdEer = e.Id
		LEFT JOIN dbo.tblSedi pa ON r.IdProduttoreParent = pa.Id
		LEFT JOIN dbo.tblSedi ps ON r.IdProduttore = ps.Id
		LEFT JOIN dbo.tblSedi tr ON r.IdTrasportatore = tr.Id
		LEFT JOIN dbo.tblSedi de ON r.IdDestinatario = de.Id
		LEFT JOIN dbo.tblSedi im ON r.IdIntermediario = im.Id
		LEFT JOIN dbo.tblEtichette et ON r.IdEtichetta = et.Id
		OUTER APPLY (
			SELECT Righe = COUNT(*)
			FROM dbo.tblImportiRighe x
			WHERE x.IdImporto = i.Id
			HAVING COUNT(*) > 0
		) g
		OUTER APPLY (
			SELECT TOP (1)
				oc.Tipo,
				oc.Lock,
				oc.DataInizio,
				oc.DataFine,
				Cliente = cs.NomeCompleto
			FROM
				dbo.tblOfferteContrattiImporti ci
				INNER JOIN dbo.tblOfferteContratti oc ON ci.IdOffertaContratto = oc.Id
				LEFT JOIN dbo.tblClientiFornitori cf ON oc.IdClienteFornitore = cf.Id
				LEFT JOIN dbo.tblSedi cs ON cf.IdSede = cs.Id
			WHERE
				ci.IdImporto = i.Id
				AND oc.Lock <= 2
		) c
	WHERE
		s.Id = @IdSessione
		AND i.Lock = 0
		-- Solo gli importi di un contratto confermato la cui validità è finita prima di oggi
		AND
			(
			ISNULL(@SoloContrattoScaduto, 0) = 0
			OR (c.Tipo = 'C' AND c.Lock = 0 AND c.DataFine < CAST(GETDATE() AS DATE))
			)
		AND
			(
			@Search IS NULL
			OR i.Nome LIKE '%' + @Search + '%'
			OR e.Nome LIKE '%' + @Search + '%'
			OR pa.NomeCompleto LIKE '%' + @Search + '%'
			OR ps.NomeCompleto LIKE '%' + @Search + '%'
			OR tr.NomeCompleto LIKE '%' + @Search + '%'
			OR de.NomeCompleto LIKE '%' + @Search + '%'
			OR im.NomeCompleto LIKE '%' + @Search + '%'
			OR et.Nome LIKE '%' + @Search + '%'
			OR c.Cliente LIKE '%' + @Search + '%'
			)
);
GO
GO

PRINT 'sql/functions/ufnOfferteContratti_get_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Contratti (@Tipo = 'C') o offerte (@Tipo = 'O') dei clienti dell'azienda interna corrente della sessione: righe
-- comuni all'elenco (uspOfferteContratti_get_List) e all'esportazione (uspOfferteContratti_get_Esportazione),
-- così scope e criteri di ricerca stanno in un posto solo. Senza azienda nel contesto nessuna riga.
-- Stato (avviso, non blocco): scaduto, non ancora in vigore, senza importi.
CREATE OR ALTER FUNCTION dbo.ufnOfferteContratti_get_List (
	@IdSessione CHAR(16),
	@Tipo CHAR(1),
	@Search VARCHAR(50))
RETURNS TABLE
AS
RETURN
(
	SELECT
		oc.Id,
		StatoValore = CASE
			WHEN oc.DataFine < CAST(GETDATE() AS DATE) THEN 1
			WHEN oc.DataInizio > CAST(GETDATE() AS DATE) THEN 1
			WHEN g.Importi IS NULL THEN 1
			ELSE 0
		END,
		StatoDescrizione = CASE
			WHEN oc.DataFine < CAST(GETDATE() AS DATE) THEN IIF(oc.Tipo = 'O', 'Offerta scaduta il ', 'Contratto scaduto il ') + CONVERT(VARCHAR(10), oc.DataFine, 103)
			WHEN oc.DataInizio > CAST(GETDATE() AS DATE) THEN 'In vigore dal ' + CONVERT(VARCHAR(10), oc.DataInizio, 103)
			WHEN g.Importi IS NULL THEN IIF(oc.Tipo = 'O', 'Offerta senza importi', 'Contratto senza importi')
			ELSE 'In vigore'
		END,
		Cliente = cs.NomeCompleto,
		ClienteIndirizzo = cs.IndirizzoCompleto,
		ClientePartitaIva = cs.PartitaIva,
		ClienteCodiceFiscale = cs.CodiceFiscale,
		oc.Tipo,
		oc.DataInizio,
		oc.DataFine,
		oc.Descrizione,
		oc.Protocollo,
		oc.Ordine,
		oc.DataOrdine,
		oc.CodiceCig,
		oc.CodiceCup,
		Importi = ISNULL(g.Importi, 0)
	FROM
		dbo.tblOfferteContratti oc
		INNER JOIN dbo.tblSessioni s ON oc.IdSede = s.IdAzienda
		LEFT JOIN dbo.tblClientiFornitori cf ON oc.IdClienteFornitore = cf.Id
		LEFT JOIN dbo.tblSedi cs ON cf.IdSede = cs.Id
		OUTER APPLY (
			SELECT Importi = COUNT(*)
			FROM dbo.tblOfferteContrattiImporti ci
			WHERE ci.IdOffertaContratto = oc.Id
			HAVING COUNT(*) > 0
		) g
	WHERE
		s.Id = @IdSessione
		AND oc.Lock = 0
		AND oc.ClienteFornitoreTipo = 'C'
		AND oc.Tipo = @Tipo
		AND
			(
			@Search IS NULL
			OR cs.NomeCompleto LIKE '%' + @Search + '%'
			OR cs.PartitaIva LIKE '%' + @Search + '%'
			OR cs.CodiceFiscale LIKE '%' + @Search + '%'
			OR oc.Descrizione LIKE '%' + @Search + '%'
			OR oc.Protocollo LIKE '%' + @Search + '%'
			OR oc.Ordine LIKE '%' + @Search + '%'
			OR oc.CodiceCig LIKE '%' + @Search + '%'
			OR oc.CodiceCup LIKE '%' + @Search + '%'
			)
);
GO
GO

PRINT 'sql/functions/ufnImportiRifiuti_get_Coincidenti.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: importi rifiuti attivi dell'azienda le cui variabili coincidono con i valori indicati
-- (regole O5 di docs/regole/offerte-contratti.md). È l'unico punto in cui è scritta la regola di coincidenza:
-- la leggono la fatturazione (ufnImportiRifiuti_get_Applicazione_List) e la verifica degli importi.
-- Funzione in linea senza TOP né sottoquery: applicata a più documenti diventa un join, e gli importi
-- dell'azienda si leggono una volta sola. Per questo non va aggiunto qui nulla che dipenda dal documento
-- oltre ai confronti delle variabili.
--
-- Coincidenza: tutte le variabili indicate nell'importo coincidono con i valori (una variabile NULL vale
-- "qualsiasi").
-- ETICHETTA: qui non viene verificata. IdEtichetta è quella indicata nell'importo (NULL = qualsiasi): chi
-- chiama scarta l'importo se la indica e il documento non ce l'ha tra le sue.
-- Classe:
--   V  candidato: importo standard (non associato a un contratto o a un'offerta), oppure importo di un
--      contratto attivo di un cliente con @Data compresa tra inizio e fine;
--   S  scartato: importo di un contratto attivo di un cliente non valido alla data (avviso "contratto scaduto");
--   X  mai candidato: importo di un'offerta o di un contratto cancellato.
-- Ordine di scelta tra i candidati: IdPriorita DESC, Standard (prima quello di un contratto), IdImporto.
CREATE OR ALTER FUNCTION dbo.ufnImportiRifiuti_get_Coincidenti (
	@IdAzienda CHAR(16),
	@Data DATE,
	@IdEer CHAR(6),
	@IdProduttoreParent CHAR(16),
	@IdProduttore CHAR(16),
	@IdTrasportatore CHAR(16),
	@IdDestinatario CHAR(16),
	@IdIntermediario CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		IdImporto = i.Id,
		i.IdPriorita,
		ir.IdEtichetta,
		IdOffertaContratto = oc.Id,
		IdClienteContratto = oc.IdClienteFornitore,
		Standard = CAST(IIF(ci.IdImporto IS NULL, 1, 0) AS BIT),
		Classe = CAST(CASE
			WHEN ci.IdImporto IS NULL THEN 'V'
			WHEN oc.Lock = 0 AND oc.Tipo = 'C' AND oc.ClienteFornitoreTipo = 'C' AND @Data BETWEEN oc.DataInizio AND oc.DataFine THEN 'V'
			WHEN oc.Lock = 0 AND oc.Tipo = 'C' AND oc.ClienteFornitoreTipo = 'C' AND NOT (@Data BETWEEN oc.DataInizio AND oc.DataFine) THEN 'S'
			ELSE 'X'
		END AS CHAR(1))
	FROM
		dbo.tblImportiRifiuti ir
		INNER JOIN dbo.tblImporti i ON ir.Id = i.Id
		LEFT JOIN dbo.tblOfferteContrattiImporti ci ON i.Id = ci.IdImporto
		-- FORCESEEK: il contratto si legge per chiave. Senza, applicata a molti documenti la funzione può finire
		-- a leggere tutti i contratti per ogni documento (misurato: 6 milioni di righe per 3.780 documenti)
		LEFT JOIN dbo.tblOfferteContratti oc WITH (FORCESEEK) ON ci.IdOffertaContratto = oc.Id
	WHERE
		-- Azienda: quella copiata sulle variabili (tblImportiRifiuti.IdSede), per leggere con un solo accesso
		-- gli importi dell'azienda senza passare da quelli di tutte le altre
		ir.IdSede = @IdAzienda
		AND i.Lock = 0
		AND (ir.IdEer IS NULL OR ir.IdEer = @IdEer)
		AND (ir.IdProduttoreParent IS NULL OR ir.IdProduttoreParent = @IdProduttoreParent)
		AND (ir.IdProduttore IS NULL OR ir.IdProduttore = @IdProduttore)
		AND (ir.IdTrasportatore IS NULL OR ir.IdTrasportatore = @IdTrasportatore)
		AND (ir.IdDestinatario IS NULL OR ir.IdDestinatario = @IdDestinatario)
		AND (ir.IdIntermediario IS NULL OR ir.IdIntermediario = @IdIntermediario)
);
GO
GO

PRINT 'sql/functions/ufnImportiRifiuti_get_Applicazione_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: importo e cliente che la fatturazione applica alle registrazioni dei rifiuti
-- (regole O5 di docs/regole/offerte-contratti.md). Una riga per registrazione, anche se nessun importo
-- coincide (IdImporto NULL).
--   @Id: una sola registrazione; altrimenti le registrazioni dei registri dell'azienda @IdAzienda con la data
--        tra @DataDa e @DataA.
--   @SoloFatturabili = 1: solo le registrazioni confermate (Lock = 0) di un'operazione fatturabile, non
--        rettifiche; il confronto con gli importi non viene fatto per le altre.
-- Il confronto è a insiemi: gli importi dell'azienda si leggono una volta e si incrociano con tutte le
-- registrazioni richieste (ufnImportiRifiuti_get_Coincidenti), invece di una ricerca per registrazione.
-- Chi la chiama con parametri variabili usa OPTION (RECOMPILE); per una sola registrazione c'è
-- ufnImportiRifiuti_get_Applicazione.
--
-- Importo: tra gli importi rifiuti attivi dell'azienda del registro, il primo le cui variabili indicate
-- coincidono tutte con la registrazione (una variabile NULL vale "qualsiasi"), in ordine di priorità
-- decrescente e, a parità di priorità, prima quello di un contratto e poi quello standard.
--   - Importo standard (non associato a un contratto o a un'offerta): sempre candidato.
--   - Importo di un contratto: candidato solo se il contratto è attivo, di un cliente, e la data della
--     registrazione è compresa tra inizio e fine.
--   - Il cliente indicato sulla registrazione NON entra nella scelta dell'importo: cambia solo l'intestatario
--     della fattura. La registrazione può essere fatturata, per esempio, all'intermediario con l'importo e le
--     condizioni del contratto di un altro cliente.
--   - Importo di un'offerta: mai candidato.
-- Valori della registrazione: quelli OPERATIVI (viewRifiutiRegistrazioniEffettive: EER, unità di misura e
-- quantità dopo le rettifiche); soggetti ed etichette sono quelli della registrazione.
--
-- Cliente (ClienteOrigine): D quello indicato sulla registrazione (tblFattureDocumenti), altrimenti C quello del
-- contratto dell'importo applicato, altrimenti P la scheda cliente attiva del soggetto produttore (per un
-- importo standard). NULL se nessuno dei tre.
-- IdImportoScartato: importo di un contratto che coinciderebbe con la registrazione ma il cui contratto non è
-- valido alla data della registrazione (serve all'avviso "contratto scaduto").
-- IdFattura: solo se la fattura non è cancellata (cancellata la fattura, la registrazione torna fatturabile).
-- IsPreFattura, IdClientePreFattura: il documento è in una pre-fattura (TD00), intestata a quel cliente; la
-- generazione può riprenderla e convertirla in fattura (uspFatture_ins_Genera, @IncludiPreFatture).
CREATE OR ALTER FUNCTION dbo.ufnImportiRifiuti_get_Applicazione_List (
	@Id CHAR(16),
	@IdAzienda CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@SoloFatturabili BIT)
RETURNS TABLE
AS
RETURN
(
	WITH ids AS (
		-- Due rami distinti, ciascuno con il suo accesso: la registrazione @Id per chiave, oppure quelle
		-- dell'azienda nel periodo (un solo WHERE con OR farebbe leggere tutte le registrazioni anche per una sola)
		SELECT r.Id
		FROM dbo.tblRifiutiRegistrazioni r
		WHERE r.Id = @Id

		UNION ALL

		SELECT r.Id
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi sr ON g.IdSede = sr.Id
		WHERE
			@Id IS NULL
			AND sr.IdAziendaInterna = @IdAzienda
			AND r.[Data] >= @DataDa
			AND r.[Data] <= @DataA
	),
	doc AS (
		SELECT
			r.Id,
			r.[Data],
			r.Numero,
			r.Lock,
			IdSedeRegistro = g.IdSede,
			IdAzienda = sr.IdAziendaInterna,
			m.IdOperazione,
			IsFatturabile = CAST(ISNULL(o.IsFatturabile, 0) AS BIT),
			v.IdEer,
			v.IdUnitaMisura,
			v.Quantita,
			v.IsRettifica,
			v.IsAnnullata,
			IdProduttore = m.IdSedeProduttoreDetentore,
			IdProduttoreParent = ISNULL(sp.IdParent, sp.Id),
			IdTrasportatore = m.IdSedeTrasportatore1,
			IdDestinatario = m.IdSedeDestinatario,
			IdIntermediario = m.IdSedeIntermediario1,
			m.FormularioNumero,
			IdClienteIndicato = d.IdClienteFornitore,
			NonFatturabile = CAST(ISNULL(d.NonFatturabile, 0) AS BIT),
			IdFattura = f.Id,
			IsPreFattura = CAST(IIF(f.IdTipo = 'TD00', 1, 0) AS BIT),
			IdClientePreFattura = IIF(f.IdTipo = 'TD00', f.IdClienteFornitore, NULL)
		FROM
			ids k
			INNER JOIN dbo.tblRifiutiRegistrazioni r ON k.Id = r.Id
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi sr ON g.IdSede = sr.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			LEFT JOIN dbo.tblSedi sp ON m.IdSedeProduttoreDetentore = sp.Id
			LEFT JOIN dbo.tblFattureDocumenti d ON r.Id = d.Id
			LEFT JOIN dbo.tblFatture f ON d.IdFattura = f.Id
									  AND f.Lock IN (0, 2)
		WHERE
			ISNULL(@SoloFatturabili, 0) = 0
			OR
			(
				r.Lock = 0
				AND o.IsFatturabile = 1
				AND v.IsRettifica = 0
			)
	),
	scelta AS (
		-- Per ogni registrazione gli importi che coincidono: N = 1 è il primo candidato (classe V) in ordine di
		-- scelta, o una riga senza candidato; IdImportoScartato il primo degli scartati (classe S). Un importo che
		-- indica un'etichetta che la registrazione non ha non coincide: passa alla classe X
		SELECT
			doc.Id,
			doc.[Data],
			doc.Numero,
			doc.Lock,
			doc.IdSedeRegistro,
			doc.IdAzienda,
			doc.IdOperazione,
			doc.IsFatturabile,
			doc.IdEer,
			doc.IdUnitaMisura,
			doc.Quantita,
			doc.IsRettifica,
			doc.IsAnnullata,
			doc.IdProduttore,
			doc.IdProduttoreParent,
			doc.IdTrasportatore,
			doc.IdDestinatario,
			doc.IdIntermediario,
			doc.FormularioNumero,
			doc.IdClienteIndicato,
			doc.NonFatturabile,
			doc.IdFattura,
			doc.IsPreFattura,
			doc.IdClientePreFattura,
			IdImporto = IIF(q.Classe = 'V', c.IdImporto, NULL),
			IdOffertaContratto = IIF(q.Classe = 'V', c.IdOffertaContratto, NULL),
			IdClienteContratto = IIF(q.Classe = 'V', c.IdClienteContratto, NULL),
			IdImportoScartato = FIRST_VALUE(IIF(q.Classe = 'S', c.IdImporto, NULL)) OVER (
				PARTITION BY doc.Id
				ORDER BY IIF(q.Classe = 'S', 0, 1), c.IdPriorita DESC, c.IdImporto
				ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
			N = ROW_NUMBER() OVER (
				PARTITION BY doc.Id
				ORDER BY IIF(q.Classe = 'V', 0, 1), c.IdPriorita DESC, c.Standard, c.IdImporto)
		FROM
			doc
			OUTER APPLY dbo.ufnImportiRifiuti_get_Coincidenti(doc.IdAzienda, doc.[Data], doc.IdEer, doc.IdProduttoreParent, doc.IdProduttore,
				doc.IdTrasportatore, doc.IdDestinatario, doc.IdIntermediario) c
			-- Al massimo una riga: (Id, IdEtichetta) è la chiave primaria
			LEFT JOIN dbo.tblRifiutiRegistrazioniEtichette e ON e.Id = doc.Id
															 AND e.IdEtichetta = c.IdEtichetta
			CROSS APPLY (SELECT Classe = IIF(c.IdEtichetta IS NOT NULL AND e.Id IS NULL, 'X', c.Classe)) q
	)
	SELECT
		t.Id,
		t.[Data],
		t.Numero,
		t.Lock,
		t.IdSedeRegistro,
		t.IdAzienda,
		t.IdOperazione,
		t.IsFatturabile,
		t.IdEer,
		t.IdUnitaMisura,
		t.Quantita,
		t.IsRettifica,
		t.IsAnnullata,
		t.IdProduttore,
		t.IdProduttoreParent,
		t.IdTrasportatore,
		t.IdDestinatario,
		t.IdIntermediario,
		t.FormularioNumero,
		t.IdClienteIndicato,
		t.NonFatturabile,
		t.IdFattura,
		t.IsPreFattura,
		t.IdClientePreFattura,
		t.IdImporto,
		t.IdOffertaContratto,
		IdClienteFornitore = COALESCE(t.IdClienteIndicato, t.IdClienteContratto, cp.Id),
		ClienteOrigine = CAST(CASE
			WHEN t.IdClienteIndicato IS NOT NULL THEN 'D'
			WHEN t.IdClienteContratto IS NOT NULL THEN 'C'
			WHEN cp.Id IS NOT NULL THEN 'P'
		END AS CHAR(1)),
		t.IdImportoScartato
	FROM
		scelta t
		OUTER APPLY (
			SELECT TOP (1) c.Id
			FROM dbo.tblClientiFornitori c
			WHERE
				c.IdSede = t.IdProduttoreParent
				AND c.IdAziendaInterna = t.IdAzienda
				AND c.Tipo = 'C'
				AND c.Lock = 0
			ORDER BY c.Id
		) cp
	WHERE t.N = 1
);
GO
GO

PRINT 'sql/functions/ufnImportiRifiuti_get_Applicazione.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: importo e cliente che la fatturazione applica a una registrazione dei rifiuti
-- (regole O5 di docs/regole/offerte-contratti.md). Una riga per la registrazione @Id, anche se nessun importo
-- coincide (IdImporto NULL).
-- È ufnImportiRifiuti_get_Applicazione_List per una sola registrazione, senza il filtro sulle fatturabili: la
-- regola e il significato delle colonne sono descritti lì. Per più registrazioni usare quella, non questa con
-- CROSS APPLY (il confronto verrebbe rifatto per ogni registrazione).
CREATE OR ALTER FUNCTION dbo.ufnImportiRifiuti_get_Applicazione (
	@Id CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		a.Id,
		a.[Data],
		a.Numero,
		a.Lock,
		a.IdSedeRegistro,
		a.IdAzienda,
		a.IdOperazione,
		a.IsFatturabile,
		a.IdEer,
		a.IdUnitaMisura,
		a.Quantita,
		a.IsRettifica,
		a.IsAnnullata,
		a.IdProduttore,
		a.IdProduttoreParent,
		a.IdTrasportatore,
		a.IdDestinatario,
		a.IdIntermediario,
		a.FormularioNumero,
		a.IdClienteIndicato,
		a.NonFatturabile,
		a.IdFattura,
		a.IsPreFattura,
		a.IdClientePreFattura,
		a.IdImporto,
		a.IdOffertaContratto,
		a.IdClienteFornitore,
		a.ClienteOrigine,
		a.IdImportoScartato
	FROM dbo.ufnImportiRifiuti_get_Applicazione_List(@Id, NULL, NULL, NULL, 0) a
);
GO
GO

PRINT 'sql/functions/ufnImportiRifiuti_get_RigheImporto.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: righe di fattura che l'importo @IdImporto genera per la registrazione dei rifiuti @Id,
-- nell'ordine delle righe dell'importo. Importo e cliente sono quelli già determinati dal confronto
-- (ufnImportiRifiuti_get_Applicazione_List): qui non lo si rifà. Funzione in linea: si può usare con CROSS APPLY
-- su più registrazioni. Nessuna riga se @IdImporto è NULL.
--
-- Quantità secondo il tipo della riga: RM una per registrazione (unità NR); RK i chilogrammi e RT le tonnellate
-- (chilogrammi / 1000), solo per le registrazioni in chilogrammi; RL i litri, solo per le registrazioni in
-- litri. Una riga a quantità che non vale per l'unità della registrazione non entra. La quantità è quella
-- operativa della registrazione (dopo le rettifiche).
-- Riga di sola descrizione (importo NULL): entra sempre, senza quantità né importo.
-- Minimo fatturabile (al massimo una riga per importo): il suo importo è il minimo da fatturare per la
-- registrazione. Si confronta con la somma degli imponibili delle altre righe (se la riga del minimo è di tipo
-- RM, di tutte; altrimenti di quelle a quantità, senza le righe RM): se il minimo è maggiore la riga entra con
-- quantità 1 e importo pari alla differenza, altrimenti non entra.
-- Testo: i segnaposto #1 codice EER, #2 numero del formulario, #3 data del formulario, #4 produttore,
-- #5 destinatario vengono sostituiti con i dati della registrazione.
-- Aliquota IVA: quella della riga dell'importo, altrimenti quella della scheda del cliente @IdClienteFornitore.
CREATE OR ALTER FUNCTION dbo.ufnImportiRifiuti_get_RigheImporto (
	@Id CHAR(16),
	@IdImporto CHAR(16),
	@IdClienteFornitore CHAR(16))
RETURNS TABLE
AS
RETURN
(
	WITH a AS (
		SELECT
			r.Id,
			IdImporto = @IdImporto,
			v.IdUnitaMisura,
			v.Quantita,
			IdAliquotaIvaCliente = c.IdAliquotaIva,
			Eer = e.Nome + IIF(e.Pericoloso = 1, '*', ''),
			m.FormularioNumero,
			FormularioData = CONVERT(VARCHAR(10), fo.DataEmissione, 103),
			Produttore = sp.NomeCompleto + ISNULL(' ' + sp.IndirizzoCompleto, ''),
			Destinatario = sd.NomeCompleto + ISNULL(' ' + sd.IndirizzoCompleto, '')
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			LEFT JOIN dbo.tblClientiFornitori c ON c.Id = @IdClienteFornitore
			LEFT JOIN dbo.tblRifiutiEer e ON v.IdEer = e.Id
			LEFT JOIN dbo.tblRifiutiFormulari fo ON r.IdMovimento = fo.IdMovimento
												 AND fo.Lock < 2
			LEFT JOIN dbo.tblSedi sp ON m.IdSedeProduttoreDetentore = sp.Id
			LEFT JOIN dbo.tblSedi sd ON m.IdSedeDestinatario = sd.Id
		WHERE
			r.Id = @Id
			AND @IdImporto IS NOT NULL
	),
	righe AS (
		SELECT
			g.Id,
			g.Pos,
			g.IdTipo,
			MinimoFatturabile = CAST(ISNULL(g.MinimoFatturabile, 0) AS BIT),
			Prezzo = g.Importo,
			Quantita = CAST(CASE
				WHEN g.Importo IS NULL THEN NULL
				WHEN g.IdTipo = 'RM' THEN 1
				WHEN g.IdTipo = 'RK' AND a.IdUnitaMisura = 'KG' THEN a.Quantita
				WHEN g.IdTipo = 'RT' AND a.IdUnitaMisura = 'KG' THEN a.Quantita / 1000.0
				WHEN g.IdTipo = 'RL' AND a.IdUnitaMisura = 'LT' THEN a.Quantita
			END AS DECIMAL(18, 4)),
			IdUnitaMisura = CAST(CASE
				WHEN g.Importo IS NULL THEN NULL
				WHEN g.IdTipo = 'RM' THEN 'NR'
				WHEN g.IdTipo = 'RK' THEN 'KG'
				WHEN g.IdTipo = 'RT' THEN 'TN'
				WHEN g.IdTipo = 'RL' THEN 'LT'
			END AS CHAR(2)),
			Descrizione = CAST(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(d.Descrizione, ''),
				'#1', ISNULL(a.Eer, '')),
				'#2', ISNULL(a.FormularioNumero, '')),
				'#3', ISNULL(a.FormularioData, '')),
				'#4', ISNULL(a.Produttore, '')),
				'#5', ISNULL(a.Destinatario, '')) AS VARCHAR(1000)),
			IdAliquotaIva = ISNULL(d.IdAliquotaIva, a.IdAliquotaIvaCliente),
			d.IdConto
		FROM
			a
			INNER JOIN dbo.tblImportiRighe g ON a.IdImporto = g.IdImporto
			LEFT JOIN dbo.tblImportiRigheDettagli d ON g.Id = d.Id
	),
	minimo AS (
		-- Somma degli imponibili delle righe con cui si confronta il minimo fatturabile
		SELECT
			Altre = ISNULL((
				SELECT SUM(ROUND(x.Prezzo * x.Quantita, 2))
				FROM righe x
				WHERE
					x.MinimoFatturabile = 0
					AND x.Quantita IS NOT NULL
					AND (m.IdTipo = 'RM' OR x.IdTipo <> 'RM')
			), 0)
		FROM righe m
		WHERE
			m.MinimoFatturabile = 1
			AND m.Prezzo IS NOT NULL
	)
	SELECT
		t.Id,
		t.Pos,
		t.IdTipo,
		t.MinimoFatturabile,
		SolaDescrizione = CAST(IIF(t.Prezzo IS NULL, 1, 0) AS BIT),
		t.Descrizione,
		Quantita = CAST(IIF(t.MinimoFatturabile = 1, 1, t.Quantita) AS DECIMAL(18, 4)),
		IdUnitaMisura = CAST(IIF(t.MinimoFatturabile = 1, 'NR', t.IdUnitaMisura) AS CHAR(2)),
		Importo = CAST(IIF(t.MinimoFatturabile = 1, t.Prezzo - n.Altre, t.Prezzo) AS DECIMAL(18, 4)),
		Imponibile = CAST(ROUND(IIF(t.MinimoFatturabile = 1, t.Prezzo - n.Altre, t.Prezzo * t.Quantita), 2) AS DECIMAL(18, 2)),
		t.IdAliquotaIva,
		t.IdConto
	FROM
		righe t
		LEFT JOIN minimo n ON t.MinimoFatturabile = 1
	WHERE
		-- Sola descrizione: sempre
		t.Prezzo IS NULL
		-- Riga normale: solo se ha una quantità per l'unità della registrazione
		OR (t.MinimoFatturabile = 0 AND t.Quantita IS NOT NULL)
		-- Minimo fatturabile: solo per la differenza non raggiunta dalle altre righe
		OR (t.MinimoFatturabile = 1 AND t.Prezzo > n.Altre)
);
GO
GO

PRINT 'sql/functions/ufnImportiRifiuti_get_ApplicazioneRighe.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti: righe di fattura che l'importo applicato a una registrazione dei rifiuti
-- (ufnImportiRifiuti_get_Applicazione) genera per quella registrazione, nell'ordine delle righe dell'importo.
-- Per una sola registrazione: determina importo e cliente e ne legge le righe con
-- ufnImportiRifiuti_get_RigheImporto, dove sono descritte le regole (quantità, sola descrizione, minimo
-- fatturabile, segnaposto, aliquota IVA). Chi ha già importo e cliente di più registrazioni usa direttamente
-- quella, senza rifare il confronto.
CREATE OR ALTER FUNCTION dbo.ufnImportiRifiuti_get_ApplicazioneRighe (
	@Id CHAR(16))
RETURNS TABLE
AS
RETURN
(
	SELECT
		g.Id,
		g.Pos,
		g.IdTipo,
		g.MinimoFatturabile,
		g.SolaDescrizione,
		g.Descrizione,
		g.Quantita,
		g.IdUnitaMisura,
		g.Importo,
		g.Imponibile,
		g.IdAliquotaIva,
		g.IdConto
	FROM
		dbo.ufnImportiRifiuti_get_Applicazione(@Id) x
		CROSS APPLY dbo.ufnImportiRifiuti_get_RigheImporto(x.Id, x.IdImporto, x.IdClienteFornitore) g
);
GO
GO

PRINT 'sql/functions/ufnFattureDocumenti_get_Rifiuti.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Generazione automatica delle fatture: registrazioni dei rifiuti candidate, con l'importo e il cliente che
-- verrebbero applicati (ufnImportiRifiuti_get_Applicazione_List: il confronto con gli importi è fatto una volta
-- per tutte le registrazioni; le righe si leggono con ufnImportiRifiuti_get_RigheImporto) e l'esito. Serve sia alla verifica
-- (uspFatture_get_Genera_List) sia alla generazione (uspFatture_ins_Genera), così leggono le stesse righe.
--   @Id: una sola registrazione ("Genera la fattura" dalla scheda); altrimenti @IdAzienda e l'intervallo di date.
--   @IdClienteFornitore: solo i documenti riconducibili a quel cliente (quelli che gli verrebbero fatturati).
--   @IncludiPreFatture = 1: rientrano anche i documenti già in una pre-fattura (IdPreFattura), che verrà
--        convertita: in fattura vanno le righe della pre-fattura, non quelle ricalcolate dagli importi, e il
--        cliente è quello della pre-fattura.
-- Candidate: registrazioni confermate (Lock = 0) di un'operazione fatturabile, non rettifiche, di un registro
-- di una sede che la sessione vede (titolarità), non ancora in una fattura (le pre-fatture non contano come
-- fattura quando si includono).
-- Fatturabile = 1: non annullata, non "Non fatturabile", con un importo che coincide, un
-- cliente determinato, almeno una riga e l'aliquota IVA su ogni riga con importo (della riga o della scheda del
-- cliente). Stessa condizione di uspFattureDocumenti_get ("Verifica importo e
-- cliente" sulla scheda): vanno tenute allineate. Un documento in una pre-fattura inclusa è sempre fatturabile.
CREATE OR ALTER FUNCTION dbo.ufnFattureDocumenti_get_Rifiuti (
	@IdSessione CHAR(16),
	@IdAzienda CHAR(16),
	@Id CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@IdClienteFornitore CHAR(16),
	@IncludiPreFatture BIT)
RETURNS TABLE
AS
RETURN
(
	SELECT
		a.Id,
		a.[Data],
		a.Numero,
		a.IdAzienda,
		a.IdProduttore,
		a.IdEer,
		a.IdUnitaMisura,
		a.Quantita,
		a.IsAnnullata,
		a.NonFatturabile,
		IdPreFattura = IIF(a.IsPreFattura = 1, a.IdFattura, NULL),
		a.IdImporto,
		a.IdOffertaContratto,
		IdClienteFornitore = IIF(a.IsPreFattura = 1, a.IdClientePreFattura, a.IdClienteFornitore),
		a.ClienteOrigine,
		a.IdImportoScartato,
		Righe = ISNULL(t.Righe, 0),
		Totale = t.Totale,
		SenzaIva = ISNULL(t.SenzaIva, 0),
		Fatturabile = CAST(CASE
			WHEN a.IsPreFattura = 1 THEN 1
			WHEN a.IsAnnullata = 0 AND a.NonFatturabile = 0
				AND a.IdImporto IS NOT NULL AND a.IdClienteFornitore IS NOT NULL AND ISNULL(t.Righe, 0) > 0 AND ISNULL(t.SenzaIva, 0) = 0 THEN 1
			ELSE 0
		END AS BIT)
	FROM
		-- Registrazioni confermate di un'operazione fatturabile, non rettifiche, di @Id o dell'azienda nel
		-- periodo, con l'importo e il cliente applicati: il confronto è fatto una volta per tutte
		dbo.ufnImportiRifiuti_get_Applicazione_List(@Id, @IdAzienda, @DataDa, @DataA, 1) a
		INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeRegistro = x.Id
		OUTER APPLY (
			SELECT
				Totale = SUM(ISNULL(q.Imponibile, 0)),
				Righe = COUNT(*),
				SenzaIva = SUM(IIF(q.SolaDescrizione = 0 AND q.IdAliquotaIva IS NULL, 1, 0))
			FROM dbo.ufnImportiRifiuti_get_RigheImporto(a.Id, a.IdImporto, a.IdClienteFornitore) q
		) t
	WHERE
		-- Non ancora in una fattura; in una pre-fattura solo se si includono
			(
			a.IdFattura IS NULL
			OR (a.IsPreFattura = 1 AND @IncludiPreFatture = 1)
			)
		AND
			(
			@IdClienteFornitore IS NULL
			OR IIF(a.IsPreFattura = 1, a.IdClientePreFattura, a.IdClienteFornitore) = @IdClienteFornitore
			)
);
GO
GO

PRINT 'sql/functions/ufnFattureGenera_get_Documenti.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Generazione automatica delle fatture: i documenti candidati (ufnFattureDocumenti_get_Rifiuti, stessi parametri;
-- per ora le sole registrazioni dei rifiuti) con in più ciò che serve a raggrupparli in fatture e a riepilogarli.
-- La leggono il riepilogo (uspFatture_get_Genera_Riepilogo), l'anteprima delle fatture
-- (uspFatture_get_Genera_Fatture_List), l'elenco di dettaglio (uspFatture_get_Genera_List) e la generazione
-- (uspFatture_ins_Genera): così contano, mostrano e generano le stesse cose.
--   GruppoSede, GruppoContratto: con il cliente dicono in quale fattura va il documento, secondo il
--        raggruppamento della scheda del cliente (tblClientiFornitori.IdRaggruppamento): S una fattura per sede
--        del produttore, T una per contratto, altrimenti una per cliente (entrambi NULL). I documenti di una
--        stessa pre-fattura restano insieme: prendono il gruppo del suo primo documento (data, numero).
--   PrimoDellaPreFattura: il primo documento della sua pre-fattura, che ne porta le righe e l'imponibile.
--   Imponibile: quello delle righe dell'importo applicato; per una pre-fattura il suo imponibile, una volta
--        sola, sul primo documento (NULL sugli altri).
--   Esito: F fatturabile; S fatturabile con l'importo standard perché il contratto non è valido alla data;
--        P in una pre-fattura che verrà convertita; A annullata; N indicata come non fatturabile; I nessun
--        importo coincide; C cliente non determinato; R l'importo non ha righe applicabili; V manca
--        l'aliquota IVA. F, S e P entrano in una fattura (Fatturabile = 1).
CREATE OR ALTER FUNCTION dbo.ufnFattureGenera_get_Documenti (
	@IdSessione CHAR(16),
	@IdAzienda CHAR(16),
	@Id CHAR(16),
	@DataDa DATE,
	@DataA DATE,
	@IdClienteFornitore CHAR(16),
	@IncludiPreFatture BIT)
RETURNS TABLE
AS
RETURN
(
	SELECT
		t.Id,
		t.[Data],
		t.Numero,
		t.IdAzienda,
		t.IdProduttore,
		t.IdEer,
		t.IdUnitaMisura,
		t.Quantita,
		t.IsAnnullata,
		t.NonFatturabile,
		t.IdPreFattura,
		t.IdImporto,
		t.IdOffertaContratto,
		t.IdClienteFornitore,
		t.ClienteOrigine,
		t.IdImportoScartato,
		t.Righe,
		t.Totale,
		t.SenzaIva,
		t.Fatturabile,
		PrimoDellaPreFattura = CAST(IIF(t.IdPreFattura IS NOT NULL AND t.N = 1, 1, 0) AS BIT),
		GruppoSede = IIF(t.IdPreFattura IS NULL, t.GruppoSedeProprio,
			FIRST_VALUE(t.GruppoSedeProprio) OVER (PARTITION BY t.IdPreFattura ORDER BY t.[Data], t.Numero, t.Id)),
		GruppoContratto = IIF(t.IdPreFattura IS NULL, t.GruppoContrattoProprio,
			FIRST_VALUE(t.GruppoContrattoProprio) OVER (PARTITION BY t.IdPreFattura ORDER BY t.[Data], t.Numero, t.Id)),
		Imponibile = CASE
			WHEN t.IdPreFattura IS NULL THEN t.Totale
			WHEN t.N = 1 THEN pf.Imponibile
		END,
		Esito = CAST(CASE
			WHEN t.IdPreFattura IS NOT NULL THEN 'P'
			WHEN t.Fatturabile = 1 AND t.IdImportoScartato IS NOT NULL AND t.IdOffertaContratto IS NULL THEN 'S'
			WHEN t.Fatturabile = 1 THEN 'F'
			WHEN t.IsAnnullata = 1 THEN 'A'
			WHEN t.NonFatturabile = 1 THEN 'N'
			WHEN t.IdImporto IS NULL THEN 'I'
			WHEN t.IdClienteFornitore IS NULL THEN 'C'
			WHEN t.Righe = 0 THEN 'R'
			ELSE 'V'
		END AS CHAR(1))
	FROM
		(
			SELECT
				d.Id,
				d.[Data],
				d.Numero,
				d.IdAzienda,
				d.IdProduttore,
				d.IdEer,
				d.IdUnitaMisura,
				d.Quantita,
				d.IsAnnullata,
				d.NonFatturabile,
				d.IdPreFattura,
				d.IdImporto,
				d.IdOffertaContratto,
				d.IdClienteFornitore,
				d.ClienteOrigine,
				d.IdImportoScartato,
				d.Righe,
				d.Totale,
				d.SenzaIva,
				d.Fatturabile,
				GruppoSedeProprio = IIF(c.IdRaggruppamento = 'S', d.IdProduttore, NULL),
				GruppoContrattoProprio = IIF(c.IdRaggruppamento = 'T', d.IdOffertaContratto, NULL),
				-- Posizione del documento nella sua pre-fattura (conta solo dove IdPreFattura non è NULL)
				N = ROW_NUMBER() OVER (PARTITION BY d.IdPreFattura ORDER BY d.[Data], d.Numero, d.Id)
			FROM
				dbo.ufnFattureDocumenti_get_Rifiuti(@IdSessione, @IdAzienda, @Id, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture) d
				LEFT JOIN dbo.tblClientiFornitori c ON d.IdClienteFornitore = c.Id
		) t
		OUTER APPLY dbo.ufnFatture_get_Totali(IIF(t.N = 1, t.IdPreFattura, NULL)) pf
);
GO
GO

PRINT 'sql/procedures/uspImporti_get_Priorita_SelectList.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select delle priorità di un importo, dalla più alta alla più bassa (dato di riferimento: tblImportiPriorita).
-- A parità di variabili coincidenti con il documento da fatturare vince l'importo con la priorità più alta.
CREATE OR ALTER PROCEDURE dbo.uspImporti_get_Priorita_SelectList
	@IdSelected INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SELECT
			Id = CAST(p.Id AS VARCHAR(10)),
			[Text] = p.Nome,
			Selected = CAST(IIF(p.Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblImportiPriorita p
		ORDER BY p.Id DESC;

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
GO

PRINT 'sql/procedures/uspImporti_del.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Cancella un importo (rifiuti, magazzino o servizi) dell'azienda interna corrente della sessione.
-- Importo attivo: cancellazione con ripristino (Lock 4), le righe restano sull'importo cancellato. Bloccata se
-- l'importo è associato a un contratto o a un'offerta: va prima tolto da lì.
-- Importo in bozza: eliminato con le sue righe.
CREATE OR ALTER PROCEDURE dbo.uspImporti_del
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
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblImporti WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità) e che il modulo dell'importo sia attivo sul dominio
		DECLARE @lock INT;
		DECLARE @idModulo CHAR(3);
		SELECT
			@lock = i.Lock,
			@idModulo = CASE
				WHEN r.Id IS NOT NULL THEN 'RIF'
				WHEN m.Id IS NOT NULL THEN 'MAG'
				WHEN s.Id IS NOT NULL THEN 'SRV'
			END
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
			LEFT JOIN dbo.tblImportiServizi s ON i.Id = s.Id
		WHERE
			i.Id = @Id
			AND e.Id = @IdSessione;

		IF @lock IS NULL OR @idModulo IS NULL OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- ── CASO 1: importo attivo (Lock = 0) → soft delete ──────────────────
		IF @lock = 0
		BEGIN
			-- Un importo associato a un contratto o a un'offerta non cancellati resta
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblOfferteContrattiImporti ci
					INNER JOIN dbo.tblOfferteContratti oc ON ci.IdOffertaContratto = oc.Id
				WHERE
					ci.IdImporto = @Id
					AND oc.Lock IN (0, 2)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un importo associato a un contratto o a un''offerta non può essere cancellato: toglierlo prima dal contratto';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblImporti
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Importo non trovato o già eliminato';
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

		-- ── CASO 2: importo in bozza (Lock = 2) → hard delete, con le sue righe ──
		ELSE IF @lock = 2
		BEGIN
			DECLARE @righe TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);

			BEGIN TRANSACTION;
				INSERT @righe (Id)
				SELECT Id
				FROM dbo.tblImportiRighe
				WHERE IdImporto = @Id;

				DELETE d
				FROM dbo.tblImportiRigheDettagli d
				INNER JOIN @righe t ON d.Id = t.Id;
				DELETE dbo.tblImportiRighe
				WHERE IdImporto = @Id;
				DELETE l
				FROM dbo.tblIdLog l
				INNER JOIN @righe t ON l.Id = t.Id;
				DELETE x
				FROM dbo.tblId x
				INNER JOIN @righe t ON x.Id = t.Id;

				DELETE dbo.tblOfferteContrattiImporti
				WHERE IdImporto = @Id;
				DELETE dbo.tblImportiRifiuti
				WHERE Id = @Id;
				DELETE dbo.tblImportiMagazzino
				WHERE Id = @Id;
				DELETE dbo.tblImportiServizi
				WHERE Id = @Id;
				DELETE dbo.tblImporti
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellato (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
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
GO

PRINT 'sql/procedures/uspImporti_del_Undo.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Ripristina gli importi (rifiuti, magazzino o servizi) cancellati con l'ultima cancellazione della sessione.
-- Rifiutato se nel frattempo è stato inserito un importo dello stesso modulo con lo stesso nome.
CREATE OR ALTER PROCEDURE dbo.uspImporti_del_Undo
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Dopo la cancellazione può essere stato inserito un importo dello stesso modulo con lo stesso nome
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblImporti i
				INNER JOIN dbo.tblIdCancellati c ON i.Id = c.Id
				INNER JOIN dbo.tblImporti a ON i.IdSede = a.IdSede
										   AND i.Nome = a.Nome
			WHERE
				c.IdSessione = @IdSessione
				AND i.Lock = 4
				AND a.Lock = 0
				AND
					(
					(EXISTS (SELECT 1 FROM dbo.tblImportiRifiuti x WHERE x.Id = i.Id) AND EXISTS (SELECT 1 FROM dbo.tblImportiRifiuti x WHERE x.Id = a.Id))
					OR (EXISTS (SELECT 1 FROM dbo.tblImportiMagazzino x WHERE x.Id = i.Id) AND EXISTS (SELECT 1 FROM dbo.tblImportiMagazzino x WHERE x.Id = a.Id))
					OR (EXISTS (SELECT 1 FROM dbo.tblImportiServizi x WHERE x.Id = i.Id) AND EXISTS (SELECT 1 FROM dbo.tblImportiServizi x WHERE x.Id = a.Id))
					)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Ripristino non possibile: esiste già un importo con lo stesso nome';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblImporti i
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
GO

PRINT 'sql/procedures/uspImporti_get_ContrattiScaduti.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Importi dell'azienda interna corrente della sessione associati a un contratto scaduto (contratto confermato,
-- non un'offerta, con la fine della validità precedente a oggi), contati per modulo dei documenti: riquadro
-- giallo in testa alla procedura automatica di fatturazione (Fatture clienti > Nuovo > Tramite procedura
-- automatica). Quegli importi non si applicano più ai documenti con data successiva alla scadenza.
-- Una riga per ogni modulo attivo sul dominio che ne ha almeno uno; nessuna riga se non ce ne sono, se manca
-- l'azienda nel contesto o se il modulo Offerte e contratti non è attivo.
-- Si legge con il permesso sulle fatture (FTT) o sugli importi (OCI).
CREATE OR ALTER PROCEDURE dbo.uspImporti_get_ContrattiScaduti
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'OCI',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Moduli dei documenti attivi sul dominio: pre-calcolati FUORI dalla query
		DECLARE @rifAttivo BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0);
		DECLARE @magAttivo BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0);
		DECLARE @srvAttivo BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('SRV', @IdSessione), 0);
		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);

		SELECT
			Id = t.IdModulo,
			Importi = COUNT(*)
		FROM
			(
				SELECT
					IdModulo = CAST(CASE
						WHEN r.Id IS NOT NULL AND @rifAttivo = 1 THEN 'RIF'
						WHEN m.Id IS NOT NULL AND @magAttivo = 1 THEN 'MAG'
						WHEN v.Id IS NOT NULL AND @srvAttivo = 1 THEN 'SRV'
					END AS CHAR(3))
				FROM
					dbo.tblImporti i
					INNER JOIN dbo.tblOfferteContrattiImporti ci ON i.Id = ci.IdImporto
					INNER JOIN dbo.tblOfferteContratti oc ON ci.IdOffertaContratto = oc.Id
					LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
					LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
					LEFT JOIN dbo.tblImportiServizi v ON i.Id = v.Id
				WHERE
					i.IdSede = @idAzienda
					AND i.Lock = 0
					AND oc.Lock = 0
					AND oc.Tipo = 'C'
					AND oc.DataFine < @oggi
					AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 1
			) t
		WHERE t.IdModulo IS NOT NULL
		GROUP BY t.IdModulo
		ORDER BY CASE t.IdModulo WHEN 'RIF' THEN 1 WHEN 'MAG' THEN 2 ELSE 3 END
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
GO

PRINT 'sql/procedures/uspImportiRifiuti_ins.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Nuovo importo rifiuti, in bozza (Lock = 2), dell'azienda interna corrente della sessione, con priorità Media.
-- @IdOffertaContratto (facoltativo): l'importo nasce già associato a quel contratto o a quell'offerta ("Nuovo
-- importo" dalla scheda del contratto); serve anche il permesso di modifica sui contratti (OCC).
CREATE OR ALTER PROCEDURE dbo.uspImportiRifiuti_ins
	@IdSessione CHAR(16) = NULL,
	@IdOffertaContratto CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnId CHAR(16) = NULL;
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdOffertaContratto = NULLIF(NULLIF(LTRIM(RTRIM(@IdOffertaContratto)), ''), REPLICATE('0', 16));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Rifiuti sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'importo appartiene all'azienda interna corrente della sessione
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

		-- Contratto o offerta a cui associare l'importo: della stessa azienda, attivo o in bozza
		IF @IdOffertaContratto IS NOT NULL
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'OCC',
				@Permesso = @permesso OUTPUT;
			IF 2 > @permesso OR NOT EXISTS (
				SELECT 1
				FROM dbo.tblOfferteContratti
				WHERE
					Id = @IdOffertaContratto
					AND IdSede = @idAzienda
					AND Lock <= 2
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Non si dispone dei diritti necessari, o il contratto non esiste';
				GOTO BRANCH_END;
			END
		END

		-- uspId_get FUORI dalla transazione
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @returnId OUTPUT;

		BEGIN TRANSACTION;
			INSERT dbo.tblImporti (Id, IdSede, IdPriorita, Lock)
			VALUES (@returnId, @idAzienda, 4, 2);

			-- IdSede: copia dell'azienda dell'importo (che non cambia più), per il confronto con i documenti
			-- (ufnImportiRifiuti_get_Coincidenti)
			INSERT dbo.tblImportiRifiuti (Id, IdSede)
			VALUES (@returnId, @idAzienda);

			IF @IdOffertaContratto IS NOT NULL
				INSERT dbo.tblOfferteContrattiImporti (IdOffertaContratto, IdImporto)
				VALUES (@IdOffertaContratto, @returnId);
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
GO

PRINT 'sql/procedures/uspImportiRifiuti_get.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scheda di un importo rifiuti dell'azienda interna corrente della sessione (attivo o in bozza).
-- Contratto: descrizione del contratto o dell'offerta a cui l'importo è associato, NULL se è un importo standard.
-- ContrattoScaduto = 1: è associato a un contratto la cui validità è finita prima di oggi (avviso nella scheda).
CREATE OR ALTER PROCEDURE dbo.uspImportiRifiuti_get
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

		-- Controlla il permesso sulla funzione e che il modulo Rifiuti sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblImporti i
				INNER JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
				INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			WHERE
				i.Id = @Id
				AND e.Id = @IdSessione
				AND i.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o l''importo non esiste';
			GOTO BRANCH_END;
		END

		SELECT
			i.Id,
			i.IdSede,
			i.Nome,
			i.IdPriorita,
			i.Lock,
			r.IdEer,
			r.IdProduttoreParent,
			r.IdProduttore,
			r.IdTrasportatore,
			r.IdDestinatario,
			r.IdIntermediario,
			r.IdEtichetta,
			Contratto = c.Contratto,
			c.IdOffertaContratto,
			ContrattoTipo = c.Tipo,
			ContrattoDataFine = c.DataFine,
			-- Contratto (non offerta) confermato la cui validità è finita prima di oggi: la scheda lo segnala
			ContrattoScaduto = CAST(IIF(c.Tipo = 'C' AND c.Lock = 0 AND c.DataFine < CAST(GETDATE() AS DATE), 1, 0) AS BIT)
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			OUTER APPLY (
				SELECT TOP (1)
					IdOffertaContratto = oc.Id,
					oc.Tipo,
					oc.DataFine,
					oc.Lock,
					Contratto = IIF(oc.Tipo = 'O', 'Offerta', 'Contratto')
						+ ISNULL(' ' + cs.NomeCompleto, '')
						+ ISNULL(' dal ' + CONVERT(VARCHAR(10), oc.DataInizio, 103), '')
						+ ISNULL(' al ' + CONVERT(VARCHAR(10), oc.DataFine, 103), '')
				FROM
					dbo.tblOfferteContrattiImporti ci
					INNER JOIN dbo.tblOfferteContratti oc ON ci.IdOffertaContratto = oc.Id
					LEFT JOIN dbo.tblClientiFornitori cf ON oc.IdClienteFornitore = cf.Id
					LEFT JOIN dbo.tblSedi cs ON cf.IdSede = cs.Id
				WHERE
					ci.IdImporto = i.Id
					AND oc.Lock <= 2
			) c
		WHERE i.Id = @Id;

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
GO

PRINT 'sql/procedures/uspImportiRifiuti_upd.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva un importo rifiuti e conferma la bozza (Lock 2 -> 0).
-- Le variabili (EER, produttore, trasportatore, destinatario, intermediario, etichetta) sono facoltative: una
-- variabile non indicata vale "qualsiasi" nel confronto con la registrazione.
-- Produttore: @IdProduttoreParent è il soggetto (tutte le sue sedi), @IdProduttore una sua sede precisa. Indicata
-- la sola sede, il soggetto si ricava dalla sede.
CREATE OR ALTER PROCEDURE dbo.uspImportiRifiuti_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@IdPriorita INT = NULL,
	@IdEer CHAR(6) = NULL,
	@IdProduttoreParent CHAR(16) = NULL,
	@IdProduttore CHAR(16) = NULL,
	@IdTrasportatore CHAR(16) = NULL,
	@IdDestinatario CHAR(16) = NULL,
	@IdIntermediario CHAR(16) = NULL,
	@IdEtichetta CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Nome = dbo.ufnStringhe_get_SenzaSpazi(@Nome, 0, 1);
		SET @IdEer = NULLIF(NULLIF(LTRIM(RTRIM(@IdEer)), ''), REPLICATE('0', 6));
		SET @IdProduttoreParent = NULLIF(NULLIF(LTRIM(RTRIM(@IdProduttoreParent)), ''), @idSediciZeri);
		SET @IdProduttore = NULLIF(NULLIF(LTRIM(RTRIM(@IdProduttore)), ''), @idSediciZeri);
		SET @IdTrasportatore = NULLIF(NULLIF(LTRIM(RTRIM(@IdTrasportatore)), ''), @idSediciZeri);
		SET @IdDestinatario = NULLIF(NULLIF(LTRIM(RTRIM(@IdDestinatario)), ''), @idSediciZeri);
		SET @IdIntermediario = NULLIF(NULLIF(LTRIM(RTRIM(@IdIntermediario)), ''), @idSediciZeri);
		SET @IdEtichetta = NULLIF(NULLIF(LTRIM(RTRIM(@IdEtichetta)), ''), @idSediciZeri);

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
		IF @Nome IS NULL OR LEN(@Nome) < 3
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il nome dell''importo (almeno 3 caratteri)';
			GOTO BRANCH_END;
		END
		IF @IdPriorita IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.tblImportiPriorita WHERE Id = @IdPriorita)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare la priorità';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Rifiuti sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @idProduttoreParentAttuale CHAR(16);
		DECLARE @idProduttoreAttuale CHAR(16);
		DECLARE @idTrasportatoreAttuale CHAR(16);
		DECLARE @idDestinatarioAttuale CHAR(16);
		DECLARE @idIntermediarioAttuale CHAR(16);
		DECLARE @idEtichettaAttuale CHAR(16);
		SELECT
			@idAzienda = i.IdSede,
			@idProduttoreParentAttuale = r.IdProduttoreParent,
			@idProduttoreAttuale = r.IdProduttore,
			@idTrasportatoreAttuale = r.IdTrasportatore,
			@idDestinatarioAttuale = r.IdDestinatario,
			@idIntermediarioAttuale = r.IdIntermediario,
			@idEtichettaAttuale = r.IdEtichetta
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
		WHERE
			i.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Nome unico tra gli importi rifiuti attivi dell'azienda
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblImporti i
				INNER JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			WHERE
				i.Id <> @Id
				AND i.IdSede = @idAzienda
				AND i.Lock = 0
				AND i.Nome = @Nome
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Esiste già un importo rifiuti con questo nome';
			GOTO BRANCH_END;
		END

		IF @IdEer IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblRifiutiEer WHERE Id = @IdEer)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il codice EER indicato non esiste';
			GOTO BRANCH_END;
		END

		-- Sede del produttore: è il soggetto stesso o una sua sede; indicata la sola sede, il soggetto si ricava
		IF @IdProduttore IS NOT NULL
		BEGIN
			DECLARE @idParentDellaSede CHAR(16);
			SELECT @idParentDellaSede = ISNULL(IdParent, Id)
			FROM dbo.tblSedi
			WHERE Id = @IdProduttore;

			IF @IdProduttoreParent IS NULL
				SET @IdProduttoreParent = @idParentDellaSede;
			ELSE IF ISNULL(@idParentDellaSede, '') <> @IdProduttoreParent
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'La sede del produttore non appartiene al produttore indicato';
				GOTO BRANCH_END;
			END
		END

		-- Soggetti e sedi: tra quelli che l'utente vede (propri dell'azienda o condivisi nel dominio tramite
		-- un'area), come nelle select; quelli già sull'importo restano validi
		DECLARE @sedi TABLE (
			Ruolo VARCHAR(50) NOT NULL,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdAttuale CHAR(16) COLLATE DATABASE_DEFAULT NULL
		);
		INSERT @sedi (Ruolo, Id, IdAttuale)
		VALUES
			('Il produttore indicato', @IdProduttoreParent, @idProduttoreParentAttuale),
			('La sede del produttore indicata', @IdProduttore, @idProduttoreAttuale),
			('Il trasportatore indicato', @IdTrasportatore, @idTrasportatoreAttuale),
			('Il destinatario indicato', @IdDestinatario, @idDestinatarioAttuale),
			('L''intermediario indicato', @IdIntermediario, @idIntermediarioAttuale);

		DECLARE @ruoloNonValido VARCHAR(50);
		SELECT TOP (1) @ruoloNonValido = t.Ruolo
		FROM @sedi t
		WHERE
			t.Id IS NOT NULL
			AND (t.IdAttuale IS NULL OR t.Id <> t.IdAttuale)
			AND NOT EXISTS (
				SELECT 1
				FROM
					dbo.tblSessioni e
					CROSS APPLY dbo.ufnSedi_get_SediByUtente_List(e.IdUtente) u
				WHERE
					e.Id = @IdSessione
					AND u.Id = t.Id
					AND
						(
							(
							u.IdDominio = e.IdDominio
							AND u.Condivisa = 1
							)
						OR u.IdAziendaInterna = @idAzienda
						)
			);

		IF @ruoloNonValido IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = @ruoloNonValido + ' non esiste o non è accessibile';
			GOTO BRANCH_END;
		END

		-- Etichetta: del modulo Rifiuti, di una sede dell'azienda; quella già sull'importo resta valida
		IF @IdEtichetta IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblEtichette t
				INNER JOIN dbo.tblSedi s ON t.IdSede = s.Id
			WHERE
				t.Id = @IdEtichetta
				AND t.IdModulo = 'RIF'
				AND s.IdAziendaInterna = @idAzienda
				AND (t.Lock = 0 OR t.Id = @idEtichettaAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''etichetta indicata non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblImporti
			SET
				Lock = 0,
				Nome = @Nome,
				IdPriorita = @IdPriorita
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Importo non trovato o già eliminato';
				GOTO BRANCH_END;
			END

			UPDATE dbo.tblImportiRifiuti
			SET
				IdEer = @IdEer,
				IdProduttoreParent = @IdProduttoreParent,
				IdProduttore = @IdProduttore,
				IdTrasportatore = @IdTrasportatore,
				IdDestinatario = @IdDestinatario,
				IdIntermediario = @IdIntermediario,
				IdEtichetta = @IdEtichetta
			WHERE Id = @Id;
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
GO

PRINT 'sql/procedures/uspImportiRifiuti_get_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti > Importi rifiuti: elenco degli importi dell'azienda interna corrente della sessione.
-- Righe, scope e ricerca sono in ufnImportiRifiuti_get_List, comune all'esportazione.
CREATE OR ALTER PROCEDURE dbo.uspImportiRifiuti_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@SoloContrattoScaduto BIT = 0
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

		-- Controlla il permesso sulla funzione e che il modulo Rifiuti sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			t.Id,
			t.StatoValore,
			t.StatoDescrizione,
			t.Nome,
			t.Priorita,
			t.Eer,
			t.EerDescrizione,
			t.Produttore,
			t.Trasportatore,
			t.Destinatario,
			t.Intermediario,
			t.Etichetta,
			t.Cliente,
			t.ContrattoTipo,
			t.ContrattoDataFine,
			t.Righe,
			RowsCount = COUNT(*) OVER ()
		FROM dbo.ufnImportiRifiuti_get_List(@IdSessione, @Search, @SoloContrattoScaduto) t
		ORDER BY t.Nome, t.Id
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
GO

PRINT 'sql/procedures/uspImportiRifiuti_get_Verifica.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti > Importi rifiuti > Azioni > Verifica importi: quali importi dell'azienda interna corrente
-- coinciderebbero con una registrazione che avesse i valori indicati, e quale verrebbe applicato. La regola di
-- coincidenza e la classe dell'importo sono quelle della fatturazione (ufnImportiRifiuti_get_Coincidenti); qui si
-- restituiscono tutti gli importi che coincidono, non solo il primo.
--   @Data: data della registrazione (decide la validità dei contratti); se manca, oggi.
--   Un valore non indicato vuol dire che la registrazione non ha quel dato: non coincide con gli importi che lo
--   indicano. Produttore: @IdProduttoreParent è il soggetto, @IdProduttore la sua sede; indicato solo il
--   soggetto, la sede è il soggetto stesso; indicata solo la sede, il soggetto si ricava.
--   @IdEtichetta: un'etichetta della registrazione (una sola).
-- Righe nell'ordine di scelta. Esito: A applicato; B coincide ma non viene applicato (Motivo); S di un contratto
-- non valido alla data; X di un'offerta o di un contratto cancellato (mai applicato).
-- Conflitto = 1: stessa priorità e stesso tipo (di contratto o standard) dell'importo applicato, lui compreso:
-- tra questi la fatturazione sceglie senza un criterio.
CREATE OR ALTER PROCEDURE dbo.uspImportiRifiuti_get_Verifica
	@IdSessione CHAR(16) = NULL,
	@Data DATE = NULL,
	@IdEer CHAR(6) = NULL,
	@IdProduttoreParent CHAR(16) = NULL,
	@IdProduttore CHAR(16) = NULL,
	@IdTrasportatore CHAR(16) = NULL,
	@IdDestinatario CHAR(16) = NULL,
	@IdIntermediario CHAR(16) = NULL,
	@IdEtichetta CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdEer = NULLIF(NULLIF(LTRIM(RTRIM(@IdEer)), ''), REPLICATE('0', 6));
		SET @IdProduttoreParent = NULLIF(NULLIF(LTRIM(RTRIM(@IdProduttoreParent)), ''), REPLICATE('0', 16));
		SET @IdProduttore = NULLIF(NULLIF(LTRIM(RTRIM(@IdProduttore)), ''), REPLICATE('0', 16));
		SET @IdTrasportatore = NULLIF(NULLIF(LTRIM(RTRIM(@IdTrasportatore)), ''), REPLICATE('0', 16));
		SET @IdDestinatario = NULLIF(NULLIF(LTRIM(RTRIM(@IdDestinatario)), ''), REPLICATE('0', 16));
		SET @IdIntermediario = NULLIF(NULLIF(LTRIM(RTRIM(@IdIntermediario)), ''), REPLICATE('0', 16));
		SET @IdEtichetta = NULLIF(NULLIF(LTRIM(RTRIM(@IdEtichetta)), ''), REPLICATE('0', 16));
		SET @Data = ISNULL(@Data, CAST(GETDATE() AS DATE));

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Rifiuti sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Gli importi sono quelli dell'azienda interna corrente della sessione
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

		-- Produttore: soggetto e sede, come sulla registrazione (ufnImportiRifiuti_get_Applicazione_List)
		IF @IdProduttore IS NULL
			SET @IdProduttore = @IdProduttoreParent;
		ELSE IF @IdProduttoreParent IS NULL
			SELECT @IdProduttoreParent = ISNULL(IdParent, Id)
			FROM dbo.tblSedi
			WHERE Id = @IdProduttore;

		WITH c AS (
			SELECT
				k.IdImporto,
				k.IdPriorita,
				k.IdOffertaContratto,
				k.Standard,
				k.Classe
			FROM dbo.ufnImportiRifiuti_get_Coincidenti(@idAzienda, @Data, @IdEer, @IdProduttoreParent, @IdProduttore, @IdTrasportatore, @IdDestinatario, @IdIntermediario) k
			-- L'importo che indica un'etichetta coincide solo se è quella della registrazione
			WHERE
				k.IdEtichetta IS NULL
				OR k.IdEtichetta = @IdEtichetta
		),
		o AS (
			SELECT
				c.IdImporto,
				c.IdPriorita,
				c.IdOffertaContratto,
				c.Standard,
				c.Classe,
				N = ROW_NUMBER() OVER (PARTITION BY c.Classe ORDER BY c.IdPriorita DESC, c.Standard, c.IdImporto),
				-- Priorità e tipo del primo della classe: per i candidati, quelli dell'importo applicato
				PrimoPriorita = FIRST_VALUE(c.IdPriorita) OVER (PARTITION BY c.Classe ORDER BY c.IdPriorita DESC, c.Standard, c.IdImporto),
				PrimoStandard = FIRST_VALUE(c.Standard) OVER (PARTITION BY c.Classe ORDER BY c.IdPriorita DESC, c.Standard, c.IdImporto)
			FROM c
		),
		t AS (
			SELECT
				o.IdImporto,
				o.IdPriorita,
				o.IdOffertaContratto,
				o.Standard,
				o.Classe,
				o.N,
				Pari = CAST(IIF(o.Classe = 'V' AND ISNULL(o.IdPriorita, -1) = ISNULL(o.PrimoPriorita, -1) AND o.Standard = o.PrimoStandard, 1, 0) AS BIT),
				PrioritaPiuBassa = CAST(IIF(ISNULL(o.IdPriorita, -1) < ISNULL(o.PrimoPriorita, -1), 1, 0) AS BIT)
			FROM o
		)
		SELECT
			Id = t.IdImporto,
			i.Nome,
			Priorita = p.Nome,
			t.Standard,
			Cliente = cs.NomeCompleto,
			ContrattoTipo = oc.Tipo,
			ContrattoDataInizio = oc.DataInizio,
			ContrattoDataFine = oc.DataFine,
			Righe = (SELECT COUNT(*) FROM dbo.tblImportiRighe g WHERE g.IdImporto = t.IdImporto),
			Esito = CAST(CASE
				WHEN t.Classe = 'V' AND t.N = 1 THEN 'A'
				WHEN t.Classe = 'V' THEN 'B'
				ELSE t.Classe
			END AS CHAR(1)),
			Conflitto = CAST(IIF(t.Pari = 1 AND SUM(CAST(t.Pari AS INT)) OVER () > 1, 1, 0) AS BIT),
			Motivo = CAST(CASE
				WHEN t.Classe = 'V' AND t.N = 1 THEN 'Importo applicato'
				WHEN t.Classe = 'V' AND t.PrioritaPiuBassa = 1 THEN 'Priorità più bassa dell''importo applicato'
				WHEN t.Classe = 'V' AND t.Pari = 1 THEN 'Stessa priorità e stesso tipo dell''importo applicato'
				WHEN t.Classe = 'V' THEN 'A parità di priorità prevale l''importo di un contratto'
				WHEN t.Classe = 'S' THEN 'Contratto non valido alla data: dal ' + CONVERT(VARCHAR(10), oc.DataInizio, 103) + ' al ' + CONVERT(VARCHAR(10), oc.DataFine, 103)
				WHEN oc.Tipo = 'O' THEN 'Importo di un''offerta: non viene applicato'
				ELSE 'Contratto cancellato o senza validità: non viene applicato'
			END AS VARCHAR(100))
		FROM
			t
			INNER JOIN dbo.tblImporti i ON t.IdImporto = i.Id
			LEFT JOIN dbo.tblImportiPriorita p ON t.IdPriorita = p.Id
			LEFT JOIN dbo.tblOfferteContratti oc ON t.IdOffertaContratto = oc.Id
			LEFT JOIN dbo.tblClientiFornitori cf ON oc.IdClienteFornitore = cf.Id
			LEFT JOIN dbo.tblSedi cs ON cf.IdSede = cs.Id
		ORDER BY
			CASE t.Classe WHEN 'V' THEN 0 WHEN 'S' THEN 1 ELSE 2 END,
			t.N
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
GO

PRINT 'sql/procedures/uspImportiRifiuti_get_Conflitti.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti > Importi rifiuti: importi attivi della stessa azienda in conflitto con l'importo @Id.
-- La scheda li mostra dopo il salvataggio; l'importo resta salvato, è un avviso.
-- Due importi sono in conflitto se possono coincidere con la stessa registrazione e la fatturazione non ha un
-- criterio per scegliere tra i due (li ordina per Id):
--   - variabili sovrapposte: per ogni variabile, uno dei due non la indica oppure indicano lo stesso valore.
--     L'etichetta non si confronta: una registrazione può averne più di una;
--   - stessa priorità;
--   - stesso tipo: entrambi standard, oppure entrambi di un contratto attivo di un cliente, con periodi di
--     validità che si sovrappongono (anche di clienti diversi).
-- Un importo di un'offerta o di un contratto cancellato non viene mai applicato: nessun conflitto.
CREATE OR ALTER PROCEDURE dbo.uspImportiRifiuti_get_Conflitti
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

		-- Controlla il permesso sulla funzione e che il modulo Rifiuti sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT
			b.Id,
			b.Nome,
			Priorita = p.Nome,
			Standard = CAST(IIF(bc.IdImporto IS NULL, 1, 0) AS BIT),
			Cliente = cs.NomeCompleto,
			ContrattoTipo = bo.Tipo,
			ContrattoDataInizio = bo.DataInizio,
			ContrattoDataFine = bo.DataFine
		FROM
			dbo.tblImporti a
			INNER JOIN dbo.tblSessioni e ON a.IdSede = e.IdAzienda
			INNER JOIN dbo.tblImportiRifiuti ar ON a.Id = ar.Id
			LEFT JOIN dbo.tblOfferteContrattiImporti ac ON a.Id = ac.IdImporto
			LEFT JOIN dbo.tblOfferteContratti ao ON ac.IdOffertaContratto = ao.Id
			-- Gli altri importi rifiuti dell'azienda
			INNER JOIN dbo.tblImportiRifiuti br ON ar.IdSede = br.IdSede
												AND ar.Id <> br.Id
			INNER JOIN dbo.tblImporti b ON br.Id = b.Id
			LEFT JOIN dbo.tblOfferteContrattiImporti bc ON b.Id = bc.IdImporto
			LEFT JOIN dbo.tblOfferteContratti bo ON bc.IdOffertaContratto = bo.Id
			LEFT JOIN dbo.tblImportiPriorita p ON b.IdPriorita = p.Id
			LEFT JOIN dbo.tblClientiFornitori cf ON bo.IdClienteFornitore = cf.Id
			LEFT JOIN dbo.tblSedi cs ON cf.IdSede = cs.Id
		WHERE
			a.Id = @Id
			AND e.Id = @IdSessione
			AND a.Lock <= 2
			AND b.Lock = 0
			AND ISNULL(a.IdPriorita, -1) = ISNULL(b.IdPriorita, -1)
			AND (ar.IdEer IS NULL OR br.IdEer IS NULL OR ar.IdEer = br.IdEer)
			AND (ar.IdProduttoreParent IS NULL OR br.IdProduttoreParent IS NULL OR ar.IdProduttoreParent = br.IdProduttoreParent)
			AND (ar.IdProduttore IS NULL OR br.IdProduttore IS NULL OR ar.IdProduttore = br.IdProduttore)
			AND (ar.IdTrasportatore IS NULL OR br.IdTrasportatore IS NULL OR ar.IdTrasportatore = br.IdTrasportatore)
			AND (ar.IdDestinatario IS NULL OR br.IdDestinatario IS NULL OR ar.IdDestinatario = br.IdDestinatario)
			AND (ar.IdIntermediario IS NULL OR br.IdIntermediario IS NULL OR ar.IdIntermediario = br.IdIntermediario)
			AND
				(
					(ac.IdImporto IS NULL AND bc.IdImporto IS NULL)
					OR
					(
						ao.Lock = 0 AND ao.Tipo = 'C' AND ao.ClienteFornitoreTipo = 'C'
						AND bo.Lock = 0 AND bo.Tipo = 'C' AND bo.ClienteFornitoreTipo = 'C'
						AND ao.DataInizio <= bo.DataFine
						AND bo.DataInizio <= ao.DataFine
					)
				)
		ORDER BY b.Nome, b.Id
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
GO

PRINT 'sql/procedures/uspImportiRifiuti_get_Esportazione.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Importi rifiuti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta in Excel, Esporta in
-- CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione (ExcelService,
-- CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa si esporta si
-- modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: scope e criteri di ricerca sono in ufnImportiRifiuti_get_List,
-- comune a uspImportiRifiuti_get_List. Tutte le righe, senza paginazione: al massimo @MaxRighe + 1 (la riga in
-- più dice all'applicazione che la ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspImportiRifiuti_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@SoloContrattoScaduto BIT = 0,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Rifiuti sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (@MaxRighe + 1)
			[Nome] = t.Nome,
			[Priorità] = t.Priorita,
			[EER] = t.Eer,
			[Produttore] = t.Produttore,
			[Trasportatore] = t.Trasportatore,
			[Destinatario] = t.Destinatario,
			[Intermediario] = t.Intermediario,
			[Etichetta] = t.Etichetta,
			[Cliente] = t.Cliente,
			[Contratto o offerta] = CASE t.ContrattoTipo WHEN 'C' THEN 'Contratto' WHEN 'O' THEN 'Offerta' END,
			[Valido dal] = t.ContrattoDataInizio,
			[Valido al] = t.ContrattoDataFine,
			[Righe] = t.Righe
		FROM dbo.ufnImportiRifiuti_get_List(@IdSessione, @Search, @SoloContrattoScaduto) t
		ORDER BY t.Nome, t.Id
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
GO

PRINT 'sql/procedures/uspImportiRifiuti_get_Sedi_SelectList.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select dei soggetti e delle sedi per le variabili di un importo rifiuti. La prima voce (Id a zeri) significa
-- "qualsiasi": la variabile non viene confrontata con la registrazione.
--   @Livello = 'A': solo i soggetti (aziende, sedi radice): produttore
--   @Livello = 'S': il soggetto @IdParent e le sue sedi: sede del produttore (senza @IdParent solo la prima voce)
--   @Livello = 'T': soggetti e sedi: trasportatore, destinatario, intermediario
-- Visibilità come uspSedi_get_Sedi_SelectList: anagrafiche dell'azienda interna corrente della sessione o
-- condivise nel dominio tramite un'area. La voce selezionata è sempre presente, anche se disabilitata, fuori
-- dalla ricerca o oltre le prime 50.
CREATE OR ALTER PROCEDURE dbo.uspImportiRifiuti_get_Sedi_SelectList
	@IdSessione CHAR(16) = NULL,
	@IdSelected CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL,
	@Livello CHAR(1) = 'T',
	@IdParent CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @idSediciZeri CHAR(16) = REPLICATE('0', 16);

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @Livello = ISNULL(NULLIF(UPPER(LTRIM(RTRIM(@Livello))), ''), 'T');
		SET @IdParent = NULLIF(NULLIF(LTRIM(RTRIM(@IdParent)), ''), @idSediciZeri);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Livello NOT IN ('A', 'S', 'T')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Livello deve essere A, S o T';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Rifiuti sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST(IIF(@Livello = 'S', '(Tutte)', '(Tutti)') AS VARCHAR(400)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0
			UNION ALL
			SELECT
				s.Id,
				[Text] = CAST(s.NomeCompleto + IIF(@Livello = 'A', '', ISNULL(' ' + s.IndirizzoCompleto, '')) AS VARCHAR(400)),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM dbo.tblSedi s
			WHERE
				s.Id = @IdSelected
				AND s.Id <> @idSediciZeri
			UNION ALL
			SELECT
				t.Id,
				t.[Text],
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				(
					SELECT TOP (50)
						s.Id,
						[Text] = CAST(s.NomeCompleto + IIF(@Livello = 'A', '', ISNULL(' ' + s.IndirizzoCompleto, '')) AS VARCHAR(400))
					FROM
						dbo.tblSessioni e
						CROSS APPLY dbo.ufnSedi_get_SediByUtente_List(e.IdUtente) u
						INNER JOIN dbo.tblSedi s ON u.Id = s.Id
					WHERE
						e.Id = @IdSessione
						AND
							(
								(
								u.IdDominio = e.IdDominio
								AND u.Condivisa = 1
								)
							OR u.IdAziendaInterna = e.IdAzienda
							)
						AND u.Disabilitata = 0
						AND s.Id <> @IdSelected
						AND
							(
							@Livello = 'T'
							OR (@Livello = 'A' AND u.IdParent IS NULL)
							OR (@Livello = 'S' AND (u.Id = @IdParent OR u.IdParent = @IdParent))
							)
						AND
							(
							@Search IS NULL
							OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%'
							)
					ORDER BY s.NomeCompleto, s.IndirizzoCompleto
				) t
		)
		SELECT
			Id,
			[Text],
			Selected
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
GO

PRINT 'sql/procedures/uspImportiRifiuti_get_Etichette_SelectList.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select delle etichette per un importo rifiuti: etichette del modulo Rifiuti delle sedi dell'azienda interna
-- corrente della sessione. Le etichette appartengono alla sede: quando la sede non è l'azienda stessa il suo
-- nome segue quello dell'etichetta. La prima voce (Id a zeri) significa "qualsiasi". L'etichetta selezionata è
-- sempre presente, anche se cancellata.
CREATE OR ALTER PROCEDURE dbo.uspImportiRifiuti_get_Etichette_SelectList
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
		SET @IdSelected = ISNULL(NULLIF(LTRIM(RTRIM(@IdSelected)), ''), @idSediciZeri);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione e che il modulo Rifiuti sia attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Tutte)' AS VARCHAR(400)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0
			UNION ALL
			SELECT
				t.Id,
				[Text] = CAST(t.Nome + IIF(t.IdSede = @idAzienda, '', ISNULL(' - ' + s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, ''), '')) AS VARCHAR(400)),
				Selected = CAST(IIF(t.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM
				dbo.tblEtichette t
				INNER JOIN dbo.tblSedi s ON t.IdSede = s.Id
			WHERE
				t.IdModulo = 'RIF'
				AND s.IdAziendaInterna = @idAzienda
				AND (t.Lock = 0 OR t.Id = @IdSelected)
		) x
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
GO

PRINT 'sql/procedures/uspImportiRighe_get_Tipi_SelectList.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Select dei tipi di riga di un importo per il modulo indicato (RIF, MAG, SRV): dato di riferimento
-- (tblImportiRigheTipi). Il tipo dice per che cosa si moltiplica l'importo della riga: una volta per documento
-- (Movimento, Servizio) oppure per la quantità (KG, T, L, articolo, unità).
CREATE OR ALTER PROCEDURE dbo.uspImportiRighe_get_Tipi_SelectList
	@IdModulo CHAR(3) = NULL,
	@IdSelected CHAR(2) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');

		IF @IdModulo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo non può essere vuoto';
			GOTO BRANCH_END;
		END

		SELECT
			t.Id,
			[Text] = t.Nome,
			Selected = CAST(IIF(t.Id = @IdSelected, 1, 0) AS BIT)
		FROM dbo.tblImportiRigheTipi t
		WHERE t.IdModulo = @IdModulo
		ORDER BY t.Pos;

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
GO

PRINT 'sql/procedures/uspImportiRighe_get_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Righe di un importo (rifiuti, magazzino o servizi) dell'azienda interna corrente della sessione, nell'ordine
-- in cui finiranno in fattura. Una riga senza importo è di sola descrizione.
CREATE OR ALTER PROCEDURE dbo.uspImportiRighe_get_List
	@IdImporto CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdImporto = NULLIF(LTRIM(RTRIM(@IdImporto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @IdImporto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdImporto non può essere vuoto';
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
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'importo deve appartenere all'azienda interna corrente della sessione e il suo modulo (quello dei
		-- documenti a cui si applica) deve essere attivo sul dominio
		DECLARE @idAzienda CHAR(16);
		DECLARE @idModulo CHAR(3);
		SELECT
			@idAzienda = i.IdSede,
			@idModulo = CASE
				WHEN r.Id IS NOT NULL THEN 'RIF'
				WHEN m.Id IS NOT NULL THEN 'MAG'
				WHEN s.Id IS NOT NULL THEN 'SRV'
			END
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
			LEFT JOIN dbo.tblImportiServizi s ON i.Id = s.Id
		WHERE
			i.Id = @IdImporto
			AND e.Id = @IdSessione
			AND i.Lock <= 2;

		IF @idAzienda IS NULL OR @idModulo IS NULL OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o l''importo non esiste';
			GOTO BRANCH_END;
		END

		SELECT
			g.Id,
			g.IdImporto,
			g.IdTipo,
			Tipo = t.Nome,
			g.Importo,
			MinimoFatturabile = ISNULL(g.MinimoFatturabile, 0),
			d.IdAliquotaIva,
			AliquotaIvaNome = a.Nome,
			d.IdConto,
			ContoNome = ISNULL(c.Codice + ' - ', '') + c.Nome,
			d.Descrizione,
			g.Pos
		FROM
			dbo.tblImportiRighe g
			LEFT JOIN dbo.tblImportiRigheDettagli d ON g.Id = d.Id
			LEFT JOIN dbo.tblImportiRigheTipi t ON g.IdTipo = t.Id
			LEFT JOIN dbo.tblAliquoteIva a ON d.IdAliquotaIva = a.Id
			LEFT JOIN dbo.tblFattureConti c ON d.IdConto = c.Id
		WHERE g.IdImporto = @IdImporto
		ORDER BY ISNULL(g.Pos, 0), g.Id;

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
GO

PRINT 'sql/procedures/uspImportiRighe_upd.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Aggiunge una riga a un importo (@Id NULL, in coda) o la modifica. Vale per gli importi di rifiuti, magazzino
-- e servizi: il tipo di riga deve essere del modulo dell'importo.
-- Riga con importo: il tipo dice per che cosa si moltiplica (una volta per documento, oppure per la quantità).
-- Riga di sola descrizione (@Importo NULL): in fattura dà una riga di testo, una per documento; aliquota IVA e
-- conto non contano.
-- Minimo fatturabile: l'importo della riga è il minimo da fatturare per documento; al massimo una per importo.
-- Aliquota IVA facoltativa: se manca, la fatturazione usa quella della scheda del cliente.
CREATE OR ALTER PROCEDURE dbo.uspImportiRighe_upd
	@Id CHAR(16) = NULL,
	@IdImporto CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdTipo CHAR(2) = NULL,
	@Importo DECIMAL(18, 4) = NULL,
	@MinimoFatturabile BIT = NULL,
	@IdAliquotaIva CHAR(16) = NULL,
	@IdConto CHAR(16) = NULL,
	@Descrizione VARCHAR(1000) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdImporto = NULLIF(LTRIM(RTRIM(@IdImporto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdTipo = NULLIF(UPPER(LTRIM(RTRIM(@IdTipo))), '');
		SET @MinimoFatturabile = ISNULL(@MinimoFatturabile, 0);
		SET @IdAliquotaIva = NULLIF(NULLIF(LTRIM(RTRIM(@IdAliquotaIva)), ''), REPLICATE('0', 16));
		SET @IdConto = NULLIF(NULLIF(LTRIM(RTRIM(@IdConto)), ''), REPLICATE('0', 16));
		SET @Descrizione = NULLIF(LTRIM(RTRIM(@Descrizione)), '');

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
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Riga esistente: l'importo è quello della riga
		DECLARE @idAliquotaIvaAttuale CHAR(16);
		DECLARE @idContoAttuale CHAR(16);
		IF @Id IS NOT NULL
		BEGIN
			SET @IdImporto = NULL;
			SELECT
				@IdImporto = g.IdImporto,
				@idAliquotaIvaAttuale = d.IdAliquotaIva,
				@idContoAttuale = d.IdConto
			FROM
				dbo.tblImportiRighe g
				LEFT JOIN dbo.tblImportiRigheDettagli d ON g.Id = d.Id
			WHERE g.Id = @Id;
		END

		-- L'importo deve esistere (in bozza o attivo), appartenere all'azienda interna corrente della sessione
		-- e il suo modulo deve essere attivo sul dominio
		DECLARE @idAzienda CHAR(16);
		DECLARE @idModulo CHAR(3);
		SELECT
			@idAzienda = i.IdSede,
			@idModulo = CASE
				WHEN r.Id IS NOT NULL THEN 'RIF'
				WHEN m.Id IS NOT NULL THEN 'MAG'
				WHEN s.Id IS NOT NULL THEN 'SRV'
			END
		FROM
			dbo.tblImporti i
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
			LEFT JOIN dbo.tblImportiServizi s ON i.Id = s.Id
		WHERE
			i.Id = @IdImporto
			AND e.Id = @IdSessione
			AND i.Lock <= 2;

		IF @idAzienda IS NULL OR @idModulo IS NULL OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o l''importo non esiste';
			GOTO BRANCH_END;
		END

		IF @Descrizione IS NULL OR LEN(@Descrizione) < 3
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il testo della riga in fattura (almeno 3 caratteri)';
			GOTO BRANCH_END;
		END

		DECLARE @conImporto BIT = IIF(@Importo IS NULL, 0, 1);
		IF @conImporto = 1
		BEGIN
			IF @IdTipo IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.tblImportiRigheTipi WHERE Id = @IdTipo AND IdModulo = @idModulo)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Selezionare a che cosa si applica l''importo della riga';
				GOTO BRANCH_END;
			END
			IF @Importo < 0.0001 OR @Importo > 999999.9999
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''importo deve essere compreso tra 0,0001 e 999.999,9999';
				GOTO BRANCH_END;
			END
			-- Aliquota IVA: facoltativa, di sistema (IdSede NULL) o dell'azienda; quella già sulla riga resta valida
			IF @IdAliquotaIva IS NOT NULL AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblAliquoteIva
				WHERE
					Id = @IdAliquotaIva
					AND (IdSede IS NULL OR IdSede = @idAzienda)
					AND (Lock = 0 OR Id = @idAliquotaIvaAttuale)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''aliquota IVA indicata non esiste';
				GOTO BRANCH_END;
			END
			-- Conto: facoltativo, dell'azienda; quello già sulla riga resta valido
			IF @IdConto IS NOT NULL AND NOT EXISTS (
				SELECT 1
				FROM dbo.tblFattureConti
				WHERE
					Id = @IdConto
					AND IdSede = @idAzienda
					AND (Lock = 0 OR Id = @idContoAttuale)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Il conto indicato non esiste';
				GOTO BRANCH_END;
			END
			-- Al massimo una riga con il minimo fatturabile per importo
			IF @MinimoFatturabile = 1 AND EXISTS (
				SELECT 1
				FROM dbo.tblImportiRighe
				WHERE
					IdImporto = @IdImporto
					AND MinimoFatturabile = 1
					AND (@Id IS NULL OR Id <> @Id)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''importo ha già una riga con il minimo fatturabile';
				GOTO BRANCH_END;
			END
		END
		ELSE
		BEGIN
			-- Sola descrizione: una riga di testo per documento (il tipo "per documento" è il primo del modulo)
			SELECT TOP (1) @IdTipo = Id
			FROM dbo.tblImportiRigheTipi
			WHERE IdModulo = @idModulo
			ORDER BY Pos;

			SET @MinimoFatturabile = 0;
			SET @IdAliquotaIva = NULL;
			SET @IdConto = NULL;
		END

		-- Nuova riga: uspId_get FUORI dalla transazione
		DECLARE @nuova BIT = IIF(@Id IS NULL, 1, 0);
		IF @nuova = 1
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @Id OUTPUT;

		BEGIN TRANSACTION;
			IF @nuova = 1
			BEGIN
				-- In coda alle righe dell'importo
				DECLARE @pos INT;
				SELECT @pos = ISNULL(MAX(Pos), 0) + 1
				FROM dbo.tblImportiRighe WITH (UPDLOCK, HOLDLOCK)
				WHERE IdImporto = @IdImporto;

				INSERT dbo.tblImportiRighe (Id, IdImporto, IdTipo, Importo, MinimoFatturabile, Lock, Pos)
				VALUES (@Id, @IdImporto, @IdTipo, @Importo, @MinimoFatturabile, 0, @pos);
			END
			ELSE
			BEGIN
				UPDATE dbo.tblImportiRighe
				SET
					IdTipo = @IdTipo,
					Importo = @Importo,
					MinimoFatturabile = @MinimoFatturabile
				WHERE Id = @Id;
			END

			DELETE dbo.tblImportiRigheDettagli
			WHERE Id = @Id;

			INSERT dbo.tblImportiRigheDettagli (Id, IdAliquotaIva, IdConto, Descrizione)
			VALUES (@Id, @IdAliquotaIva, @IdConto, @Descrizione);
		COMMIT TRANSACTION;

		SELECT Id = @Id;

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
GO

PRINT 'sql/procedures/uspImportiRighe_del.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Toglie una riga da un importo (rifiuti, magazzino o servizi). La riga viene eliminata, senza ripristino:
-- come le righe delle fatture non ha uno stato proprio. Una riga che non esiste più non è un errore.
CREATE OR ALTER PROCEDURE dbo.uspImportiRighe_del
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
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF EXISTS (SELECT 1 FROM dbo.tblImportiRighe WHERE Id = @Id)
		BEGIN

		-- L'importo della riga deve esistere (in bozza o attivo), appartenere all'azienda interna corrente
		-- della sessione e il suo modulo deve essere attivo sul dominio
		DECLARE @idAzienda CHAR(16);
		DECLARE @idModulo CHAR(3);
		SELECT
			@idAzienda = i.IdSede,
			@idModulo = CASE
				WHEN r.Id IS NOT NULL THEN 'RIF'
				WHEN m.Id IS NOT NULL THEN 'MAG'
				WHEN s.Id IS NOT NULL THEN 'SRV'
			END
		FROM
			dbo.tblImportiRighe g
			INNER JOIN dbo.tblImporti i ON g.IdImporto = i.Id
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
			LEFT JOIN dbo.tblImportiServizi s ON i.Id = s.Id
		WHERE
			g.Id = @Id
			AND e.Id = @IdSessione
			AND i.Lock <= 2;

		IF @idAzienda IS NULL OR @idModulo IS NULL OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o l''importo non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DELETE dbo.tblImportiRigheDettagli
			WHERE Id = @Id;
			DELETE dbo.tblImportiRighe
			WHERE Id = @Id;
			DELETE dbo.tblIdLog
			WHERE Id = @Id;
			DELETE dbo.tblId
			WHERE Id = @Id;
		COMMIT TRANSACTION;

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
GO

PRINT 'sql/procedures/uspImportiRighe_upd_Pos.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Sposta su (@Direzione = -1) o giù (@Direzione = 1) una riga dell'importo. Prima dello scambio le righe
-- vengono rinumerate 1..n nell'ordine corrente, così i buchi lasciati dalle righe tolte non contano. Sulla
-- prima riga "su" e sull'ultima "giù" non fanno nulla.
CREATE OR ALTER PROCEDURE dbo.uspImportiRighe_upd_Pos
	@Id CHAR(16) = NULL,
	@Direzione SMALLINT = NULL,
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
		IF @Direzione IS NULL OR @Direzione NOT IN (-1, 1)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Direzione deve essere -1 (su) o 1 (giù)';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCI',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- L'importo della riga deve esistere (in bozza o attivo), appartenere all'azienda interna corrente
		-- della sessione e il suo modulo deve essere attivo sul dominio
		DECLARE @idImporto CHAR(16);
		DECLARE @idModulo CHAR(3);
		SELECT
			@idImporto = i.Id,
			@idModulo = CASE
				WHEN r.Id IS NOT NULL THEN 'RIF'
				WHEN m.Id IS NOT NULL THEN 'MAG'
				WHEN s.Id IS NOT NULL THEN 'SRV'
			END
		FROM
			dbo.tblImportiRighe g
			INNER JOIN dbo.tblImporti i ON g.IdImporto = i.Id
			INNER JOIN dbo.tblSessioni e ON i.IdSede = e.IdAzienda
			LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
			LEFT JOIN dbo.tblImportiServizi s ON i.Id = s.Id
		WHERE
			g.Id = @Id
			AND e.Id = @IdSessione
			AND i.Lock <= 2;

		IF @idImporto IS NULL OR @idModulo IS NULL OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la riga non esiste';
			GOTO BRANCH_END;
		END

		DECLARE @righe TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			PosAttuale INT NULL,
			PosNuova INT NOT NULL
		);

		BEGIN TRANSACTION;
			-- Stesso ordinamento di uspImportiRighe_get_List
			INSERT @righe (Id, PosAttuale, PosNuova)
			SELECT
				Id,
				Pos,
				ROW_NUMBER() OVER (ORDER BY ISNULL(Pos, 0), Id)
			FROM dbo.tblImportiRighe WITH (UPDLOCK, HOLDLOCK)
			WHERE IdImporto = @idImporto;

			DECLARE @pos INT, @posAltra INT;
			SELECT @pos = PosNuova
			FROM @righe
			WHERE Id = @Id;
			SET @posAltra = @pos + @Direzione;

			IF EXISTS (SELECT 1 FROM @righe WHERE PosNuova = @posAltra)
			BEGIN
				UPDATE @righe
				SET PosNuova = IIF(Id = @Id, @posAltra, @pos)
				WHERE PosNuova IN (@pos, @posAltra);
			END

			UPDATE g
			SET Pos = t.PosNuova
			FROM
				dbo.tblImportiRighe g
				INNER JOIN @righe t ON g.Id = t.Id
			WHERE ISNULL(t.PosAttuale, -1) <> t.PosNuova;
		COMMIT TRANSACTION;

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
GO

PRINT 'sql/procedures/uspOfferteContratti_ins.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Nuovo contratto (@Tipo = 'C') o nuova offerta (@Tipo = 'O') di un cliente, in bozza (Lock = 2), dell'azienda
-- interna corrente della sessione. La validità parte da oggi.
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_ins
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
		SET @Tipo = NULLIF(UPPER(LTRIM(RTRIM(@Tipo))), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'O')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (contratto) o O (offerta)';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il contratto appartiene all'azienda interna corrente della sessione
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

		BEGIN TRANSACTION;
			INSERT dbo.tblOfferteContratti (Id, IdSede, Tipo, ClienteFornitoreTipo, DataInizio, Lock)
			VALUES (@returnId, @idAzienda, @Tipo, 'C', CAST(GETDATE() AS DATE), 2);
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
GO

PRINT 'sql/procedures/uspOfferteContratti_get.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Scheda di un contratto o di un'offerta dell'azienda interna corrente della sessione (attivo o in bozza).
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_get
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
			@IdFunzione = 'OCC',
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
				dbo.tblOfferteContratti oc
				INNER JOIN dbo.tblSessioni e ON oc.IdSede = e.IdAzienda
			WHERE
				oc.Id = @Id
				AND e.Id = @IdSessione
				AND oc.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il contratto non esiste';
			GOTO BRANCH_END;
		END

		SELECT
			oc.Id,
			oc.IdSede,
			oc.IdClienteFornitore,
			oc.Tipo,
			oc.DataInizio,
			oc.DataFine,
			oc.Descrizione,
			oc.Protocollo,
			oc.Ordine,
			oc.DataOrdine,
			oc.CodiceCig,
			oc.CodiceCup,
			oc.Lock
		FROM dbo.tblOfferteContratti oc
		WHERE oc.Id = @Id;

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
GO

PRINT 'sql/procedures/uspOfferteContratti_upd.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva un contratto o un'offerta di un cliente e conferma la bozza (Lock 2 -> 0).
-- @Tipo: C contratto, O offerta. Si può cambiare: un'offerta accettata diventa contratto, con i suoi importi.
-- Solo gli importi di un contratto vengono applicati nella fatturazione, per i documenti con data compresa tra
-- inizio e fine: per questo le due date sono obbligatorie.
-- Ordine, CIG e CUP vengono riportati sulle fatture generate: stessi limiti della fattura (uspFatture_upd).
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_upd
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@DataInizio DATE = NULL,
	@DataFine DATE = NULL,
	@Descrizione VARCHAR(1000) = NULL,
	@Protocollo VARCHAR(50) = NULL,
	@Ordine VARCHAR(50) = NULL,
	@DataOrdine DATE = NULL,
	@CodiceCig VARCHAR(20) = NULL,
	@CodiceCup VARCHAR(20) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @Tipo = NULLIF(UPPER(LTRIM(RTRIM(@Tipo))), '');
		SET @Descrizione = NULLIF(LTRIM(RTRIM(@Descrizione)), '');
		SET @Protocollo = dbo.ufnStringhe_get_SenzaSpazi(@Protocollo, 0, 1);
		SET @Ordine = dbo.ufnStringhe_get_SenzaSpazi(@Ordine, 0, 1);
		SET @CodiceCig = NULLIF(REPLACE(UPPER(@CodiceCig), ' ', ''), '');
		SET @CodiceCup = NULLIF(REPLACE(UPPER(@CodiceCup), ' ', ''), '');

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
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'O')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il tipo: contratto oppure offerta';
			GOTO BRANCH_END;
		END
		IF @IdClienteFornitore IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il cliente';
			GOTO BRANCH_END;
		END
		IF @DataInizio IS NULL OR @DataFine IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare le date di inizio e di fine della validità';
			GOTO BRANCH_END;
		END
		IF @DataFine < @DataInizio
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine non può precedere la data di inizio';
			GOTO BRANCH_END;
		END
		IF LEN(@Ordine) > 30
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''ordine non può superare i 30 caratteri';
			GOTO BRANCH_END;
		END
		IF LEN(@CodiceCig) > 10
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il CIG non può superare i 10 caratteri';
			GOTO BRANCH_END;
		END
		IF LEN(@CodiceCup) > 15
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il CUP non può superare i 15 caratteri';
			GOTO BRANCH_END;
		END
		IF @DataOrdine IS NOT NULL AND @DataOrdine > @DataFine
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data dell''ordine non può seguire la data di fine della validità';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		DECLARE @idClienteFornitoreAttuale CHAR(16);
		SELECT
			@idAzienda = oc.IdSede,
			@idClienteFornitoreAttuale = oc.IdClienteFornitore
		FROM
			dbo.tblOfferteContratti oc
			INNER JOIN dbo.tblSessioni e ON oc.IdSede = e.IdAzienda
		WHERE
			oc.Id = @Id
			AND e.Id = @IdSessione;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Cliente: una scheda cliente attiva dell'azienda; quella già sul contratto resta valida
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblClientiFornitori
			WHERE
				Id = @IdClienteFornitore
				AND IdAziendaInterna = @idAzienda
				AND Tipo = 'C'
				AND (Lock = 0 OR Id = @idClienteFornitoreAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il cliente indicato non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblOfferteContratti
			SET
				Lock = 0,
				IdClienteFornitore = @IdClienteFornitore,
				Tipo = @Tipo,
				ClienteFornitoreTipo = 'C',
				DataInizio = @DataInizio,
				DataFine = @DataFine,
				Descrizione = @Descrizione,
				Protocollo = @Protocollo,
				Ordine = @Ordine,
				DataOrdine = @DataOrdine,
				CodiceCig = @CodiceCig,
				CodiceCup = @CodiceCup
			WHERE
				Id = @Id
				AND Lock <= 2;

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Contratto non trovato o già eliminato';
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
GO

PRINT 'sql/procedures/uspOfferteContratti_del.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Cancella un contratto o un'offerta dell'azienda interna corrente della sessione.
-- Con importi associati non si cancella, né attivo né in bozza: gli importi vanno prima tolti, perché un importo
-- senza contratto è un importo standard, valido per tutti i clienti, e non deve diventarlo senza che lo si voglia.
-- Attivo: cancellazione con ripristino (Lock 4). In bozza: eliminato.
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_del
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
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblOfferteContratti WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità)
		DECLARE @lock INT;
		DECLARE @tipo CHAR(1);
		SELECT
			@lock = oc.Lock,
			@tipo = oc.Tipo
		FROM
			dbo.tblOfferteContratti oc
			INNER JOIN dbo.tblSessioni e ON oc.IdSede = e.IdAzienda
		WHERE
			oc.Id = @Id
			AND e.Id = @IdSessione;

		IF @lock IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @lock IN (0, 2) AND EXISTS (SELECT 1 FROM dbo.tblOfferteContrattiImporti WHERE IdOffertaContratto = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = IIF(@tipo = 'O', 'Un''offerta', 'Un contratto') + ' con importi associati non può essere '
				+ IIF(@tipo = 'O', 'cancellata', 'cancellato') + ': togliere prima gli importi';
			GOTO BRANCH_END;
		END

		-- ── CASO 1: attivo (Lock = 0) → soft delete ──────────────────────────
		IF @lock = 0
		BEGIN
			BEGIN TRANSACTION;
				UPDATE dbo.tblOfferteContratti
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Contratto non trovato o già eliminato';
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

		-- ── CASO 2: in bozza (Lock = 2) → hard delete ────────────────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblOfferteContratti
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellato (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il contratto è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
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
GO

PRINT 'sql/procedures/uspOfferteContratti_del_Undo.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Ripristina i contratti e le offerte cancellati con l'ultima cancellazione della sessione.
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_del_Undo
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

		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;

		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			UPDATE i
			SET Lock = 0
			FROM dbo.tblOfferteContratti i
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
GO

PRINT 'sql/procedures/uspOfferteContratti_get_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Offerte e contratti > Contratti clienti (@Tipo = 'C') e Offerte clienti (@Tipo = 'O'): elenco dell'azienda
-- interna corrente della sessione. Righe, scope e ricerca sono in ufnOfferteContratti_get_List, comune
-- all'esportazione. @SoloInVigore = 1: solo quelli validi oggi (data di oggi tra inizio e fine).
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_get_List
	@PageNumber INT = 1,
	@RowsPerPage INT = 50,
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Search VARCHAR(50) = NULL,
	@SoloInVigore BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = NULLIF(UPPER(LTRIM(RTRIM(@Tipo))), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @SoloInVigore = ISNULL(@SoloInVigore, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'O')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (contratto) o O (offerta)';
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
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);

		SELECT
			t.Id,
			t.StatoValore,
			t.StatoDescrizione,
			t.Cliente,
			t.Tipo,
			t.DataInizio,
			t.DataFine,
			t.Descrizione,
			t.Protocollo,
			t.Importi,
			RowsCount = COUNT(*) OVER ()
		FROM dbo.ufnOfferteContratti_get_List(@IdSessione, @Tipo, @Search) t
		WHERE
			@SoloInVigore = 0
			OR (t.DataInizio <= @oggi AND t.DataFine >= @oggi)
		ORDER BY t.Cliente, t.DataInizio DESC, t.Id
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
GO

PRINT 'sql/procedures/uspOfferteContratti_get_Esportazione.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Contratti clienti e Offerte clienti: righe per l'esportazione dell'elenco in Excel e in CSV (Azioni > Esporta
-- in Excel, Esporta in CSV). Il nome di ogni colonna è l'intestazione che finisce nel file: l'applicazione
-- (ExcelService, CsvService) scrive le colonne così come arrivano, nello stesso ordine. Per cambiare che cosa
-- si esporta si modifica solo questa SP.
-- Stesse righe e stesso ordine dell'elenco: scope e criteri di ricerca sono in ufnOfferteContratti_get_List,
-- comune a uspOfferteContratti_get_List; il filtro @SoloInVigore è ricopiato da quella e va tenuto allineato.
-- Tutte le righe, senza paginazione: al massimo @MaxRighe + 1 (la riga in più dice all'applicazione che la
-- ricerca va ristretta).
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_get_Esportazione
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@Search VARCHAR(50) = NULL,
	@SoloInVigore BIT = 0,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = NULLIF(UPPER(LTRIM(RTRIM(@Tipo))), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);
		SET @SoloInVigore = ISNULL(@SoloInVigore, 0);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 50000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Tipo IS NULL OR @Tipo NOT IN ('C', 'O')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Tipo deve essere C (contratto) o O (offerta)';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @oggi DATE = CAST(GETDATE() AS DATE);

		SELECT TOP (@MaxRighe + 1)
			[Cliente] = t.Cliente,
			[Indirizzo] = t.ClienteIndirizzo,
			[Partita IVA] = t.ClientePartitaIva,
			[Codice fiscale] = t.ClienteCodiceFiscale,
			[Dal] = t.DataInizio,
			[Al] = t.DataFine,
			[Stato] = t.StatoDescrizione,
			[Descrizione] = t.Descrizione,
			[Protocollo] = t.Protocollo,
			[Ordine] = t.Ordine,
			[Data ordine] = t.DataOrdine,
			[CIG] = t.CodiceCig,
			[CUP] = t.CodiceCup,
			[Importi] = t.Importi
		FROM dbo.ufnOfferteContratti_get_List(@IdSessione, @Tipo, @Search) t
		WHERE
			@SoloInVigore = 0
			OR (t.DataInizio <= @oggi AND t.DataFine >= @oggi)
		ORDER BY t.Cliente, t.DataInizio DESC, t.Id
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
GO

PRINT 'sql/procedures/uspOfferteContratti_get_Importi_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Importi di un contratto o di un'offerta dell'azienda interna corrente della sessione.
--   @Disponibili = 0: gli importi associati al contratto @Id (tutti, anche di un modulo non più attivo sul
--                     dominio: ModuloAttivo = 0, così si vedono e si possono togliere)
--   @Disponibili = 1: gli importi attivi dell'azienda che si possono associare: non associati ad alcun contratto
--                     o offerta (un importo sta in uno solo) e di un modulo attivo sul dominio; al massimo 50,
--                     filtrabili con @Search
-- Si legge con il permesso sui contratti (OCC): non serve quello sugli importi (OCI).
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_get_Importi_List
	@Id CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Disponibili BIT = 0,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Disponibili = ISNULL(@Disponibili, 0);
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

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
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = oc.IdSede
		FROM
			dbo.tblOfferteContratti oc
			INNER JOIN dbo.tblSessioni e ON oc.IdSede = e.IdAzienda
		WHERE
			oc.Id = @Id
			AND e.Id = @IdSessione
			AND oc.Lock <= 2;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il contratto non esiste';
			GOTO BRANCH_END;
		END

		-- Moduli dei documenti attivi sul dominio: pre-calcolati FUORI dalla query
		DECLARE @rifAttivo BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('RIF', @IdSessione), 0);
		DECLARE @magAttivo BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('MAG', @IdSessione), 0);
		DECLARE @srvAttivo BIT = ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('SRV', @IdSessione), 0);

		SELECT TOP (IIF(@Disponibili = 1, 50, 100000))
			t.Id,
			t.IdModulo,
			Modulo = CASE t.IdModulo WHEN 'RIF' THEN 'Rifiuti' WHEN 'MAG' THEN 'Magazzino' WHEN 'SRV' THEN 'Servizi' END,
			t.ModuloAttivo,
			t.Nome,
			Priorita = p.Nome,
			Righe = (SELECT COUNT(*) FROM dbo.tblImportiRighe g WHERE g.IdImporto = t.Id)
		FROM
			(
				SELECT
					i.Id,
					i.Nome,
					i.IdPriorita,
					IdModulo = CAST(CASE
						WHEN r.Id IS NOT NULL THEN 'RIF'
						WHEN m.Id IS NOT NULL THEN 'MAG'
						WHEN v.Id IS NOT NULL THEN 'SRV'
					END AS CHAR(3)),
					ModuloAttivo = CAST(CASE
						WHEN r.Id IS NOT NULL THEN @rifAttivo
						WHEN m.Id IS NOT NULL THEN @magAttivo
						WHEN v.Id IS NOT NULL THEN @srvAttivo
						ELSE 0
					END AS BIT),
					Associato = IIF(ci.IdImporto IS NULL, 0, 1),
					Suo = IIF(ci.IdOffertaContratto = @Id, 1, 0)
				FROM
					dbo.tblImporti i
					LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
					LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
					LEFT JOIN dbo.tblImportiServizi v ON i.Id = v.Id
					LEFT JOIN dbo.tblOfferteContrattiImporti ci ON i.Id = ci.IdImporto
				WHERE
					i.IdSede = @idAzienda
					AND i.Lock = 0
			) t
			LEFT JOIN dbo.tblImportiPriorita p ON t.IdPriorita = p.Id
		WHERE
			(
				@Disponibili = 0
				AND t.Suo = 1
			)
			OR
			(
				@Disponibili = 1
				AND t.Associato = 0
				AND t.ModuloAttivo = 1
				AND (@Search IS NULL OR t.Nome LIKE '%' + @Search + '%')
			)
		ORDER BY t.IdModulo, t.Nome, t.Id
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
GO

PRINT 'sql/procedures/uspOfferteContratti_ins_Importo.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Associa un importo a un contratto o a un'offerta (attivo o in bozza) dell'azienda interna corrente della
-- sessione. Un importo sta in un solo contratto o offerta (UX_OfferteContrattiImporti_IdImporto): quello già
-- associato altrove non si sposta da qui, va prima tolto dall'altro. L'importo deve essere attivo, della stessa
-- azienda e di un modulo attivo sul dominio. Già associato a questo contratto: nessuna azione.
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_ins_Importo
	@Id CHAR(16) = NULL,
	@IdImporto CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdImporto = NULLIF(LTRIM(RTRIM(@IdImporto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdImporto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdImporto non può essere vuoto';
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
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = oc.IdSede
		FROM
			dbo.tblOfferteContratti oc
			INNER JOIN dbo.tblSessioni e ON oc.IdSede = e.IdAzienda
		WHERE
			oc.Id = @Id
			AND e.Id = @IdSessione
			AND oc.Lock <= 2;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il contratto non esiste';
			GOTO BRANCH_END;
		END

		-- L'importo: attivo, della stessa azienda, di un modulo attivo sul dominio
		DECLARE @idModulo CHAR(3);
		SELECT
			@idModulo = CASE
				WHEN r.Id IS NOT NULL THEN 'RIF'
				WHEN m.Id IS NOT NULL THEN 'MAG'
				WHEN v.Id IS NOT NULL THEN 'SRV'
			END
		FROM
			dbo.tblImporti i
			LEFT JOIN dbo.tblImportiRifiuti r ON i.Id = r.Id
			LEFT JOIN dbo.tblImportiMagazzino m ON i.Id = m.Id
			LEFT JOIN dbo.tblImportiServizi v ON i.Id = v.Id
		WHERE
			i.Id = @IdImporto
			AND i.IdSede = @idAzienda
			AND i.Lock = 0;

		IF @idModulo IS NULL OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione(@idModulo, @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importo indicato non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DECLARE @idAltro CHAR(16);
			SELECT @idAltro = IdOffertaContratto
			FROM dbo.tblOfferteContrattiImporti WITH (UPDLOCK, HOLDLOCK)
			WHERE IdImporto = @IdImporto;

			IF @idAltro IS NOT NULL AND @idAltro <> @Id
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'L''importo è già associato a un altro contratto o a un''altra offerta';
				GOTO BRANCH_END;
			END

			IF @idAltro IS NULL
				INSERT dbo.tblOfferteContrattiImporti (IdOffertaContratto, IdImporto)
				VALUES (@Id, @IdImporto);
		COMMIT TRANSACTION;

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
GO

PRINT 'sql/procedures/uspOfferteContratti_del_Importo.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Toglie un importo da un contratto o da un'offerta (attivo o in bozza) dell'azienda interna corrente della
-- sessione. L'importo non viene cancellato: senza contratto torna a essere un importo standard, valido per
-- tutti i clienti. Un importo che non è (più) associato non è un errore.
CREATE OR ALTER PROCEDURE dbo.uspOfferteContratti_del_Importo
	@Id CHAR(16) = NULL,
	@IdImporto CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdImporto = NULLIF(LTRIM(RTRIM(@IdImporto)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');

		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdImporto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdImporto non può essere vuoto';
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
			@IdFunzione = 'OCC',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record: scope azienda interna corrente della sessione
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblOfferteContratti oc
				INNER JOIN dbo.tblSessioni e ON oc.IdSede = e.IdAzienda
			WHERE
				oc.Id = @Id
				AND e.Id = @IdSessione
				AND oc.Lock <= 2
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o il contratto non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			DELETE dbo.tblOfferteContrattiImporti
			WHERE
				IdOffertaContratto = @Id
				AND IdImporto = @IdImporto;
		COMMIT TRANSACTION;

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
GO

PRINT 'sql/procedures/uspFattureDocumenti_get.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione di un documento (blocco "Cliente a cui fatturare", comune alle schede di registrazioni dei
-- rifiuti, DDT di magazzino e servizi): cliente indicato sul documento, spunta "Non fatturabile", fattura in
-- cui è finito e l'anteprima di ciò che la generazione automatica userebbe ("Verifica importo e cliente":
-- cliente, importo, contratto, totale e avvisi). Le righe dell'anteprima: uspFattureDocumenti_get_Righe.
-- @IdModulo: RIF registrazione dei rifiuti (MAG e SRV non ancora gestiti: nessuna riga).
-- Sempre una riga al massimo; nessuna riga (e nessun errore) se il blocco non va mostrato: modulo Offerte e
-- contratti non attivo sul dominio, documento non accessibile, operazione non fatturabile, rettifica. Così la
-- scheda del documento non dipende da questo modulo.
--   Modificabile: permesso di modifica sul documento, documento confermato e non ancora fatturato.
--   Fatturabile: la generazione automatica lo fatturerebbe (nessun avviso bloccante).
--   Avvisi: testi separati da '|'.
-- L'azienda è quella del documento (per i rifiuti, del registro), non quella del contesto della sessione.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_get
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
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

		-- Solo registrazioni dei rifiuti, con il modulo Offerte e contratti attivo sul dominio e almeno la
		-- lettura delle registrazioni
		DECLARE @permesso TINYINT = dbo.ufnFunzioni_get_PermessoBySessione('RRG', @IdSessione);
		IF ISNULL(@IdModulo, '') = 'RIF'
			AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 1
			AND @permesso >= 1
		BEGIN
			SELECT
				a.Id,
				IdModulo = CAST('RIF' AS CHAR(3)),
				Modificabile = CAST(IIF(@permesso >= 2 AND a.Lock = 0 AND a.IdFattura IS NULL, 1, 0) AS BIT),
				IdClienteIndicato = a.IdClienteIndicato,
				ClienteIndicato = si.NomeCompleto + ISNULL(' ' + si.IndirizzoCompleto, ''),
				a.NonFatturabile,
				a.IdFattura,
				Fattura = IIF(a.IdFattura IS NULL, NULL, IIF(f.IdTipo = 'TD00', 'Pre-fattura', 'Fattura'))
					+ ISNULL(' ' + CAST(f.Numero AS VARCHAR(10)) + ISNULL('/' + f.Sezionale, ''), '')
					+ ISNULL(' del ' + CONVERT(VARCHAR(10), f.DataEmissione, 103), ''),
				-- Anteprima
				a.IdClienteFornitore,
				Cliente = sc.NomeCompleto + ISNULL(' ' + sc.IndirizzoCompleto, ''),
				a.ClienteOrigine,
				ClienteOrigineDescrizione = CASE a.ClienteOrigine
					WHEN 'D' THEN 'indicato sulla registrazione'
					WHEN 'C' THEN 'dal contratto dell''importo'
					WHEN 'P' THEN 'produttore del rifiuto (importo standard)'
				END,
				a.IdImporto,
				Importo = i.Nome,
				Priorita = p.Nome,
				Contratto = CASE
					WHEN a.IdImporto IS NULL THEN NULL
					WHEN a.IdOffertaContratto IS NULL THEN 'Nessuno (importo standard)'
					ELSE 'Contratto' + ISNULL(' ' + so.NomeCompleto, '')
						+ ISNULL(' dal ' + CONVERT(VARCHAR(10), oc.DataInizio, 103), '')
						+ ISNULL(' al ' + CONVERT(VARCHAR(10), oc.DataFine, 103), '')
				END,
				Totale = t.Totale,
				Fatturabile = CAST(IIF(
					a.Lock = 0 AND a.IsAnnullata = 0 AND a.NonFatturabile = 0 AND a.IdFattura IS NULL
					AND a.IdImporto IS NOT NULL AND a.IdClienteFornitore IS NOT NULL AND ISNULL(t.Righe, 0) > 0 AND ISNULL(t.SenzaIva, 0) = 0, 1, 0) AS BIT),
				Avvisi = CAST(STUFF(
					IIF(a.Lock <> 0, '|La registrazione non è ancora salvata: salvarla prima di fatturarla', '')
					+ IIF(a.IdFattura IS NOT NULL, '|La registrazione è già stata fatturata', '')
					+ IIF(a.NonFatturabile = 1, '|La registrazione è indicata come non fatturabile', '')
					+ IIF(a.IsAnnullata = 1, '|La registrazione è annullata: non viene fatturata', '')
					+ IIF(a.IdImporto IS NULL, '|Nessun importo coincide con la registrazione: non viene fatturata', '')
					+ IIF(a.IdImportoScartato IS NOT NULL, '|L''importo "' + ISNULL(isc.Nome, '') + '" coincide con la registrazione, ma il suo contratto non è valido alla data della registrazione'
						+ IIF(a.IdImporto IS NOT NULL AND a.IdOffertaContratto IS NULL, ': è stato applicato l''importo standard', ''), '')
					+ IIF(a.IdClienteFornitore IS NULL, '|Cliente non determinato: il produttore non ha una scheda cliente. Indicare il cliente sulla registrazione', '')
					+ IIF(a.IdClienteFornitore IS NOT NULL AND ISNULL(t.SenzaIva, 0) > 0, '|Aliquota IVA non indicata né sulle righe dell''importo né sulla scheda del cliente', '')
					+ IIF(a.IdImporto IS NOT NULL AND ISNULL(t.Righe, 0) = 0, '|L''importo non ha righe applicabili a questa registrazione', '')
					+ IIF(a.IdImporto IS NOT NULL AND q.RigheQuantita > 0 AND ISNULL(t.RigheQuantita, 0) = 0, '|L''importo non ha righe per l''unità di misura della registrazione (' + ISNULL(a.IdUnitaMisura, 'non indicata') + ')', '')
					, 1, 1, '') AS VARCHAR(2000))
			FROM
				dbo.ufnImportiRifiuti_get_Applicazione(@Id) a
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeRegistro = x.Id
				LEFT JOIN dbo.tblClientiFornitori ci ON a.IdClienteIndicato = ci.Id
				LEFT JOIN dbo.tblSedi si ON ci.IdSede = si.Id
				LEFT JOIN dbo.tblClientiFornitori cc ON a.IdClienteFornitore = cc.Id
				LEFT JOIN dbo.tblSedi sc ON cc.IdSede = sc.Id
				LEFT JOIN dbo.tblFatture f ON a.IdFattura = f.Id
				LEFT JOIN dbo.tblImporti i ON a.IdImporto = i.Id
				LEFT JOIN dbo.tblImportiPriorita p ON i.IdPriorita = p.Id
				LEFT JOIN dbo.tblImporti isc ON a.IdImportoScartato = isc.Id
				LEFT JOIN dbo.tblOfferteContratti oc ON a.IdOffertaContratto = oc.Id
				LEFT JOIN dbo.tblClientiFornitori co ON oc.IdClienteFornitore = co.Id
				LEFT JOIN dbo.tblSedi so ON co.IdSede = so.Id
				OUTER APPLY (
					-- Righe che entrano in fattura: totale, numero, e quante sono a quantità (KG, T, L)
					SELECT
						Totale = SUM(ISNULL(g.Imponibile, 0)),
						Righe = COUNT(*),
						SenzaIva = SUM(IIF(g.SolaDescrizione = 0 AND g.IdAliquotaIva IS NULL, 1, 0)),
						RigheQuantita = SUM(IIF(g.SolaDescrizione = 0 AND g.MinimoFatturabile = 0 AND g.IdTipo <> 'RM', 1, 0))
					FROM dbo.ufnImportiRifiuti_get_ApplicazioneRighe(@Id) g
				) t
				OUTER APPLY (
					-- Righe a quantità dell'importo, comprese quelle che non valgono per l'unità della registrazione
					SELECT RigheQuantita = COUNT(*)
					FROM dbo.tblImportiRighe g
					WHERE
						g.IdImporto = a.IdImporto
						AND g.Importo IS NOT NULL
						AND ISNULL(g.MinimoFatturabile, 0) = 0
						AND g.IdTipo <> 'RM'
				) q
			WHERE
				a.IsFatturabile = 1
				AND a.IsRettifica = 0
			OPTION (RECOMPILE);
		END

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
GO

PRINT 'sql/procedures/uspFattureDocumenti_get_Righe.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- "Verifica importo e cliente": righe di fattura che la generazione automatica creerebbe per il documento, con
-- l'importo che gli viene applicato (ufnImportiRifiuti_get_ApplicazioneRighe). Stessi controlli di accesso di
-- uspFattureDocumenti_get: senza accesso, o per un modulo non gestito, nessuna riga e nessun errore.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_get_Righe
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
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

		IF ISNULL(@IdModulo, '') = 'RIF'
			AND ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 1
			AND dbo.ufnFunzioni_get_PermessoBySessione('RRG', @IdSessione) >= 1
		BEGIN
			SELECT
				g.Id,
				g.Pos,
				g.Descrizione,
				g.SolaDescrizione,
				g.MinimoFatturabile,
				g.Quantita,
				UnitaMisura = g.IdUnitaMisura,
				g.Importo,
				g.Imponibile,
				AliquotaIvaNome = v.Nome,
				ContoNome = ISNULL(c.Codice + ' - ', '') + c.Nome
			FROM
				dbo.ufnImportiRifiuti_get_Applicazione(@Id) a
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeRegistro = x.Id
				CROSS APPLY dbo.ufnImportiRifiuti_get_ApplicazioneRighe(a.Id) g
				LEFT JOIN dbo.tblAliquoteIva v ON g.IdAliquotaIva = v.Id
				LEFT JOIN dbo.tblFattureConti c ON g.IdConto = c.Id
			WHERE
				a.IsFatturabile = 1
				AND a.IsRettifica = 0
			ORDER BY ISNULL(g.Pos, 0), g.Id
			OPTION (RECOMPILE);
		END

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
GO

PRINT 'sql/procedures/uspFattureDocumenti_upd.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Salva sul documento (registrazione dei rifiuti; DDT e servizi non ancora gestiti) il cliente a cui fatturarlo
-- e la spunta "Non fatturabile". Si salvano da soli, senza il "Salva" della scheda: valgono anche per una
-- registrazione già inviata al RENTRI, che non si può più modificare, perché non fanno parte del registro.
--   @IdClienteFornitore NULL: nessun cliente indicato (lo decide l'importo applicato).
-- Serve il permesso di modifica sul documento; il documento deve essere confermato e non ancora fatturato.
-- Senza cliente e senza spunta la riga di tblFattureDocumenti viene tolta.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_upd
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@NonFatturabile BIT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @NonFatturabile = ISNULL(@NonFatturabile, 0);

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
		IF ISNULL(@IdModulo, '') <> 'RIF'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo deve essere RIF';
			GOTO BRANCH_END;
		END

		-- Permesso di modifica sulle registrazioni e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il documento: accessibile dalla sessione (titolarità sulla sede del registro), di un'operazione
		-- fatturabile, non una rettifica
		DECLARE @idAzienda CHAR(16);
		DECLARE @lock INT;
		DECLARE @idFattura CHAR(16);
		DECLARE @idClienteAttuale CHAR(16);
		SELECT
			@idAzienda = a.IdAzienda,
			@lock = a.Lock,
			@idFattura = a.IdFattura,
			@idClienteAttuale = a.IdClienteIndicato
		FROM
			dbo.ufnImportiRifiuti_get_Applicazione(@Id) a
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON a.IdSedeRegistro = x.Id
		WHERE
			a.IsFatturabile = 1
			AND a.IsRettifica = 0;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la registrazione non è fatturabile';
			GOTO BRANCH_END;
		END
		IF @lock <> 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Salvare la registrazione prima di indicare il cliente';
			GOTO BRANCH_END;
		END
		IF @idFattura IS NOT NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione è già stata fatturata: cliente e spunta non si possono più modificare';
			GOTO BRANCH_END;
		END

		-- Cliente: una scheda cliente attiva dell'azienda del documento; quella già indicata resta valida
		IF @IdClienteFornitore IS NOT NULL AND NOT EXISTS (
			SELECT 1
			FROM dbo.tblClientiFornitori
			WHERE
				Id = @IdClienteFornitore
				AND IdAziendaInterna = @idAzienda
				AND Tipo = 'C'
				AND (Lock = 0 OR Id = @idClienteAttuale)
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il cliente indicato non esiste';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			IF @IdClienteFornitore IS NULL AND @NonFatturabile = 0
			BEGIN
				-- Nulla da ricordare: la riga resta solo se porta ancora il legame con una fattura cancellata
				DELETE dbo.tblFattureDocumenti
				WHERE
					Id = @Id
					AND IdFattura IS NULL;

				UPDATE dbo.tblFattureDocumenti
				SET
					IdClienteFornitore = NULL,
					NonFatturabile = 0
				WHERE Id = @Id;
			END
			ELSE
			BEGIN
				UPDATE dbo.tblFattureDocumenti WITH (UPDLOCK, HOLDLOCK)
				SET
					IdClienteFornitore = @IdClienteFornitore,
					NonFatturabile = @NonFatturabile
				WHERE Id = @Id;

				IF @@ROWCOUNT = 0
					INSERT dbo.tblFattureDocumenti (Id, IdModulo, IdClienteFornitore, NonFatturabile)
					VALUES (@Id, 'RIF', @IdClienteFornitore, @NonFatturabile);
			END
		COMMIT TRANSACTION;

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
GO

PRINT 'sql/procedures/uspFattureDocumenti_get_Clienti_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Clienti tra cui scegliere quello a cui fatturare un documento (link "Seleziona" del blocco "Cliente a cui
-- fatturare"): schede cliente attive dell'azienda del documento (per i rifiuti, quella del registro: non
-- quella del contesto della sessione), al massimo 50, filtrabili per nome, partita IVA o codice fiscale.
-- Si legge con il permesso sul documento, senza quello sulle anagrafiche dei clienti.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_get_Clienti_List
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

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
		IF ISNULL(@IdModulo, '') <> 'RIF'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo deve essere RIF';
			GOTO BRANCH_END;
		END

		-- Permesso di modifica sulle registrazioni e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Azienda del documento, se accessibile dalla sessione
		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = s.IdAziendaInterna
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON g.IdSede = x.Id
		WHERE r.Id = @Id;

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SELECT TOP (50)
			c.Id,
			[Text] = CAST(s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') AS VARCHAR(500)),
			Selected = CAST(0 AS BIT)
		FROM
			dbo.tblClientiFornitori c
			INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
		WHERE
			c.IdAziendaInterna = @idAzienda
			AND c.Tipo = 'C'
			AND c.Lock = 0
			AND ISNULL(s.Disabilitata, 0) = 0
			AND
				(
				@Search IS NULL
				OR s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') LIKE '%' + @Search + '%'
				OR s.PartitaIva LIKE '%' + @Search + '%'
				OR s.CodiceFiscale LIKE '%' + @Search + '%'
				)
		ORDER BY s.NomeCompleto, c.Id
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
GO

PRINT 'sql/procedures/uspFattureDocumenti_del_Fattura.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- "Togli la fattura": scollega il documento (registrazione dei rifiuti; DDT e servizi non ancora gestiti) dalla
-- fattura in cui è stato fatturato. La fattura NON viene cancellata né modificata: le sue righe restano come
-- sono. Il documento torna fatturabile, quindi una nuova generazione lo fatturerebbe di nuovo.
-- Cliente indicato e spunta "Non fatturabile" restano; importo e contratto applicati alla generazione vengono
-- azzerati. Serve il permesso di modifica sul documento. Un documento non fatturato non è un errore.
CREATE OR ALTER PROCEDURE dbo.uspFattureDocumenti_del_Fattura
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@IdSessione CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
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
		IF ISNULL(@IdModulo, '') <> 'RIF'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo deve essere RIF';
			GOTO BRANCH_END;
		END

		-- Permesso di modifica sulle registrazioni e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RRG',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Il documento deve essere accessibile dalla sessione (titolarità sulla sede del registro)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON g.IdSede = x.Id
			WHERE r.Id = @Id
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;
			UPDATE dbo.tblFattureDocumenti
			SET
				IdFattura = NULL,
				IdImporto = NULL,
				IdOffertaContratto = NULL
			WHERE Id = @Id;

			-- Nulla da ricordare: né cliente indicato né spunta
			DELETE dbo.tblFattureDocumenti
			WHERE
				Id = @Id
				AND IdClienteFornitore IS NULL
				AND ISNULL(NonFatturabile, 0) = 0;
		COMMIT TRANSACTION;

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
GO

PRINT 'sql/procedures/uspFatture_get_Genera_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione > Fatture clienti > Nuova > Tramite procedura automatica: elenco di dettaglio della verifica
-- ("Visualizza" sulle righe della finestra "Verifica"; i conteggi sono in uspFatture_get_Genera_Riepilogo).
-- Elenca i documenti (per ora le registrazioni dei rifiuti) dell'azienda interna corrente della sessione con data
-- nell'intervallo, con il cliente, l'importo e l'imponibile che la generazione userebbe e l'esito:
-- Fatturabile = 1 entra in una fattura, altrimenti Avviso dice perché resta fuori. Stesse righe di
-- uspFatture_ins_Genera (ufnFattureGenera_get_Documenti).
--   @Rifiuti = 0: le registrazioni dei rifiuti non sono state scelte (nessuna riga, finché è l'unico modulo).
--   @IdClienteFornitore: solo i documenti riconducibili a quel cliente.
--   @IncludiPreFatture = 1: anche i documenti già in una pre-fattura, che verrà convertita in fattura con le
--        sue righe; l'imponibile della pre-fattura è riportato sul suo primo documento.
--   @Esito: solo i documenti con quell'esito (codici di ufnFattureGenera_get_Documenti.Esito); F = tutti quelli
--        che entrano in una fattura (F, S e P). NULL: tutti.
-- I documenti già in una fattura non compaiono; quelli annullati sì, con il loro avviso.
-- Al massimo @MaxRighe righe (predefinito 1000): RowsCount dice quante sono in tutto.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Genera_List
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@Esito CHAR(1) = NULL,
	@Rifiuti BIT = 1,
	@IncludiPreFatture BIT = 0,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @Esito = NULLIF(UPPER(LTRIM(RTRIM(@Esito))), '');
		SET @Rifiuti = ISNULL(@Rifiuti, 1);
		SET @IncludiPreFatture = ISNULL(@IncludiPreFatture, 0);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 1000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataDa IS NULL OR @DataA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il periodo dei documenti da fatturare';
			GOTO BRANCH_END;
		END
		IF @DataA < @DataDa
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine del periodo non può precedere quella di inizio';
			GOTO BRANCH_END;
		END

		-- Permesso sulle fatture e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Senza azienda nel contesto nessuna riga
		SELECT TOP (@MaxRighe)
			d.Id,
			IdModulo = CAST('RIF' AS CHAR(3)),
			Documento = CAST('Registrazione' + ISNULL(' n. ' + CAST(d.Numero AS VARCHAR(10)), '')
				+ ISNULL(' - EER ' + e.Nome + IIF(e.Pericoloso = 1, '*', ''), '') AS VARCHAR(100)),
			d.[Data],
			d.Quantita,
			UnitaMisura = d.IdUnitaMisura,
			Cliente = sc.NomeCompleto,
			Importo = CAST(IIF(d.IdPreFattura IS NULL, i.Nome, 'Righe della pre-fattura') AS VARCHAR(50)),
			Contratto = CAST(IIF(d.IdPreFattura IS NULL AND d.IdOffertaContratto IS NOT NULL, 1, 0) AS BIT),
			PreFattura = CAST(IIF(d.IdPreFattura IS NULL, 0, 1) AS BIT),
			-- Pre-fattura: il suo imponibile una volta sola, sul primo dei suoi documenti
			Totale = d.Imponibile,
			d.Fatturabile,
			d.Esito,
			Avviso = CAST(CASE d.Esito
				WHEN 'P' THEN 'In pre-fattura del ' + ISNULL(CONVERT(VARCHAR(10), f.DataEmissione, 103), '') + ': viene convertita in fattura con le sue righe'
				WHEN 'S' THEN 'Contratto non valido alla data: applicato l''importo standard'
				WHEN 'A' THEN 'Registrazione annullata'
				WHEN 'N' THEN 'Indicata come non fatturabile'
				WHEN 'I' THEN 'Nessun importo coincide'
				WHEN 'C' THEN 'Cliente non determinato: il produttore non ha una scheda cliente'
				WHEN 'R' THEN 'L''importo non ha righe applicabili'
				WHEN 'V' THEN 'Aliquota IVA non indicata né sull''importo né sulla scheda del cliente'
			END AS VARCHAR(200)),
			RowsCount = COUNT(*) OVER ()
		FROM
			dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, NULL, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture) d
			LEFT JOIN dbo.tblRifiutiEer e ON d.IdEer = e.Id
			LEFT JOIN dbo.tblClientiFornitori c ON d.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi sc ON c.IdSede = sc.Id
			LEFT JOIN dbo.tblImporti i ON d.IdImporto = i.Id
			LEFT JOIN dbo.tblFatture f ON d.IdPreFattura = f.Id
		WHERE
			@Rifiuti = 1
			AND
				(
				@Esito IS NULL
				OR (@Esito = 'F' AND d.Fatturabile = 1)
				OR (@Esito <> 'F' AND d.Esito = @Esito)
				)
		ORDER BY d.Fatturabile DESC, sc.NomeCompleto, d.[Data], d.Numero, d.Id
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
GO

PRINT 'sql/procedures/uspFatture_get_Genera_Riepilogo.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione > Fatture clienti > Nuova > Tramite procedura automatica: riepilogo della verifica, mostrato nella
-- finestra "Verifica" prima di generare. Una riga con i conteggi di ciò che la generazione farebbe con gli stessi
-- criteri (stessi documenti e stessi gruppi di uspFatture_ins_Genera: ufnFattureGenera_get_Documenti), calcolati
-- su tutti i documenti, senza limite di righe.
--   Documenti: documenti del periodo non ancora fatturati (con @IncludiPreFatture anche quelli in pre-fattura).
--   Fatturabili, Fatture, Clienti, Imponibile: documenti che entrano in una fattura, fatture previste (una per
--        cliente e, secondo la scheda del cliente, per sede o per contratto), clienti e imponibile totale.
--   PreFatture, DocumentiPreFatture: pre-fatture che verrebbero convertite e loro documenti nel periodo.
--   ImportoStandard: fatturabili con l'importo standard perché il contratto non è valido alla data.
--   Annullati, NonFatturabili, SenzaImporto, SenzaCliente, SenzaRighe, SenzaIva: documenti che restano fuori,
--        per motivo (uno solo per documento, nell'ordine di ufnFattureGenera_get_Documenti.Esito).
--   GiaFatturati: documenti del periodo già in una fattura (solo informativo: non rientrano).
--   InPreFattura: documenti del periodo già in una pre-fattura, quando non si includono le pre-fatture.
-- @Rifiuti = 0: le registrazioni dei rifiuti non sono state scelte (tutto a zero, finché è l'unico modulo).
-- Senza azienda nel contesto tutto a zero.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Genera_Riepilogo
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@Rifiuti BIT = 1,
	@IncludiPreFatture BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @Rifiuti = ISNULL(@Rifiuti, 1);
		SET @IncludiPreFatture = ISNULL(@IncludiPreFatture, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataDa IS NULL OR @DataA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il periodo dei documenti da fatturare';
			GOTO BRANCH_END;
		END
		IF @DataA < @DataDa
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine del periodo non può precedere quella di inizio';
			GOTO BRANCH_END;
		END

		-- Permesso sulle fatture e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Documenti candidati, letti una volta sola
		DECLARE @doc TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			IdClienteFornitore CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdPreFattura CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			GruppoSede CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			GruppoContratto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Imponibile DECIMAL(18, 2) NULL,
			Fatturabile BIT NOT NULL,
			Esito CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL
		);
		INSERT @doc (Id, IdClienteFornitore, IdPreFattura, GruppoSede, GruppoContratto, Imponibile, Fatturabile, Esito)
		SELECT
			d.Id,
			d.IdClienteFornitore,
			d.IdPreFattura,
			d.GruppoSede,
			d.GruppoContratto,
			d.Imponibile,
			d.Fatturabile,
			d.Esito
		FROM dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, NULL, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture) d
		WHERE @Rifiuti = 1
		OPTION (RECOMPILE);

		-- Documenti del periodo già in una fattura o in una pre-fattura (stessa platea dei candidati:
		-- registrazioni confermate di un'operazione fatturabile, non rettifiche, dei registri che la sessione vede)
		DECLARE @giaFatturati INT = 0;
		DECLARE @inPreFattura INT = 0;
		SELECT
			@giaFatturati = ISNULL(SUM(IIF(f.IdTipo = 'TD00', 0, 1)), 0),
			@inPreFattura = ISNULL(SUM(IIF(f.IdTipo = 'TD00', 1, 0)), 0)
		FROM
			dbo.tblRifiutiRegistrazioni r
			INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
			INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi sr ON g.IdSede = sr.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) x ON g.IdSede = x.Id
			INNER JOIN dbo.viewRifiutiRegistrazioniEffettive v ON r.Id = v.Id
			INNER JOIN dbo.tblFattureDocumenti fd ON r.Id = fd.Id
			INNER JOIN dbo.tblFatture f ON fd.IdFattura = f.Id
		WHERE
			@Rifiuti = 1
			AND r.Lock = 0
			AND o.IsFatturabile = 1
			AND v.IsRettifica = 0
			AND f.Lock IN (0, 2)
			AND sr.IdAziendaInterna = @idAzienda
			AND r.[Data] >= @DataDa
			AND r.[Data] <= @DataA
			AND (@IdClienteFornitore IS NULL OR f.IdClienteFornitore = @IdClienteFornitore)
		OPTION (RECOMPILE);

		SELECT
			Documenti = COUNT(*),
			Fatturabili = ISNULL(SUM(IIF(d.Fatturabile = 1, 1, 0)), 0),
			Fatture = (
				SELECT COUNT(*)
				FROM (SELECT DISTINCT IdClienteFornitore, GruppoSede, GruppoContratto FROM @doc WHERE Fatturabile = 1) q
			),
			Clienti = COUNT(DISTINCT IIF(d.Fatturabile = 1, d.IdClienteFornitore, NULL)),
			Imponibile = ISNULL(SUM(IIF(d.Fatturabile = 1, ISNULL(d.Imponibile, 0), 0)), 0),
			PreFatture = COUNT(DISTINCT d.IdPreFattura),
			DocumentiPreFatture = ISNULL(SUM(IIF(d.Esito = 'P', 1, 0)), 0),
			ImportoStandard = ISNULL(SUM(IIF(d.Esito = 'S', 1, 0)), 0),
			Annullati = ISNULL(SUM(IIF(d.Esito = 'A', 1, 0)), 0),
			NonFatturabili = ISNULL(SUM(IIF(d.Esito = 'N', 1, 0)), 0),
			SenzaImporto = ISNULL(SUM(IIF(d.Esito = 'I', 1, 0)), 0),
			SenzaCliente = ISNULL(SUM(IIF(d.Esito = 'C', 1, 0)), 0),
			SenzaRighe = ISNULL(SUM(IIF(d.Esito = 'R', 1, 0)), 0),
			SenzaIva = ISNULL(SUM(IIF(d.Esito = 'V', 1, 0)), 0),
			GiaFatturati = @giaFatturati,
			-- Con le pre-fatture incluse quei documenti sono già tra i candidati
			InPreFattura = IIF(@IncludiPreFatture = 1, 0, @inPreFattura)
		FROM @doc d;

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
GO

PRINT 'sql/procedures/uspFatture_get_Genera_Fatture_List.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatturazione > Fatture clienti > Nuova > Tramite procedura automatica: anteprima delle fatture che la
-- generazione creerebbe con gli stessi criteri ("Visualizza" sulla riga delle fatture previste della finestra
-- "Verifica"). Una riga per fattura: cliente, raggruppamento (la sede del produttore o il contratto, quando la
-- scheda del cliente chiede una fattura per sede o per contratto), documenti, pre-fatture convertite, imponibile.
-- Stessi documenti e stessi gruppi di uspFatture_ins_Genera (ufnFattureGenera_get_Documenti).
-- Al massimo @MaxRighe righe (predefinito 1000): RowsCount dice quante sono in tutto.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_Genera_Fatture_List
	@IdSessione CHAR(16) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@Rifiuti BIT = 1,
	@IncludiPreFatture BIT = 0,
	@MaxRighe INT = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @Rifiuti = ISNULL(@Rifiuti, 1);
		SET @IncludiPreFatture = ISNULL(@IncludiPreFatture, 0);
		SET @MaxRighe = IIF(ISNULL(@MaxRighe, 0) < 1, 1000, @MaxRighe);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @DataDa IS NULL OR @DataA IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il periodo dei documenti da fatturare';
			GOTO BRANCH_END;
		END
		IF @DataA < @DataDa
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine del periodo non può precedere quella di inizio';
			GOTO BRANCH_END;
		END

		-- Permesso sulle fatture e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		SELECT @idAzienda = IdAzienda
		FROM dbo.tblSessioni
		WHERE Id = @IdSessione;

		-- Senza azienda nel contesto nessuna riga
		SELECT TOP (@MaxRighe)
			Id = t.IdClienteFornitore,
			Cliente = sc.NomeCompleto,
			Raggruppamento = CAST(CASE
				WHEN t.GruppoSede IS NOT NULL THEN 'Sede: ' + sp.NomeCompleto
				WHEN t.GruppoContratto IS NOT NULL THEN 'Contratto'
					+ ISNULL(' ' + NULLIF(oc.Protocollo, ''), '')
					+ ISNULL(' del ' + CONVERT(VARCHAR(10), oc.DataInizio, 103), '')
					+ ISNULL(' - ' + NULLIF(oc.Descrizione, ''), '')
			END AS VARCHAR(300)),
			t.Documenti,
			t.PreFatture,
			t.Imponibile,
			RowsCount = COUNT(*) OVER ()
		FROM
			(
				SELECT
					d.IdClienteFornitore,
					d.GruppoSede,
					d.GruppoContratto,
					Documenti = COUNT(*),
					PreFatture = COUNT(DISTINCT d.IdPreFattura),
					Imponibile = SUM(ISNULL(d.Imponibile, 0))
				FROM dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, NULL, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture) d
				WHERE
					@Rifiuti = 1
					AND d.Fatturabile = 1
				GROUP BY d.IdClienteFornitore, d.GruppoSede, d.GruppoContratto
			) t
			LEFT JOIN dbo.tblClientiFornitori c ON t.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi sc ON c.IdSede = sc.Id
			LEFT JOIN dbo.tblSedi sp ON t.GruppoSede = sp.Id
			LEFT JOIN dbo.tblOfferteContratti oc ON t.GruppoContratto = oc.Id
		ORDER BY sc.NomeCompleto, t.IdClienteFornitore, t.GruppoSede, t.GruppoContratto
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
GO

PRINT 'sql/procedures/uspFatture_ins_Genera.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Generazione automatica delle fatture clienti dai documenti fatturabili (per ora le registrazioni dei rifiuti),
-- con gli importi del modulo Offerte e contratti (regole O5 e O6 di docs/regole/offerte-contratti.md).
--   @Id (con @IdModulo = 'RIF'): un solo documento ("Genera la fattura" dalla scheda); l'azienda è quella del
--        documento. Se il documento non è fatturabile la SP lo rifiuta.
--   Senza @Id: i documenti dell'azienda interna corrente della sessione con data tra @DataDa e @DataA,
--        eventualmente riconducibili al solo cliente @IdClienteFornitore (Fatture clienti > Nuovo > Tramite
--        procedura automatica). @Rifiuti = 0: le registrazioni dei rifiuti non sono state scelte.
-- Entrano solo i documenti fatturabili, raggruppati come li mostra la verifica (ufnFattureGenera_get_Documenti).
-- Una fattura per cliente; secondo il raggruppamento della scheda del cliente (tblClientiFornitori.
-- IdRaggruppamento) una per sede del produttore (S) o una per contratto (T): solo in quest'ultimo caso la
-- fattura riporta ordine, data dell'ordine, CIG e CUP del contratto.
-- Fattura: tipo TD01 (TD00, pre-fattura senza numero, con @PreFattura = 1), stato Generata, attiva; data di
-- emissione e di registrazione @DataEmissione (oggi se non indicata); condizioni di pagamento, banca, IBAN,
-- valuta e split payment dalla scheda del cliente; numero successivo dell'anno senza sezionale, assegnato con
-- lo stesso blocco di uspFatture_upd. Righe: quelle dell'importo applicato a ogni documento, nell'ordine dei
-- documenti (data, numero); ritenuta d'acconto della scheda del cliente. Rate: uspFattureRate_ins_Genera.
-- Pre-fatture (@IncludiPreFatture = 1): i documenti già in una pre-fattura rientrano e la pre-fattura viene
-- convertita PER INTERO: le sue righe (non ricalcolate dagli importi, con aliquota, conto e ritenuta che hanno)
-- vanno nella fattura del suo cliente insieme agli altri documenti, al posto del suo primo documento, e tutti i
-- suoi documenti, anche quelli fuori dal periodo, passano alla nuova fattura. Con @RimuoviPreFatture = 1 la
-- pre-fattura viene poi cancellata (Lock 4), altrimenti resta in elenco senza più documenti collegati.
-- Ogni documento resta legato alla fattura (tblFattureDocumenti, con importo e contratto applicati) e non
-- viene fatturato due volte: un documento fatturato nel frattempo da un'altra sessione fa saltare la sua fattura.
-- Una transazione per fattura. Restituisce Fatture, Documenti e IdFattura (l'ultima generata).
CREATE OR ALTER PROCEDURE dbo.uspFatture_ins_Genera
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdModulo CHAR(3) = NULL,
	@DataDa DATE = NULL,
	@DataA DATE = NULL,
	@IdClienteFornitore CHAR(16) = NULL,
	@DataEmissione DATE = NULL,
	@PreFattura BIT = 0,
	@Rifiuti BIT = 1,
	@IncludiPreFatture BIT = 0,
	@RimuoviPreFatture BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(NULLIF(LTRIM(RTRIM(@Id)), ''), REPLICATE('0', 16));
		SET @IdModulo = NULLIF(UPPER(LTRIM(RTRIM(@IdModulo))), '');
		SET @IdClienteFornitore = NULLIF(NULLIF(LTRIM(RTRIM(@IdClienteFornitore)), ''), REPLICATE('0', 16));
		SET @DataEmissione = ISNULL(@DataEmissione, CAST(GETDATE() AS DATE));
		SET @PreFattura = ISNULL(@PreFattura, 0);
		SET @Rifiuti = ISNULL(@Rifiuti, 1);
		SET @IncludiPreFatture = ISNULL(@IncludiPreFatture, 0);
		SET @RimuoviPreFatture = ISNULL(@RimuoviPreFatture, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NOT NULL AND ISNULL(@IdModulo, '') <> 'RIF'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdModulo deve essere RIF';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL AND (@DataDa IS NULL OR @DataA IS NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare il periodo dei documenti da fatturare';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL AND @DataA < @DataDa
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La data di fine del periodo non può precedere quella di inizio';
			GOTO BRANCH_END;
		END
		-- Convertire le pre-fatture in altre pre-fatture non ha senso
		IF @PreFattura = 1 AND @IncludiPreFatture = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Per includere le pre-fatture togliere la spunta "Genera come pre-fatture"';
			GOTO BRANCH_END;
		END

		-- Permesso di modifica sulle fatture e modulo Offerte e contratti attivo sul dominio
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso OR ISNULL(dbo.ufnModuli_get_IsAttivoBySessione('OFC', @IdSessione), 0) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari per generare le fatture';
			GOTO BRANCH_END;
		END

		DECLARE @idAzienda CHAR(16);
		IF @Id IS NULL
		BEGIN
			SELECT @idAzienda = IdAzienda
			FROM dbo.tblSessioni
			WHERE Id = @IdSessione;

			IF @idAzienda IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Selezionare l''azienda';
				GOTO BRANCH_END;
			END
		END
		ELSE
		BEGIN
			-- Un solo documento: sempre i rifiuti, senza pre-fatture
			SET @Rifiuti = 1;
			SET @IncludiPreFatture = 0;
		END

		-- Documenti da fatturare, con il raggruppamento della scheda del cliente
		DECLARE @doc TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			[Data] DATE NULL,
			Numero INT NULL,
			IdAzienda CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdImporto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdOffertaContratto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdClienteFornitore CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdPreFattura CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			-- Primo documento della sua pre-fattura: porta le righe della pre-fattura e decide il gruppo
			PrimoDellaPreFattura BIT NOT NULL,
			GruppoSede CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			GruppoContratto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Fatturabile BIT NOT NULL
		);
		INSERT @doc (Id, [Data], Numero, IdAzienda, IdImporto, IdOffertaContratto, IdClienteFornitore, IdPreFattura, PrimoDellaPreFattura, GruppoSede, GruppoContratto, Fatturabile)
		SELECT
			d.Id,
			d.[Data],
			d.Numero,
			d.IdAzienda,
			d.IdImporto,
			d.IdOffertaContratto,
			ISNULL(d.IdClienteFornitore, REPLICATE('0', 16)),
			d.IdPreFattura,
			d.PrimoDellaPreFattura,
			d.GruppoSede,
			d.GruppoContratto,
			d.Fatturabile
		FROM dbo.ufnFattureGenera_get_Documenti(@IdSessione, @idAzienda, @Id, @DataDa, @DataA, @IdClienteFornitore, @IncludiPreFatture) d
		WHERE
			@Rifiuti = 1
			AND (@Id IS NOT NULL OR d.Fatturabile = 1)
		OPTION (RECOMPILE);

		IF @Id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM @doc WHERE Fatturabile = 1)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il documento non è fatturabile: usare "Verifica importo e cliente" per vedere il motivo';
			GOTO BRANCH_END;
		END

		-- Righe di fattura di ogni documento, calcolate ora una volta per tutte: quelle dell'importo applicato
		-- oppure, per il primo documento di una pre-fattura, le righe della pre-fattura così come sono
		DECLARE @righe TABLE (
			N INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
			IdDocumento CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdRiga CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			Descrizione VARCHAR(1000) NULL,
			SolaDescrizione BIT NOT NULL,
			Quantita DECIMAL(18, 4) NULL,
			IdUnitaMisura CHAR(2) COLLATE DATABASE_DEFAULT NULL,
			Importo DECIMAL(18, 4) NULL,
			IdAliquotaIva CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			IdConto CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			-- NULL: la ritenuta è quella della scheda del cliente
			RitenutaAcconto INT NULL
		);
		INSERT @righe (IdDocumento, Descrizione, SolaDescrizione, Quantita, IdUnitaMisura, Importo, IdAliquotaIva, IdConto, RitenutaAcconto)
		SELECT
			t.IdDocumento,
			t.Descrizione,
			t.SolaDescrizione,
			t.Quantita,
			t.IdUnitaMisura,
			t.Importo,
			t.IdAliquotaIva,
			t.IdConto,
			t.RitenutaAcconto
		FROM
			(
				SELECT
					IdDocumento = d.Id,
					d.[Data],
					d.Numero,
					Pos = ISNULL(g.Pos, 0),
					Ordine = g.Id,
					g.Descrizione,
					g.SolaDescrizione,
					g.Quantita,
					g.IdUnitaMisura,
					g.Importo,
					g.IdAliquotaIva,
					g.IdConto,
					RitenutaAcconto = CAST(NULL AS INT)
				FROM
					@doc d
					CROSS APPLY dbo.ufnImportiRifiuti_get_RigheImporto(d.Id, d.IdImporto, d.IdClienteFornitore) g
				WHERE
					d.Fatturabile = 1
					AND d.IdPreFattura IS NULL

				UNION ALL

				SELECT
					IdDocumento = d.Id,
					d.[Data],
					d.Numero,
					Pos = ISNULL(r.Pos, 0),
					Ordine = r.Id,
					r.Descrizione,
					SolaDescrizione = CAST(IIF(i.Id IS NULL, 1, 0) AS BIT),
					i.Quantita,
					i.IdUnitaMisura,
					i.Importo,
					i.IdAliquotaIva,
					i.IdConto,
					RitenutaAcconto = ISNULL(i.RitenutaAcconto, 0)
				FROM
					@doc d
					INNER JOIN dbo.tblFattureRighe r ON d.IdPreFattura = r.IdFattura
					LEFT JOIN dbo.tblFattureRigheImporti i ON r.Id = i.Id
				WHERE
					d.Fatturabile = 1
					AND d.PrimoDellaPreFattura = 1
			) t
		ORDER BY t.[Data], t.Numero, t.IdDocumento, t.Pos, t.Ordine;

		-- Una fattura per ogni gruppo: cliente e, secondo il raggruppamento, sede del produttore o contratto
		DECLARE @gruppi TABLE (
			N INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
			IdAzienda CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			IdClienteFornitore CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL,
			GruppoSede CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			GruppoContratto CHAR(16) COLLATE DATABASE_DEFAULT NULL
		);
		INSERT @gruppi (IdAzienda, IdClienteFornitore, GruppoSede, GruppoContratto)
		SELECT
			t.IdAzienda,
			t.IdClienteFornitore,
			t.GruppoSede,
			t.GruppoContratto
		FROM
			(
				SELECT DISTINCT IdAzienda, IdClienteFornitore, GruppoSede, GruppoContratto
				FROM @doc
				WHERE Fatturabile = 1
			) t
			LEFT JOIN dbo.tblClientiFornitori c ON t.IdClienteFornitore = c.Id
			LEFT JOIN dbo.tblSedi s ON c.IdSede = s.Id
		ORDER BY s.NomeCompleto, t.IdClienteFornitore, t.GruppoSede, t.GruppoContratto;

		DECLARE @fatture INT = 0;
		DECLARE @documenti INT = 0;
		DECLARE @idUltima CHAR(16) = NULL;
		DECLARE @n INT = 1;
		DECLARE @gruppiTotale INT = (SELECT COUNT(*) FROM @gruppi);
		DECLARE @gAzienda CHAR(16), @gCliente CHAR(16), @gSede CHAR(16), @gContratto CHAR(16);
		DECLARE @idFattura CHAR(16), @idRiga CHAR(16), @r INT, @numero INT;
		DECLARE @annoInizio DATE = DATEFROMPARTS(YEAR(@DataEmissione), 1, 1);
		DECLARE @annoFine DATE = DATEADD(YEAR, 1, @annoInizio);
		DECLARE @gDoc TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
		DECLARE @gPre TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);

		WHILE @n <= @gruppiTotale
		BEGIN
			SELECT
				@gAzienda = IdAzienda,
				@gCliente = IdClienteFornitore,
				@gSede = GruppoSede,
				@gContratto = GruppoContratto
			FROM @gruppi
			WHERE N = @n;

			DELETE @gDoc;
			INSERT @gDoc (Id)
			SELECT Id
			FROM @doc
			WHERE
				Fatturabile = 1
				AND IdAzienda = @gAzienda
				AND IdClienteFornitore = @gCliente
				AND ISNULL(GruppoSede, '') = ISNULL(@gSede, '')
				AND ISNULL(GruppoContratto, '') = ISNULL(@gContratto, '');

			-- Pre-fatture del gruppo, da convertire
			DELETE @gPre;
			INSERT @gPre (Id)
			SELECT DISTINCT IdPreFattura
			FROM @doc
			WHERE
				Id IN (SELECT Id FROM @gDoc)
				AND IdPreFattura IS NOT NULL;

			-- Id della fattura e delle sue righe: uspId_get FUORI dalla transazione
			SET @idFattura = NULL;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idFattura OUTPUT;

			SET @r = (SELECT MIN(N) FROM @righe WHERE IdDocumento IN (SELECT Id FROM @gDoc));
			WHILE @r IS NOT NULL
			BEGIN
				SET @idRiga = NULL;
				EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @idRiga OUTPUT;
				UPDATE @righe SET IdRiga = @idRiga WHERE N = @r;
				SET @r = (SELECT MIN(N) FROM @righe WHERE N > @r AND IdDocumento IN (SELECT Id FROM @gDoc));
			END

			BEGIN TRANSACTION;
				-- Un documento fatturato nel frattempo da un'altra sessione (in una fattura che non è una delle
				-- pre-fatture da convertire), o una pre-fattura nel frattempo cancellata o diventata fattura:
				-- questa fattura non si genera
				IF EXISTS (
						SELECT 1
						FROM
							dbo.tblFattureDocumenti fd WITH (UPDLOCK, HOLDLOCK)
							INNER JOIN dbo.tblFatture f ON fd.IdFattura = f.Id
						WHERE
							fd.Id IN (SELECT Id FROM @gDoc)
							AND f.Lock IN (0, 2)
							AND f.Id NOT IN (SELECT Id FROM @gPre)
					)
					OR EXISTS (
						SELECT 1
						FROM
							@gPre p
							LEFT JOIN dbo.tblFatture f WITH (UPDLOCK, HOLDLOCK) ON p.Id = f.Id
																			  AND f.Lock IN (0, 2)
																			  AND f.IdTipo = 'TD00'
						WHERE f.Id IS NULL
					)
				BEGIN
					ROLLBACK TRANSACTION;

					-- Gli Id presi per la fattura e per le sue righe non servono più
					DELETE dbo.tblIdLog
					WHERE Id = @idFattura OR Id IN (SELECT IdRiga FROM @righe WHERE IdDocumento IN (SELECT Id FROM @gDoc));
					DELETE dbo.tblId
					WHERE Id = @idFattura OR Id IN (SELECT IdRiga FROM @righe WHERE IdDocumento IN (SELECT Id FROM @gDoc));
				END
				ELSE
				BEGIN
					-- Numero: successivo al più alto tra le fatture cliente attive dell'azienda nell'anno della data
					-- di emissione, senza sezionale (stessa lettura con blocco di uspFatture_upd). La pre-fattura
					-- non ha numero
					SET @numero = NULL;
					IF @PreFattura = 0
						SELECT @numero = ISNULL(MAX(Numero), 0) + 1
						FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
						WHERE
							IdSede = @gAzienda
							AND Tipo = 'C'
							AND Lock = 0
							AND ISNULL(Sezionale, '') = ''
							AND DataEmissione >= @annoInizio
							AND DataEmissione < @annoFine;

					INSERT dbo.tblFatture (
						Id, IdSede, IdClienteFornitore, IdTipo, IdStato, IdModalita, IdRata, IdRataInizio, IdValuta, IdBancaCassa,
						Tipo, Numero, DataRegistrazione, DataEmissione, Iban, RataGiorniInizio, Ordine, DataOrdine,
						SplitPayment, Bollo, CodiceCig, CodiceCup, SolaLettura, Lock)
					SELECT
						@idFattura, @gAzienda, c.Id, IIF(@PreFattura = 1, 'TD00', 'TD01'), 'G', c.IdModalita, c.IdRata, ISNULL(c.IdRataInizio, 'DF'), ISNULL(c.IdValuta, 'EUR'), c.IdBancaCassa,
						'C', @numero, @DataEmissione, @DataEmissione, c.Iban, ISNULL(c.RataGiorniInizio, 0), oc.Ordine, oc.DataOrdine,
						ISNULL(c.SplitPayment, 0), 0, oc.CodiceCig, oc.CodiceCup, 0, 0
					FROM
						dbo.tblClientiFornitori c
						LEFT JOIN dbo.tblOfferteContratti oc ON oc.Id = @gContratto
					WHERE c.Id = @gCliente;

					INSERT dbo.tblFattureRighe (Id, IdFattura, Descrizione, Pos)
					SELECT
						g.IdRiga,
						@idFattura,
						g.Descrizione,
						ROW_NUMBER() OVER (ORDER BY g.N)
					FROM @righe g
					WHERE g.IdDocumento IN (SELECT Id FROM @gDoc);

					INSERT dbo.tblFattureRigheImporti (Id, IdAliquotaIva, IdConto, IdUnitaMisura, Quantita, Importo, RitenutaAcconto)
					SELECT
						g.IdRiga,
						g.IdAliquotaIva,
						g.IdConto,
						g.IdUnitaMisura,
						g.Quantita,
						g.Importo,
						ISNULL(g.RitenutaAcconto, ISNULL(c.RitenutaAcconto, 0))
					FROM
						@righe g
						INNER JOIN dbo.tblClientiFornitori c ON c.Id = @gCliente
					WHERE
						g.IdDocumento IN (SELECT Id FROM @gDoc)
						AND g.SolaDescrizione = 0;

					-- Pre-fatture convertite: tutti i loro documenti, anche quelli fuori dal periodo, passano alla
					-- nuova fattura (le righe della pre-fattura non si possono dividere per documento); importo e
					-- contratto applicati restano quelli già registrati
					UPDATE dbo.tblFattureDocumenti
					SET IdFattura = @idFattura
					WHERE IdFattura IN (SELECT Id FROM @gPre);

					IF @RimuoviPreFatture = 1
						UPDATE dbo.tblFatture
						SET Lock = 4
						WHERE Id IN (SELECT Id FROM @gPre);

					-- Legame degli altri documenti con la fattura, con l'importo e il contratto applicati; cliente
					-- indicato e spunta restano quelli già presenti
					UPDATE fd
					SET
						IdFattura = @idFattura,
						IdImporto = d.IdImporto,
						IdOffertaContratto = d.IdOffertaContratto
					FROM
						dbo.tblFattureDocumenti fd
						INNER JOIN @doc d ON fd.Id = d.Id
					WHERE
						d.Id IN (SELECT Id FROM @gDoc)
						AND d.IdPreFattura IS NULL;

					INSERT dbo.tblFattureDocumenti (Id, IdModulo, IdFattura, IdImporto, IdOffertaContratto, NonFatturabile)
					SELECT d.Id, 'RIF', @idFattura, d.IdImporto, d.IdOffertaContratto, 0
					FROM @doc d
					WHERE
						d.Id IN (SELECT Id FROM @gDoc)
						AND NOT EXISTS (SELECT 1 FROM dbo.tblFattureDocumenti x WHERE x.Id = d.Id);

					COMMIT TRANSACTION;

					SET @fatture += 1;
					SET @documenti += (SELECT COUNT(*) FROM @gDoc);
					SET @idUltima = @idFattura;

					-- Rate dalle condizioni di pagamento della fattura. Una fattura senza importo da pagare non
					-- ha rate: quell'errore applicativo non ferma la generazione
					BEGIN TRY
						EXEC dbo.uspFattureRate_ins_Genera @IdFattura = @idFattura, @IdSessione = @IdSessione, @Interno = 1;
					END TRY
					BEGIN CATCH
						IF ERROR_NUMBER() <> 50001
							THROW;
					END CATCH
				END

			SET @n += 1;
		END

		SELECT
			Fatture = @fatture,
			Documenti = @documenti,
			IdFattura = @idUltima;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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
GO

PRINT 'sql/procedures/uspFatture_upd_Numerazione.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Fatture clienti / fornitori > Azioni > Rinumera le fatture. Rinumera le fatture attive dell'azienda interna
-- corrente della sessione, del tipo @Tipo (C clienti, F fornitori), dell'anno @Anno e del sezionale @Sezionale
-- (NULL = senza sezionale), con numero tra @DalNumero e @AlNumero: ricevono numeri consecutivi a partire da
-- @PrimoNumero, nell'ordine di data e numero attuali. Stesso schema di uspRifiutiRegistrazioni_upd_Numerazione.
-- La numerazione è quella della fattura (fatturazione.md, F3): per anno e sezionale; l'anno è quello della data
-- di emissione per le fatture cliente e della data di registrazione per le fatture fornitore (protocollo
-- interno). Le pre-fatture non hanno numero e non entrano; le bozze e le fatture cancellate nemmeno.
-- Fatture in sola lettura: con @AncheSolaLettura = 0 un intervallo che ne contiene almeno una non si rinumera;
-- con @AncheSolaLettura = 1 vengono rinumerate anche quelle, e restano in sola lettura.
-- Controlli e aggiornamento in un'unica transazione, con la stessa lettura con blocco di uspFatture_upd: un
-- salvataggio contemporaneo attende la fine della rinumerazione. Restituisce il numero di fatture rinumerate.
CREATE OR ALTER PROCEDURE dbo.uspFatture_upd_Numerazione
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
	@DalNumero INT = NULL,
	@AlNumero INT = NULL,
	@Anno INT = NULL,
	@Sezionale VARCHAR(5) = NULL,
	@PrimoNumero INT = NULL,
	@AncheSolaLettura BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Tipo = NULLIF(UPPER(LTRIM(RTRIM(@Tipo))), '');
		SET @Sezionale = NULLIF(UPPER(LTRIM(RTRIM(@Sezionale))), '');
		SET @AncheSolaLettura = ISNULL(@AncheSolaLettura, 0);

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
		IF @DalNumero IS NULL OR @AlNumero IS NULL OR @Anno IS NULL OR @PrimoNumero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare l''intervallo dei numeri, l''anno e il primo numero';
			GOTO BRANCH_END;
		END
		IF @DalNumero < 1 OR @AlNumero < @DalNumero
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''intervallo dei numeri non è valido';
			GOTO BRANCH_END;
		END
		IF @PrimoNumero < 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il nuovo numero deve essere maggiore di zero';
			GOTO BRANCH_END;
		END
		IF @Anno < 1900 OR @Anno > 2999
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''anno indicato non è valido';
			GOTO BRANCH_END;
		END
		IF @Sezionale IS NOT NULL AND (LEN(@Sezionale) > 1 OR @Sezionale NOT LIKE '[A-Z]')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il sezionale è una lettera da A a Z';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Scope: azienda interna corrente della sessione
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

		DECLARE @annoInizio DATE = DATEFROMPARTS(@Anno, 1, 1);
		DECLARE @annoFine DATE = DATEADD(YEAR, 1, @annoInizio);

		-- Fatture dell'anno e del sezionale: Id, numero attuale, data che decide l'anno, sola lettura
		DECLARE @fatture TABLE (
			Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			Numero INT NOT NULL,
			[Data] DATE NOT NULL,
			SolaLettura BIT NOT NULL
		);

		BEGIN TRANSACTION;

			-- Lettura con blocco separata per tipo, con il filtro sulla colonna della data, come in
			-- uspFatture_upd: per le fatture cliente il blocco copre l'anno dell'azienda
			IF @Tipo = 'C'
				INSERT @fatture (Id, Numero, [Data], SolaLettura)
				SELECT Id, Numero, DataEmissione, ISNULL(SolaLettura, 0)
				FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
				WHERE
					IdSede = @idAzienda
					AND Tipo = 'C'
					AND Lock = 0
					AND Numero IS NOT NULL
					AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
					AND DataEmissione >= @annoInizio
					AND DataEmissione < @annoFine;
			ELSE
				INSERT @fatture (Id, Numero, [Data], SolaLettura)
				SELECT Id, Numero, DataRegistrazione, ISNULL(SolaLettura, 0)
				FROM dbo.tblFatture WITH (UPDLOCK, HOLDLOCK)
				WHERE
					IdSede = @idAzienda
					AND Tipo = 'F'
					AND Lock = 0
					AND Numero IS NOT NULL
					AND ISNULL(Sezionale, '') = ISNULL(@Sezionale, '')
					AND DataRegistrazione >= @annoInizio
					AND DataRegistrazione < @annoFine;

			DECLARE @totaleDaRinumerare INT = (SELECT COUNT(*) FROM @fatture WHERE Numero BETWEEN @DalNumero AND @AlNumero);

			-- Se non c'è nulla da rinumerare
			IF @totaleDaRinumerare = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Non ci sono fatture nell''intervallo indicato';
				GOTO BRANCH_END;
			END

			-- Fatture in sola lettura: si rinumerano solo se richiesto
			IF @AncheSolaLettura = 0 AND EXISTS (SELECT 1 FROM @fatture WHERE Numero BETWEEN @DalNumero AND @AlNumero AND SolaLettura = 1)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'L''intervallo contiene fatture in sola lettura: per rinumerarle spuntare "Rinumera anche le fatture in Sola lettura"';
				GOTO BRANCH_END;
			END

			-- Se la numerazione finale supera 999.999
			IF @PrimoNumero + @totaleDaRinumerare - 1 > 999999
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La rinumerazione non può assegnare numeri maggiori di 999.999';
				GOTO BRANCH_END;
			END

			-- Se la nuova numerazione entra in conflitto con fatture fuori dal gruppo che sarà rinumerato
			IF EXISTS (
				SELECT 1
				FROM @fatture
				WHERE
					Numero NOT BETWEEN @DalNumero AND @AlNumero
					AND Numero BETWEEN @PrimoNumero AND @PrimoNumero + @totaleDaRinumerare - 1
			)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'La nuova numerazione è in conflitto con quella di altre fatture';
				GOTO BRANCH_END;
			END

			UPDATE f
			SET Numero = t.NumeroNuovo
			FROM
				dbo.tblFatture f
				INNER JOIN
					(
						SELECT
							Id,
							Numero,
							NumeroNuovo = ROW_NUMBER() OVER (ORDER BY [Data], Numero, Id) + @PrimoNumero - 1
						FROM @fatture
						WHERE Numero BETWEEN @DalNumero AND @AlNumero
					) t ON f.Id = t.Id
			WHERE t.Numero <> t.NumeroNuovo;

			SET @returnValue = @@ROWCOUNT;

		COMMIT TRANSACTION;

		SELECT @returnValue AS ReturnValue;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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
GO

PRINT 'sql/procedures/uspMenu_get.sql';
GO
CREATE OR ALTER PROCEDURE [dbo].[uspMenu_get]
	@IdUtente CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY

		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;
		DECLARE @Menu VARCHAR(MAX) = NULL;

		SET @IdUtente = NULLIF(LTRIM(RTRIM(@IdUtente)), '');
		IF @IdUtente IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdUtente non può essere vuoto';
			GOTO BRANCH_END;
		END

		BEGIN TRY
			-- Costruisce il menu JSON con le pagine accessibili dall'utente.
			-- La CTE filtra le pagine per cui l'utente ha accesso alla funzione.
			-- La query esterna filtra le aree:
			--   - Admin Master: accede a tutte le aree senza filtro sui moduli
			--   - Utenti normali: il modulo (IdArea = IdModulo) deve essere
			--     abilitato sul dominio dell'utente
			WITH cte AS (
				SELECT
					m.Id,
					m.IdParent,
					Nome = p.Nome,
					Pagina = LOWER('/' + ISNULL(p.[Url], p.Nome)),
					m.Pos
				FROM
					dbo.tblMenu m
					INNER JOIN dbo.tblPagine p ON m.IdPagina = p.Id
					INNER JOIN dbo.ufnFunzioni_get_ByUtente_List(@IdUtente) f
											  ON p.IdFunzione = f.Id
				WHERE
					-- Pagina che richiede un altro modulo oltre a quello dell'area (tblPagine.IdModulo):
					-- il modulo deve essere abilitato sul dominio dell'utente; l'Admin Master la vede sempre
					p.IdModulo IS NULL
					OR EXISTS (
						SELECT 1
						FROM dbo.tblUtenti u
						INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
						WHERE u.Id = @IdUtente
						  AND d.[Master] = 1
					)
					OR EXISTS (
						SELECT 1
						FROM dbo.tblDominiModuli dm
						INNER JOIN dbo.tblUtenti u ON dm.Id = u.IdDominio
						WHERE dm.IdModulo = p.IdModulo
						  AND u.Id = @IdUtente
					)
			)
			SELECT @Menu = (
				SELECT
					m.Id,
					Nome = a.Nome,
					Icon = a.Icon,
					Pagine = (
						SELECT
							s.Id,
							s.Nome,
							s.Pagina
						FROM cte s
						WHERE
							s.IdParent = m.Id
							AND s.Nome IS NOT NULL
						ORDER BY s.Pos
						FOR JSON PATH
					)
				FROM
					dbo.tblMenu m
					INNER JOIN dbo.tblPagineAree a ON m.IdArea = a.Id
				WHERE
					EXISTS (SELECT 1 FROM cte s WHERE s.IdParent = m.Id)
					AND
						(
						-- Admin Master: accede a tutte le aree
						EXISTS (
							SELECT 1
							FROM dbo.tblUtenti u
							INNER JOIN dbo.tblDomini d ON u.IdDominio = d.Id
							WHERE u.Id = @IdUtente
							  AND d.[Master] = 1
						)
						OR
						-- Utenti normali: modulo dell'area abilitato sul dominio
						EXISTS (
							SELECT 1
							FROM dbo.tblDominiModuli dm
							INNER JOIN dbo.tblUtenti u ON dm.Id = u.IdDominio
							WHERE dm.IdModulo = m.IdArea
							  AND u.Id = @IdUtente
						)
						)
				ORDER BY m.Pos
				FOR JSON PATH, ROOT('Aree')
			);
		END TRY
		BEGIN CATCH
			-- Fallback intenzionale: se la generazione del menu fallisce
			-- restituisce il menu minimo con la sola area Home.
			SET @Menu = '{"Aree":[{"Id":"AA0","Nome":"Home","Icon":"fal fa-home","Pagine":[{"Id":"AA1","Nome":"Avvisi","Pagina":"\/Avvisi"}]}]}';
		END CATCH

		SELECT @Menu AS rtn;

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

PRINT 'sql/procedures/uspAliquoteIva_get_SelectList.sql';
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
		-- Le fatture (FTT) usano la stessa select
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'FTT',
				@Permesso = @permesso OUTPUT;
		END
		-- Anche le righe degli importi (OCI, modulo Offerte e contratti)
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'OCI',
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
GO

PRINT 'sql/procedures/uspFattureConti_get_SelectList.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureConti_get_SelectList
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

		-- Controlla il permesso sulla funzione: la select serve alle righe delle fatture (FTT) oltre che
		-- alla configurazione (FTC); basta la lettura su una delle due
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'FTC',
				@Permesso = @permesso OUTPUT;
		END
		-- Anche le righe degli importi (OCI, modulo Offerte e contratti)
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'OCI',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		-- Scope: conti dell'azienda interna corrente della sessione
		SELECT Id, [Text], Selected
		FROM (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(100)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL

			SELECT
				c.Id,
				[Text] = CAST(ISNULL(c.Codice + ' - ', '') + c.Nome AS VARCHAR(100)),
				Selected = CAST(IIF(c.Id = @IdSelected, 1, 0) AS BIT),
				Pos = 1
			FROM
				dbo.tblFattureConti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				e.Id = @IdSessione
				AND c.Lock = 0
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
GO

PRINT 'sql/procedures/uspFatture_get_ClientiFornitori_SelectList.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Clienti (@Tipo = C) o fornitori (@Tipo = F) dell'azienda del contesto per la select della fattura:
-- Id è la scheda del cliente o del fornitore, non il soggetto.
CREATE OR ALTER PROCEDURE dbo.uspFatture_get_ClientiFornitori_SelectList
	@IdSessione CHAR(16) = NULL,
	@Tipo CHAR(1) = NULL,
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
		SET @Tipo = UPPER(NULLIF(LTRIM(RTRIM(@Tipo)), ''));
		SET @IdSelected = NULLIF(LTRIM(RTRIM(@IdSelected)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

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

		-- Controlla il permesso sulla funzione
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		-- Anche la scheda di un contratto o di un'offerta (OCC, modulo Offerte e contratti)
		IF 1 > @permesso
		BEGIN
			EXEC dbo.uspSessione_get_FunzionePermesso
				@Id = @IdSessione,
				@IdFunzione = 'OCC',
				@Permesso = @permesso OUTPUT;
		END
		IF 1 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		SET @IdSelected = ISNULL(@IdSelected, @idSediciZeri);

		;WITH cte AS (
			SELECT
				Id = CAST(@idSediciZeri AS CHAR(16)),
				[Text] = CAST('(Selezionare)' AS VARCHAR(500)),
				Selected = CAST(IIF(@IdSelected = @idSediciZeri, 1, 0) AS BIT),
				Pos = 0

			UNION ALL -- scheda selezionata: sempre presente, anche se cancellata, disabilitata o fuori da @Search

			SELECT
				c.Id,
				[Text] = CAST(s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') AS VARCHAR(500)),
				Selected = CAST(1 AS BIT),
				Pos = 1
			FROM
				dbo.tblClientiFornitori c
				INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
				INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			WHERE
				e.Id = @IdSessione
				AND c.Id = @IdSelected
				AND c.Tipo = @Tipo

			UNION ALL -- altre schede attive dell'azienda, filtrabili per @Search

			SELECT
				c.Id,
				[Text] = CAST(s.NomeCompleto + ISNULL(' ' + s.IndirizzoCompleto, '') AS VARCHAR(500)),
				Selected = CAST(0 AS BIT),
				Pos = 2
			FROM
				dbo.tblClientiFornitori c
				INNER JOIN dbo.tblSessioni e ON c.IdAziendaInterna = e.IdAzienda
				INNER JOIN dbo.tblSedi s ON c.IdSede = s.Id
			WHERE
				e.Id = @IdSessione
				AND c.Tipo = @Tipo
				AND c.Lock = 0
				AND ISNULL(s.Disabilitata, 0) = 0
				AND c.Id <> @IdSelected
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
GO

PRINT 'sql/procedures/uspAliquoteIva_del.sql';
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
			END			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblFattureRigheImporti i
					INNER JOIN dbo.tblFattureRighe r ON i.Id = r.Id
					INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				WHERE
					i.IdAliquotaIva = @Id
					AND f.Lock IN (0, 2)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''aliquota usata nelle righe di una fattura non può essere cancellata';
				GOTO BRANCH_END;
			END
			-- Modulo Offerte e contratti: lo stesso per le righe di un importo non cancellato
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblImportiRigheDettagli d
					INNER JOIN dbo.tblImportiRighe g ON d.Id = g.Id
					INNER JOIN dbo.tblImporti i ON g.IdImporto = i.Id
				WHERE
					d.IdAliquotaIva = @Id
					AND i.Lock IN (0, 2)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un''aliquota usata nelle righe di un importo non può essere cancellata';
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
GO

PRINT 'sql/procedures/uspFattureConti_del.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspFattureConti_del
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

		-- Idempotenza: mai esistito o già cancellato viene trattato come cancellazione già avvenuta
		IF NOT EXISTS (SELECT 1 FROM dbo.tblFattureConti WHERE Id = @Id)
		BEGIN
			SET @returnValue = 0;
		END
		ELSE
		BEGIN

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblFattureConti c
				INNER JOIN dbo.tblSessioni e ON c.IdSede = e.IdAzienda
			WHERE
				c.Id = @Id
				AND e.Id = @IdSessione
		)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		DECLARE @lock INT = (SELECT Lock FROM dbo.tblFattureConti WHERE Id = @Id);
		DECLARE @idAzienda CHAR(16) = (SELECT IdSede FROM dbo.tblFattureConti WHERE Id = @Id);

		-- ── CASO 1: conto attivo (Lock = 0) → soft delete ────────────────────
		IF @lock = 0
		BEGIN
			-- Un conto usato nelle righe di una fattura non cancellata resta
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblFattureRigheImporti i
					INNER JOIN dbo.tblFattureRighe r ON i.Id = r.Id
					INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id
				WHERE
					i.IdConto = @Id
					AND f.Lock IN (0, 2)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un conto usato nelle righe di una fattura non può essere cancellato';
				GOTO BRANCH_END;
			END
			-- Lo stesso per un conto indicato in un movimento manuale attivo della prima nota. IdSede (l'azienda
			-- del conto, la stessa dei suoi movimenti) permette la ricerca nell'indice dei pagamenti
			IF EXISTS (SELECT 1 FROM dbo.tblPagamenti WHERE IdSede = @idAzienda AND IdConto = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un conto usato in un movimento della prima nota non può essere cancellato';
				GOTO BRANCH_END;
			END
			-- Modulo Offerte e contratti: lo stesso per le righe di un importo non cancellato
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblImportiRigheDettagli d
					INNER JOIN dbo.tblImportiRighe g ON d.Id = g.Id
					INNER JOIN dbo.tblImporti i ON g.IdImporto = i.Id
				WHERE
					d.IdConto = @Id
					AND i.Lock IN (0, 2)
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un conto usato nelle righe di un importo non può essere cancellato';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblFattureConti
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				IF @@ROWCOUNT = 0
				BEGIN
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Conto non trovato o già eliminato';
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

		-- ── CASO 2: conto in bozza (Lock = 2) → hard delete ──────────────────
		ELSE IF @lock = 2
		BEGIN
			BEGIN TRANSACTION;
				DELETE dbo.tblFattureConti
				WHERE Id = @Id;
				DELETE dbo.tblIdCancellati
				WHERE Id = @Id;
				DELETE dbo.tblIdLog
				WHERE Id = @Id;
				DELETE dbo.tblId
				WHERE Id = @Id;
			COMMIT TRANSACTION;
		END

		-- ── CASO 3: già cancellato (Lock = 4) → nessuna azione (idempotenza) ──
		ELSE IF @lock = 4
		BEGIN
			SET @returnValue = 0;
		END

		-- ── CASO 4: Lock in stato non gestito ─────────────────────────────────
		ELSE
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il conto è in uno stato non modificabile (Lock = ' + ISNULL(CAST(@lock AS VARCHAR(5)), 'NULL') + ')';
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
GO

PRINT 'sql/procedures/uspClientiFornitori_del.sql';
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
			-- Una scheda con fatture non cancellate resta
			IF EXISTS (SELECT 1 FROM dbo.tblFatture WHERE IdClienteFornitore = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = IIF(@tipo = 'C', 'Un cliente con fatture non può essere cancellato', 'Un fornitore con fatture non può essere cancellato');
				GOTO BRANCH_END;
			END
			-- Modulo Offerte e contratti: lo stesso per una scheda con contratti o offerte non cancellati
			IF EXISTS (SELECT 1 FROM dbo.tblOfferteContratti WHERE IdClienteFornitore = @Id AND Lock IN (0, 2))
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Un cliente con contratti o offerte non può essere cancellato';
				GOTO BRANCH_END;
			END
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
GO

PRINT 'sql/procedures/uspSedi_del_SediEsterne.sql';
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
				FROM dbo.tblServiziOsepe o
				INNER JOIN dbo.tblServizi s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
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

			-- Modulo Magazzino: una sede esterna può comparire su un DDT come mittente (es. il
			-- fornitore di un DDT ricevuto), destinatario, destinazione o trasportatore
			-- (Articoli/Lotti/Movimenti/Righe sono sempre su sedi interne)
			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniDdt WHERE IdMittente = @Id OR IdDestinatario = @Id OR IdDestinazione = @Id OR IdTrasportatore = @Id)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede associata a un DDT di magazzino non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Anagrafica estesa: un soggetto con una scheda cliente o fornitore attiva
			IF EXISTS (SELECT 1 FROM dbo.tblClientiFornitori WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede presente tra i clienti o i fornitori non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Offerte e contratti: una sede indicata tra le variabili di un importo attivo
			IF EXISTS (
					SELECT 1
					FROM dbo.tblImportiRifiuti r
					INNER JOIN dbo.tblImporti i ON r.Id = i.Id
					WHERE i.Lock = 0 AND @Id IN (r.IdProduttoreParent, r.IdProduttore, r.IdTrasportatore, r.IdDestinatario, r.IdIntermediario)
				)
				OR EXISTS (
					SELECT 1
					FROM dbo.tblImportiMagazzino m
					INNER JOIN dbo.tblImporti i ON m.Id = i.Id
					WHERE i.Lock = 0 AND @Id IN (m.IdMittenteParent, m.IdMittente, m.IdDestinatarioParent, m.IdDestinatario)
				)
				OR EXISTS (
					SELECT 1
					FROM dbo.tblImportiServizi v
					INNER JOIN dbo.tblImporti i ON v.Id = i.Id
					WHERE i.Lock = 0 AND @Id IN (v.IdRichiedenteParent, v.IdRichiedente, v.IdEsecutore)
				)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede indicata in un importo non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Anagrafica estesa: un soggetto con una scheda amministratore attiva, o
			-- amministrato da un amministratore attivo
			IF EXISTS (SELECT 1 FROM dbo.tblAmministratori WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede presente tra gli amministratori non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblAmministratoriSedi x
					INNER JOIN dbo.tblAmministratori a ON x.Id = a.Id
				WHERE
					x.IdSede = @Id
					AND a.Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede amministrata da un amministratore non può essere cancellata';
				GOTO BRANCH_END;
			END

			BEGIN TRANSACTION;
				UPDATE dbo.tblSedi
				SET Lock = 4
				WHERE
					Id = @Id
					AND Lock = 0;

				-- Unità locale: se la sede cancellata è una sede figlia con il flag, lo eredita
				-- il soggetto, così il gruppo non resta mai senza un'unità locale attiva
				UPDATE p
				SET p.UnitaLocale = 1
				FROM dbo.tblSedi p
				INNER JOIN dbo.tblSedi s ON s.IdParent = p.Id
				WHERE
					s.Id = @Id
					AND s.UnitaLocale = 1
					AND p.Lock = 0;

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
				FROM dbo.tblServiziOsepe o
				INNER JOIN dbo.tblServizi s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
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
				-- Modulo Magazzino: DDT dove questa sede esterna compare come mittente,
				-- destinatario, destinazione o trasportatore. Ramo di fatto irraggiungibile in
				-- pratica (blocco sopra su Lock=0), mantenuto per difesa dalla FK.
				DELETE dbo.tblMagazziniDdt
				WHERE IdMittente = @Id OR IdDestinatario = @Id OR IdDestinazione = @Id OR IdTrasportatore = @Id;

				-- Anagrafica estesa: schede cliente/fornitore del soggetto (una bozza di norma non
				-- ne ha), per difesa dalla FK NO_ACTION
				DELETE dbo.tblClientiFornitori
				WHERE IdSede = @Id;

				-- Anagrafica estesa: schede amministratore del soggetto con i loro amministrati, e
				-- il soggetto stesso tra gli amministrati di altre schede (stessa difesa dalla FK)
				DELETE dbo.tblAmministratoriSedi
				WHERE
					IdSede = @Id
					OR Id IN (SELECT Id FROM dbo.tblAmministratori WHERE IdSede = @Id);
				DELETE dbo.tblAmministratori
				WHERE IdSede = @Id;

				-- Tabelle 1:1 sulla sede (FK NO_ACTION): una bozza di norma non ne ha
				DELETE dbo.tblSediDatiEstesi
				WHERE Id = @Id;
				DELETE dbo.tblSediRecapiti
				WHERE Id = @Id;
				DELETE dbo.tblSediIndirizzi
				WHERE Id = @Id;

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

PRINT 'sql/procedures/uspSedi_del_SediInterne.sql';
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

			IF EXISTS (SELECT 1 FROM dbo.tblMagazziniDdt WHERE IdSede = @Id OR IdMittente = @Id OR IdDestinatario = @Id OR IdDestinazione = @Id OR IdTrasportatore = @Id)
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

			IF EXISTS (SELECT 1 FROM dbo.tblAmministratori WHERE IdAziendaInterna = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con amministratori associati non può essere cancellata';
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
			IF EXISTS (SELECT 1 FROM dbo.tblFatture WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con fatture associate non può essere cancellata';
				GOTO BRANCH_END;
			END

			IF EXISTS (SELECT 1 FROM dbo.tblFattureConti WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con conti di fatturazione associati non può essere cancellata';
				GOTO BRANCH_END;
			END

			-- Modulo Offerte e contratti: importi e offerte o contratti dell'azienda, e sedi indicate tra le
			-- variabili di un importo attivo
			IF EXISTS (SELECT 1 FROM dbo.tblImporti WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con importi associati non può essere cancellata';
				GOTO BRANCH_END;
			END
			IF EXISTS (SELECT 1 FROM dbo.tblOfferteContratti WHERE IdSede = @Id AND Lock = 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con offerte o contratti associati non può essere cancellata';
				GOTO BRANCH_END;
			END
			IF EXISTS (
					SELECT 1
					FROM dbo.tblImportiRifiuti r
					INNER JOIN dbo.tblImporti i ON r.Id = i.Id
					WHERE i.Lock = 0 AND @Id IN (r.IdProduttoreParent, r.IdProduttore, r.IdTrasportatore, r.IdDestinatario, r.IdIntermediario)
				)
				OR EXISTS (
					SELECT 1
					FROM dbo.tblImportiMagazzino m
					INNER JOIN dbo.tblImporti i ON m.Id = i.Id
					WHERE i.Lock = 0 AND @Id IN (m.IdMittenteParent, m.IdMittente, m.IdDestinatarioParent, m.IdDestinatario)
				)
				OR EXISTS (
					SELECT 1
					FROM dbo.tblImportiServizi v
					INNER JOIN dbo.tblImporti i ON v.Id = i.Id
					WHERE i.Lock = 0 AND @Id IN (v.IdRichiedenteParent, v.IdRichiedente, v.IdEsecutore)
				)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede indicata in un importo non può essere cancellata';
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
				FROM dbo.tblServiziOsepe o
				INNER JOIN dbo.tblServizi s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
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

			-- Dichiarazione MUD: azienda dichiarante (IdSede), sede legale e unità locale
			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiMud
			WHERE
				(IdSede = @Id OR IdSedeLegale = @Id OR IdSedeUnitaLocale = @Id)
				AND Lock = 0
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con dichiarazioni MUD associate non può essere cancellata';
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

				-- Unità locale: se la sede cancellata è una sede figlia con il flag, lo eredita
				-- l'azienda, così il gruppo non resta mai senza un'unità locale attiva
				UPDATE p
				SET p.UnitaLocale = 1
				FROM dbo.tblSedi p
				INNER JOIN dbo.tblSedi s ON s.IdParent = p.Id
				WHERE
					s.Id = @Id
					AND s.UnitaLocale = 1
					AND p.Lock = 0;

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
				FROM dbo.tblServiziOsepe o
				INNER JOIN dbo.tblServizi s ON o.Id = s.Id
				INNER JOIN dbo.tblEventi e ON s.IdEvento = e.Id
				WHERE
					o.IdOsepe = @Id
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

			-- Dichiarazione MUD: una dichiarazione non si elimina mai insieme alla sede, quindi qui
			-- blocca in qualunque stato (la FK NO_ACTION fermerebbe comunque la cancellazione fisica)
			IF EXISTS (SELECT 1
			FROM dbo.tblRifiutiMud
			WHERE IdSede = @Id OR IdSedeLegale = @Id OR IdSedeUnitaLocale = @Id
			)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Una sede con dichiarazioni MUD associate non può essere cancellata';
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
					IdSede = @Id
					OR IdMittente = @Id
					OR IdDestinatario = @Id
					OR IdDestinazione = @Id
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
				-- Fatture dell'azienda con righe e rate, poi i conti (prima delle schede e delle banche,
				-- che le fatture referenziano)
				DELETE dbo.tblFattureRigheImporti
				WHERE Id IN (SELECT r.Id FROM dbo.tblFattureRighe r INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id WHERE f.IdSede = @Id);
				DELETE dbo.tblFattureRighe
				WHERE IdFattura IN (SELECT Id FROM dbo.tblFatture WHERE IdSede = @Id);
				DELETE dbo.tblFattureRatePagamenti
				WHERE IdRata IN (SELECT r.Id FROM dbo.tblFattureRate r INNER JOIN dbo.tblFatture f ON r.IdFattura = f.Id WHERE f.IdSede = @Id);
				DELETE dbo.tblFattureRate
				WHERE IdFattura IN (SELECT Id FROM dbo.tblFatture WHERE IdSede = @Id);
				UPDATE dbo.tblFatture
				SET IdFatturaRiferimento = NULL
				WHERE IdSede = @Id;
				DELETE dbo.tblFatture
				WHERE IdSede = @Id;
				DELETE dbo.tblPagamenti
				WHERE
					IdSede = @Id
					OR IdBancaCassa IN (SELECT Id FROM dbo.tblBancheCasse WHERE IdSede = @Id);
				DELETE dbo.tblFattureConti
				WHERE IdSede = @Id;
				DELETE dbo.tblFattureDatiFiscali
				WHERE Id = @Id;
				DELETE dbo.tblClientiFornitori
				WHERE IdAziendaInterna = @Id;

				DELETE dbo.tblAmministratoriSedi
				WHERE Id IN (SELECT Id FROM dbo.tblAmministratori WHERE IdAziendaInterna = @Id);
				DELETE dbo.tblAmministratori
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

				-- Tabelle 1:1 sulla sede (FK NO_ACTION): una bozza di norma non ne ha
				DELETE dbo.tblSediDatiEstesi
				WHERE Id = @Id;
				DELETE dbo.tblSediRecapiti
				WHERE Id = @Id;
				DELETE dbo.tblSediIndirizzi
				WHERE Id = @Id;

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

PRINT 'sql/procedures/uspFattureRate_ins_Genera.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Genera le rate della fattura dalle condizioni di pagamento salvate sulla testata, sostituendo quelle
-- presenti. Numero di rate e mesi della prima vengono dalla rateizzazione (tblPagamentiRate: Numero,
-- PrimaMesi; le successive a un mese l'una dall'altra); senza rateizzazione una sola rata alla data
-- della fattura. Decorrenza DF: scadenza = data della fattura + mesi. Decorrenza FM: fine del mese
-- di (data della fattura + mesi) e, con il giorno del mese indicato, quel giorno del mese successivo.
-- Importo: netto a pagare diviso in parti uguali, con il resto degli arrotondamenti sull'ultima rata.
-- @Interno = 1: chiamata da un'altra SP che ha già controllato l'azienda della fattura (uspFatture_ins_Genera,
-- generazione automatica: l'azienda è quella del documento, non quella del contesto della sessione); non
-- restituisce il numero di rate. L'applicazione non lo passa.
CREATE OR ALTER PROCEDURE dbo.uspFattureRate_ins_Genera
	@IdFattura CHAR(16) = NULL,
	@IdSessione CHAR(16) = NULL,
	@Interno BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdFattura = NULLIF(LTRIM(RTRIM(@IdFattura)), '');
		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Interno = ISNULL(@Interno, 0);

		IF @IdFattura IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdFattura non può essere vuoto';
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
			@IdFunzione = 'FTT',
			@Permesso = @permesso OUTPUT;
		IF 2 > @permesso
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- La fattura deve esistere (in bozza o attiva, non eliminata), appartenere all'azienda interna
		-- corrente della sessione e non essere in sola lettura
		DECLARE @idAzienda CHAR(16);
		DECLARE @solaLettura BIT;
		DECLARE @dataEmissione DATE;
		DECLARE @idRataInizio CHAR(2);
		DECLARE @giorno INT;
		DECLARE @numero INT;
		DECLARE @primaMesi INT;
		SELECT
			@idAzienda = f.IdSede,
			@solaLettura = ISNULL(f.SolaLettura, 0),
			@dataEmissione = f.DataEmissione,
			@idRataInizio = ISNULL(f.IdRataInizio, 'DF'),
			@giorno = ISNULL(f.RataGiorniInizio, 0),
			@numero = ISNULL(r.Numero, 1),
			@primaMesi = ISNULL(r.PrimaMesi, 0)
		FROM
			dbo.tblFatture f
			LEFT JOIN dbo.tblSessioni e ON e.Id = @IdSessione
			LEFT JOIN dbo.tblPagamentiRate r ON f.IdRata = r.Id
		WHERE
			f.Id = @IdFattura
			AND (@Interno = 1 OR f.IdSede = e.IdAzienda)
			AND f.Lock IN (0, 2);

		IF @idAzienda IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari, o la fattura non esiste';
			GOTO BRANCH_END;
		END
		IF @solaLettura = 1
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura è in sola lettura: per modificarla togliere la spunta Sola lettura e salvare';
			GOTO BRANCH_END;
		END
		IF @dataEmissione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare la data della fattura prima di generare le rate';
			GOTO BRANCH_END;
		END
		IF EXISTS (
			SELECT 1
			FROM
				dbo.tblFattureRate r
				INNER JOIN dbo.tblFattureRatePagamenti p ON r.Id = p.IdRata
			WHERE r.IdFattura = @IdFattura)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Le rate hanno già dei pagamenti: non si possono rigenerare';
			GOTO BRANCH_END;
		END

		DECLARE @netto DECIMAL(18, 2);
		SELECT @netto = NettoAPagare
		FROM dbo.ufnFatture_get_Totali(@IdFattura);

		IF ISNULL(@netto, 0) <= 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La fattura non ha un importo da pagare: inserire prima le righe';
			GOTO BRANCH_END;
		END
		IF @numero < 1 SET @numero = 1;

		-- Scadenze e importi; gli Id (uspId_get) FUORI dalla transazione
		DECLARE @rate TABLE (
			N INT NOT NULL PRIMARY KEY,
			Id CHAR(16) COLLATE DATABASE_DEFAULT NULL,
			DataScadenza DATE NOT NULL,
			Importo DECIMAL(18, 2) NOT NULL
		);
		DECLARE @quota DECIMAL(18, 2) = ROUND(@netto / @numero, 2, 1);
		DECLARE @n INT = 1;
		DECLARE @scadenza DATE;
		DECLARE @fineMese DATE;
		DECLARE @id CHAR(16);

		WHILE @n <= @numero
		BEGIN
			SET @scadenza = DATEADD(MONTH, @primaMesi + @n - 1, @dataEmissione);
			IF @idRataInizio = 'FM'
			BEGIN
				SET @scadenza = EOMONTH(@scadenza);
				IF @giorno > 0
				BEGIN
					-- Giorno del mese successivo, non oltre la sua fine (31 in un mese di 30 giorni)
					SET @fineMese = EOMONTH(DATEADD(DAY, 1, @scadenza));
					SET @scadenza = DATEADD(DAY, IIF(@giorno > DAY(@fineMese), DAY(@fineMese), @giorno), @scadenza);
				END
			END

			SET @id = NULL;
			EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @id OUTPUT;

			INSERT @rate (N, Id, DataScadenza, Importo)
			VALUES (@n, @id, @scadenza, IIF(@n = @numero, @netto - @quota * (@numero - 1), @quota));

			SET @n += 1;
		END

		DECLARE @vecchie TABLE (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);

		BEGIN TRANSACTION;
			INSERT @vecchie (Id)
			SELECT Id
			FROM dbo.tblFattureRate WITH (UPDLOCK, HOLDLOCK)
			WHERE IdFattura = @IdFattura;

			DELETE dbo.tblFattureRate
			WHERE IdFattura = @IdFattura;
			DELETE dbo.tblIdLog
			WHERE Id IN (SELECT Id FROM @vecchie);
			DELETE dbo.tblId
			WHERE Id IN (SELECT Id FROM @vecchie);

			INSERT dbo.tblFattureRate (Id, IdFattura, Importo, Abbuono, DataScadenza)
			SELECT Id, @IdFattura, Importo, 0, DataScadenza
			FROM @rate;
		COMMIT TRANSACTION;

		IF @Interno = 0
			SELECT ReturnValue = @numero;

	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
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
GO

PRINT 'sql/procedures/uspSYS_del_SedeInternaCascade.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_SedeInternaCascade
    @IdSede   CHAR(16)    = NULL,
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSede   = NULLIF(LTRIM(RTRIM(@IdSede)),   '');
        SET @Conferma = NULLIF(LTRIM(RTRIM(@Conferma)), '');

        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @IdSede AND InternaEsterna = 'I')
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La sede indicata non esiste o non è una sede interna';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- Sede di partenza + tutte le sotto-sedi collegate (tblSedi.IdParent, tblSedi.IdAziendaInterna,
        -- tblSediEsterne.IdSedeInterna), a qualunque profondità. Ciclo con deduplica esplicita anziché
        -- CTE ricorsiva: le tre relazioni unite possono formare cicli sui dati reali, e una CTE
        -- ricorsiva pura non deduplica tra un livello e l'altro, rischiando MAXRECURSION anche in
        -- assenza di un vero ciclo logico.
        -- COLLATE DATABASE_DEFAULT esplicito: senza, la colonna erediterebbe la collation di tempdb
        -- (non convertita insieme al DB, vedi project_collation_conversion), in conflitto con le
        -- colonne CHAR(16) del database nei confronti/JOIN sottostanti.
        CREATE TABLE #Sedi (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
        INSERT INTO #Sedi (Id) VALUES (@IdSede);

        DECLARE @nuoveRighe INT = 1;
        WHILE @nuoveRighe > 0
        BEGIN
            INSERT INTO #Sedi (Id)
            SELECT DISTINCT x.Id
            FROM (
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdParent = c.Id
                UNION
                SELECT s.Id FROM dbo.tblSedi s INNER JOIN #Sedi c ON s.IdAziendaInterna = c.Id
                UNION
                SELECT se.Id FROM dbo.tblSediEsterne se INNER JOIN #Sedi c ON se.IdSedeInterna = c.Id
            ) x
            WHERE NOT EXISTS (SELECT 1 FROM #Sedi t WHERE t.Id = x.Id);

            SET @nuoveRighe = @@ROWCOUNT;
        END

        DECLARE @totaleSedi INT = (SELECT COUNT(*) FROM #Sedi);

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui)
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #Etichette FROM dbo.tblEtichette WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Calendari FROM dbo.tblCalendari WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Eventi FROM dbo.tblEventi WHERE IdCalendario IN (SELECT Id FROM #Calendari);
        SELECT Id INTO #Tipi FROM dbo.tblTipi WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #TipiProprieta FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #Tipi);
        SELECT Id INTO #Persone FROM dbo.tblPersone WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Oggetti FROM dbo.tblOggetti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Gestione EoW: lotti/allocazioni/magazzini specifici EoW di proprietà della sede (solo sedi
        -- interne, IdSede diretto su tutte e tre le tabelle) - vedi project_eow_module_design in
        -- memoria persistente.
        SELECT Id INTO #EoWLotti FROM dbo.tblEoWLotti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #EoWAllocazioni FROM dbo.tblEoWAllocazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #EoWMagazzini FROM dbo.tblEoWMagazzini WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Modulo Magazzino: Articoli/Movimenti hanno IdSede = Azienda; Lotti hanno IdSede = sede
        -- operativa (può essere una sede figlia diversa dall'Azienda) - vedi project_magazzino
        -- in memoria persistente.
        SELECT Id INTO #MagArticoli FROM dbo.tblMagazziniArticoli WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #MagLotti FROM dbo.tblMagazziniLotti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #MagMovimenti FROM dbo.tblMagazziniMovimenti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Anagrafica estesa e Fatturazione: schede dell'azienda (o sul soggetto, se nella cascata),
        -- banche/casse e aliquote IVA proprie dell'azienda
        SELECT Id INTO #ClientiFornitori FROM dbo.tblClientiFornitori
        WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi) OR IdSede IN (SELECT Id FROM #Sedi);
        -- Schede amministratore dell'azienda (o su un soggetto della cascata)
        SELECT Id INTO #Amministratori FROM dbo.tblAmministratori
        WHERE IdAziendaInterna IN (SELECT Id FROM #Sedi) OR IdSede IN (SELECT Id FROM #Sedi);
        -- Fatture dell'azienda (o di una scheda della cascata) e conti dell'azienda
        SELECT Id INTO #Fatture FROM dbo.tblFatture
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);
        SELECT Id INTO #FattureConti FROM dbo.tblFattureConti WHERE IdSede IN (SELECT Id FROM #Sedi);        SELECT Id INTO #BancheCasse FROM dbo.tblBancheCasse WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #AliquoteIva FROM dbo.tblAliquoteIva WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Dichiarazioni MUD dell'azienda o che citano una sede della cascata
        SELECT Id INTO #RifiutiMud FROM dbo.tblRifiutiMud
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdSedeLegale IN (SELECT Id FROM #Sedi) OR IdSedeUnitaLocale IN (SELECT Id FROM #Sedi);

        -- tblSedi/tblPersone/tblOggetti sono sottotipi a chiave condivisa di tblOsepe (stesso Id)
        SELECT Id INTO #OsepeIds FROM (
            SELECT Id FROM #Sedi
            UNION
            SELECT Id FROM #Persone
            UNION
            SELECT Id FROM #Oggetti
        ) x;

        SELECT Id INTO #RifiutiRegistri FROM dbo.tblRifiutiRegistri WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiAutorizzazioni FROM dbo.tblRifiutiAutorizzazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblRifiutiLimiti.IdSede è NOT NULL (proprietà della sede) e IdRegistro è nullable (scoping
        -- opzionale a un registro specifico della stessa sede) - entrambi i rami coperti per sicurezza.
        SELECT Id INTO #RifiutiLimiti FROM dbo.tblRifiutiLimiti
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiMovimenti
        FROM dbo.tblRifiutiMovimenti
        WHERE IdSedeProduttoreDetentore IN (SELECT Id FROM #Sedi)
           OR IdSedeDestinatario        IN (SELECT Id FROM #Sedi)
           OR IdSedeTrasportatore1      IN (SELECT Id FROM #Sedi)
           OR IdSedeIntermediario1      IN (SELECT Id FROM #Sedi)
           OR IdRegistro                IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        SELECT Id INTO #Scadenze
        FROM dbo.tblScadenze
        WHERE IdEvento IN (SELECT Id FROM #Eventi)
           OR IdTipo   IN (SELECT Id FROM #Tipi);

        SELECT Id INTO #Servizi
        FROM dbo.tblServizi
        WHERE IdEvento      IN (SELECT Id FROM #Eventi)
           OR IdRichiedente IN (SELECT Id FROM #Sedi)
           OR IdTipo        IN (SELECT Id FROM #Tipi);

        -- tblAreeSediInterne/tblAreeOsepe/tblUtentiSediInterne sono giunzioni a chiave composita
        -- verso risorse condivise a livello di Dominio (tblAree, tblUtenti), non di proprietà della
        -- sede: si cancellano solo le righe di giunzione, mai tblAree/tblUtenti stesse.
        SELECT Id, IdSede  INTO #AreeSediInterne FROM dbo.tblAreeSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id, IdOsepe INTO #AreeOsepe       FROM dbo.tblAreeOsepe       WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

        -- Fatturazione: righe e rate delle fatture della cascata e pagamenti che potrebbero essere
        -- cancellati (quelli dell'azienda o delle sue banche e casse, e quelli che coprono rate di
        -- queste fatture), raccolti qui per la pulizia finale degli Id. Un pagamento che copre anche
        -- rate di altre fatture non viene cancellato: la pulizia toglie solo gli Id dei pagamenti
        -- che alla fine non esistono più
        SELECT Id INTO #FattureRighe FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #FattureRate FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #PagamentiCandidati FROM (
            SELECT Id FROM dbo.tblPagamenti
            WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi)
            UNION
            SELECT rp.IdPagamento FROM dbo.tblFattureRatePagamenti rp
            WHERE rp.IdRata IN (SELECT Id FROM #FattureRate)
        ) x;

        -- Offerte e contratti: importi (con le righe) e offerte o contratti dell'azienda, o di una
        -- scheda cliente della cascata
        SELECT Id INTO #Importi FROM dbo.tblImporti WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #ImportiRighe FROM dbo.tblImportiRighe WHERE IdImporto IN (SELECT Id FROM #Importi);
        SELECT Id INTO #OfferteContratti FROM dbo.tblOfferteContratti
        WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            -- Offerte e contratti, per primi: referenziano fatture, schede cliente, conti, aliquote,
            -- etichette, tipi e sedi cancellati più sotto. I documenti fatturabili (registrazioni,
            -- movimenti di magazzino, servizi) hanno lo stesso Id del documento
            DELETE FROM dbo.tblFattureDocumenti
            WHERE
                Id IN (SELECT Id FROM #RifiutiRegistrazioni)
                OR Id IN (SELECT Id FROM #MagMovimenti)
                OR Id IN (SELECT Id FROM #Servizi)
                OR IdFattura IN (SELECT Id FROM #Fatture)
                OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori)
                OR IdImporto IN (SELECT Id FROM #Importi)
                OR IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContrattiImporti
            WHERE IdOffertaContratto IN (SELECT Id FROM #OfferteContratti) OR IdImporto IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblOfferteContratti WHERE Id IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblImportiRigheDettagli WHERE Id IN (SELECT Id FROM #ImportiRighe);
            DELETE FROM dbo.tblImportiRighe WHERE Id IN (SELECT Id FROM #ImportiRighe);
            DELETE FROM dbo.tblImportiRifiuti WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImportiMagazzino WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImportiServizi WHERE Id IN (SELECT Id FROM #Importi);
            DELETE FROM dbo.tblImporti WHERE Id IN (SELECT Id FROM #Importi);
            -- Importi di ALTRE aziende che citano una sede, un'etichetta, un tipo, un conto o
            -- un'aliquota della cascata (non previsto dalle regole): perdono solo il collegamento
            UPDATE dbo.tblImportiRifiuti SET IdProduttoreParent = NULL WHERE IdProduttoreParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdProduttore = NULL WHERE IdProduttore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdTrasportatore = NULL WHERE IdTrasportatore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdIntermediario = NULL WHERE IdIntermediario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiMagazzino SET IdMittenteParent = NULL WHERE IdMittenteParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdMittente = NULL WHERE IdMittente IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatarioParent = NULL WHERE IdDestinatarioParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdRichiedenteParent = NULL WHERE IdRichiedenteParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdRichiedente = NULL WHERE IdRichiedente IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEsecutore = NULL WHERE IdEsecutore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdTipo = NULL WHERE IdTipo IN (SELECT Id FROM #Tipi);
            UPDATE dbo.tblImportiRigheDettagli SET IdConto = NULL WHERE IdConto IN (SELECT Id FROM #FattureConti);
            UPDATE dbo.tblImportiRigheDettagli SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);

            DELETE FROM dbo.tblRifiutiAutorizzazioniAttivita         WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniConducenti       WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniEer              WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTarghe           WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            -- FK NO_ACTION verso tblRifiutiModelli: righe della generazione automatica dei carichi
            -- (IdModello NOT NULL, si cancellano) e movimenti creati dal modello (IdModello nullable,
            -- perdono solo il collegamento)
            DELETE ae
            FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette ae
            INNER JOIN dbo.tblRifiutiModelliRegistrazioniAuto a ON ae.Id = a.Id
            WHERE a.IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAuto WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            UPDATE dbo.tblRifiutiMovimenti SET IdModello = NULL WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            DELETE FROM dbo.tblRifiutiFormulariEtichette             WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti     WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                      WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Modulo Magazzino: cascata figlio->genitore (FK NO_ACTION, nessun ON DELETE CASCADE).
            -- Va fatta prima della Gestione EoW: le righe EoW di scarico referenziano tblEoWLotti.
            -- Relazioni carico/scarico in entrambi i versi (righe della sede, dei suoi movimenti o
            -- dei suoi lotti): FK NO_ACTION su Id e IdParent verso tblMagazziniMovimentiRighe.
            DELETE rel
            FROM dbo.tblMagazziniMovimentiRigheRelazioni rel
            INNER JOIN dbo.tblMagazziniMovimentiRighe r ON rel.Id = r.Id OR rel.IdParent = r.Id
            WHERE r.IdSede IN (SELECT Id FROM #Sedi) OR r.IdMovimento IN (SELECT Id FROM #MagMovimenti) OR r.IdLotto IN (SELECT Id FROM #MagLotti);

            DELETE rel
            FROM dbo.tblMagazziniMovimentiRigheEoWLotti rel
            INNER JOIN dbo.tblMagazziniMovimentiRigheEoW re ON rel.Id = re.Id
            WHERE
                re.IdSede IN (SELECT Id FROM #Sedi)
                OR re.IdMovimento IN (SELECT Id FROM #MagMovimenti)
                OR re.IdLotto IN (SELECT Id FROM #EoWLotti)
                OR rel.IdLotto IN (SELECT Id FROM #EoWLotti);

            DELETE FROM dbo.tblMagazziniDdt
            WHERE
                IdSede IN (SELECT Id FROM #Sedi)
                OR IdMittente IN (SELECT Id FROM #Sedi)
                OR IdDestinatario IN (SELECT Id FROM #Sedi)
                OR IdDestinazione IN (SELECT Id FROM #Sedi)
                OR IdTrasportatore IN (SELECT Id FROM #Sedi)
                OR IdMovimento IN (SELECT Id FROM #MagMovimenti);

            DELETE FROM dbo.tblMagazziniMovimentiRighe
            WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdMovimento IN (SELECT Id FROM #MagMovimenti) OR IdLotto IN (SELECT Id FROM #MagLotti);
            DELETE FROM dbo.tblMagazziniMovimentiRigheEoW
            WHERE IdSede IN (SELECT Id FROM #Sedi) OR IdMovimento IN (SELECT Id FROM #MagMovimenti) OR IdLotto IN (SELECT Id FROM #EoWLotti);

            DELETE FROM dbo.tblMagazziniMovimenti WHERE Id IN (SELECT Id FROM #MagMovimenti);
            DELETE FROM dbo.tblMagazziniLotti WHERE Id IN (SELECT Id FROM #MagLotti);
            DELETE FROM dbo.tblMagazziniArticoli WHERE Id IN (SELECT Id FROM #MagArticoli);

            -- Gestione EoW: va fatta prima di cancellare Registrazioni sottostanti, per rispettare
            -- la FK di tblEoWLottiRifiutiRegistrazioni.IdRegistrazione (NOT NULL, parte della PK
            -- composta con IdLotto - non azzerabile, la riga di collegamento va sempre rimossa,
            -- anche quando referenzia una Registrazione di questa sede legata a un Lotto di un'altra:
            -- stesso motivo dell'OR su #RifiutiRegistrazioni). I lotti/allocazioni EoW di questa sede
            -- vengono invece cancellati per intero (non azzerati) perché sono risorse di proprietà
            -- esclusiva della sede stessa, non condivise con altre sedi.
            DELETE FROM dbo.tblEoWLottiRifiutiRegistrazioni
            WHERE IdLotto        IN (SELECT Id FROM #EoWLotti)
               OR IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblEoWLottiAllocazioni
            WHERE IdLotto      IN (SELECT Id FROM #EoWLotti)
               OR IdAllocazione IN (SELECT Id FROM #EoWAllocazioni);
            DELETE FROM dbo.tblEoWLotti       WHERE Id IN (SELECT Id FROM #EoWLotti);
            DELETE FROM dbo.tblEoWAllocazioni WHERE Id IN (SELECT Id FROM #EoWAllocazioni);

            -- tblEoWLotti.IdMagazzino (nullable, nessun vincolo strutturale che lo leghi allo stesso
            -- IdSede del Lotto) può referenziare un Magazzino di questa sede anche da un Lotto esterno
            -- alla cascata - i Lotti di questa sede sono già stati cancellati sopra, quindi qui restano
            -- solo eventuali riferimenti esterni: azzerati, non cancellati (stessa logica "UPDATE=NULL
            -- dove possibile" delle risorse condivise più sotto).
            DECLARE @eoWLottiScollegati INT;
            UPDATE dbo.tblEoWLotti SET IdMagazzino = NULL WHERE IdMagazzino IN (SELECT Id FROM #EoWMagazzini);
            SET @eoWLottiScollegati = @@ROWCOUNT;
            DELETE FROM dbo.tblEoWMagazzini WHERE Id IN (SELECT Id FROM #EoWMagazzini);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va rimossa prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se una registrazione in cancellazione è coinvolta in una rettifica.
            DELETE FROM dbo.tblRentriRegistrazioniRettifiche
            WHERE Id          IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdRettifica IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRifiutiLimiti* va rimosso prima di tblRifiutiRegistri: FK NO_ACTION su IdRegistro
            -- bloccherebbe altrimenti la cancellazione del registro sottostante.
            DELETE FROM dbo.tblRifiutiLimitiEer        WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiEtichette  WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimitiOperazioni WHERE IdLimite IN (SELECT Id FROM #RifiutiLimiti);
            DELETE FROM dbo.tblRifiutiLimiti           WHERE Id IN (SELECT Id FROM #RifiutiLimiti);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL, nessun
            -- ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante fallisce per FK.
            DELETE FROM dbo.tblRentriRegistri  WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            -- Dichiarazioni MUD: registri della dichiarazione (FK su tblRifiutiMud e su
            -- tblRifiutiRegistri), poi la dichiarazione
            DELETE FROM dbo.tblRifiutiMudRegistri
            WHERE Id IN (SELECT Id FROM #RifiutiMud) OR IdRegistro IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblRifiutiMud WHERE Id IN (SELECT Id FROM #RifiutiMud);

            DELETE FROM dbo.tblRifiutiRegistri WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            DELETE FROM dbo.tblScadenzeOsepe
            WHERE Id      IN (SELECT Id FROM #Scadenze)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblScadenze WHERE Id IN (SELECT Id FROM #Scadenze);

            DELETE FROM dbo.tblServiziOsepe
            WHERE Id      IN (SELECT Id FROM #Servizi)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblServizi WHERE Id IN (SELECT Id FROM #Servizi);

            DELETE FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipi          WHERE Id IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblEventiFirme      WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiProprieta  WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiUtenti     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenzeEccezioni
            WHERE Id       IN (SELECT Id FROM #Eventi)
               OR IdEvento IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenze WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventi     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblCalendari  WHERE Id IN (SELECT Id FROM #Calendari);

            -- Risorse riutilizzabili di proprietà della sede: prima di cancellarle si liberano da
            -- eventuali riferimenti di ALTRE sedi non coinvolte nella cascata. Dove la colonna è
            -- nullable si azzera il riferimento (la riga esterna resta, perde solo il collegamento);
            -- dove è NOT NULL non è possibile azzerarla, quindi si cancella la riga di giunzione
            -- esterna stessa. Scelta esplicita dell'utente: tocca dati di altre sedi pur di
            -- garantire che Etichette/Autorizzazioni di questa sede vengano sempre rimosse.
            DECLARE @rifEsterniRimossi INT = 0;

            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneDestinatario = NULL         WHERE IdAutorizzazioneDestinatario         IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneIntermediario1 = NULL       WHERE IdAutorizzazioneIntermediario1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneProduttoreDetentore = NULL  WHERE IdAutorizzazioneProduttoreDetentore  IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore1 = NULL       WHERE IdAutorizzazioneTrasportatore1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore2 = NULL       WHERE IdAutorizzazioneTrasportatore2       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiMovimentiDestinatari   WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari  WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiProduttori    WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiFormulariEtichette     WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblEtichette             WHERE Id IN (SELECT Id FROM #Etichette);
            DELETE FROM dbo.tblRifiutiAutorizzazioni WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblPersoneRuoli WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblPersone      WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblOggetti      WHERE Id IN (SELECT Id FROM #Oggetti);

            -- Anagrafica estesa e Fatturazione: prima le schede, che referenziano banche/casse e
            -- aliquote; le schede di ALTRE aziende che usano un'aliquota o una banca di questa
            -- (non previsto dalle regole) perdono solo il collegamento
            -- Fatturazione: fatture con righe, rate e pagamenti (prima delle schede, delle banche e
            -- delle aliquote, che le fatture referenziano)
            DELETE FROM dbo.tblFattureRigheImporti WHERE Id IN (SELECT Id FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
            SELECT DISTINCT rp.IdPagamento AS Id INTO #Pagamenti
            FROM dbo.tblFattureRatePagamenti rp INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
            WHERE r.IdFattura IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFattureRatePagamenti WHERE IdRata IN (SELECT Id FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblPagamenti
            WHERE Id IN (SELECT Id FROM #Pagamenti) AND Id NOT IN (SELECT IdPagamento FROM dbo.tblFattureRatePagamenti);
            DELETE FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
            UPDATE dbo.tblFatture SET IdFatturaRiferimento = NULL WHERE IdFatturaRiferimento IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFatture WHERE Id IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblClientiFornitori WHERE Id IN (SELECT Id FROM #ClientiFornitori);
            DELETE FROM dbo.tblAmministratoriSedi
            WHERE Id IN (SELECT Id FROM #Amministratori) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblAmministratori WHERE Id IN (SELECT Id FROM #Amministratori);
            UPDATE dbo.tblClientiFornitori SET IdBancaCassa = NULL WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse);
            UPDATE dbo.tblClientiFornitori SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);
            -- Conti: le righe di ALTRE aziende che li usano (non previsto dalle regole) perdono solo il
            -- collegamento, come per banche/casse e aliquote
            UPDATE dbo.tblFattureRigheImporti SET IdConto = NULL WHERE IdConto IN (SELECT Id FROM #FattureConti);
            DELETE FROM dbo.tblFattureConti WHERE Id IN (SELECT Id FROM #FattureConti);
            DELETE FROM dbo.tblFattureDatiFiscali WHERE Id IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblFattureRigheImporti SET IdAliquotaIva = NULL WHERE IdAliquotaIva IN (SELECT Id FROM #AliquoteIva);
            UPDATE dbo.tblFatture SET IdBancaCassa = NULL WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse);
            DELETE FROM dbo.tblFattureRatePagamenti
            WHERE IdPagamento IN (SELECT Id FROM dbo.tblPagamenti WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi));
            DELETE FROM dbo.tblPagamenti WHERE IdBancaCassa IN (SELECT Id FROM #BancheCasse) OR IdSede IN (SELECT Id FROM #Sedi);            DELETE FROM dbo.tblBancheCasse WHERE Id IN (SELECT Id FROM #BancheCasse);
            DELETE FROM dbo.tblAliquoteIva WHERE Id IN (SELECT Id FROM #AliquoteIva);

            -- Giunzioni a chiave composita verso risorse condivise (tblAree/tblUtenti non toccate)
            DELETE asi FROM dbo.tblAreeSediInterne asi INNER JOIN #AreeSediInterne t ON t.Id = asi.Id AND t.IdSede  = asi.IdSede;
            DELETE ao  FROM dbo.tblAreeOsepe       ao  INNER JOIN #AreeOsepe       t ON t.Id = ao.Id  AND t.IdOsepe = ao.IdOsepe;
            DELETE FROM dbo.tblUtentiSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL (nessuna
            -- colonna da azzerare) - si cancella la riga di associazione, mai tblRentriCredenziali stessa.
            DELETE FROM dbo.tblRentriCredenzialiSedi WHERE IdSede IN (SELECT Id FROM #Sedi);

            DELETE FROM dbo.tblSediDatiEstesi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediRecapiti  WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediEsterne   WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediInterne   WHERE Id IN (SELECT Id FROM #Sedi);

            -- Radice e sotto-sedi cancellate in un'unica istruzione set-based: i vincoli
            -- auto-referenziati IdParent/IdAziendaInterna sono verificati a fine istruzione (non
            -- riga per riga), quindi non si bloccano a vicenda anche su gerarchie a più livelli.
            DELETE FROM dbo.tblSedi WHERE Id IN (SELECT Id FROM #Sedi);

            -- tblOsepe: supertipo condiviso di Sedi/Persone/Oggetti, cancellato per ultimo
            DELETE FROM dbo.tblOsepe WHERE Id IN (SELECT Id FROM #OsepeIds);

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get), solo per le entità con Id
            -- proprio (non per le tabelle a chiave condivisa/giunzione, già coperte a monte)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #OsepeIds
                UNION SELECT Id FROM #Calendari
                UNION SELECT Id FROM #Etichette
                UNION SELECT Id FROM #Eventi
                UNION SELECT Id FROM #MagArticoli
                UNION SELECT Id FROM #MagLotti
                UNION SELECT Id FROM #MagMovimenti
                UNION SELECT Id FROM #ClientiFornitori
                UNION SELECT Id FROM #Fatture
                UNION SELECT Id FROM #FattureRighe
                UNION SELECT Id FROM #FattureRate
                UNION SELECT Id FROM #FattureConti
                UNION SELECT Id FROM #PagamentiCandidati WHERE Id NOT IN (SELECT Id FROM dbo.tblPagamenti)
                UNION SELECT Id FROM #Importi
                UNION SELECT Id FROM #ImportiRighe
                UNION SELECT Id FROM #OfferteContratti
                UNION SELECT Id FROM #Amministratori
                UNION SELECT Id FROM #BancheCasse
                UNION SELECT Id FROM #AliquoteIva
                UNION SELECT Id FROM #RifiutiMud
                UNION SELECT Id FROM #EoWLotti
                UNION SELECT Id FROM #EoWAllocazioni
                UNION SELECT Id FROM #EoWMagazzini
                UNION SELECT Id FROM #RifiutiAutorizzazioni
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiRegistri
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT Id FROM #RifiutiLimiti
                UNION SELECT Id FROM #Scadenze
                UNION SELECT Id FROM #Servizi
                UNION SELECT Id FROM #Tipi
                UNION SELECT Id FROM #TipiProprieta
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT('Cancellazione completata. Sedi rimosse: ', @totaleSedi, '. Riferimenti esterni azzerati/rimossi su Etichette/Autorizzazioni condivise: ', @rifEsterniRimossi, '. Lotti EoW rimossi: ', (SELECT COUNT(*) FROM #EoWLotti), ', Allocazioni EoW rimosse: ', (SELECT COUNT(*) FROM #EoWAllocazioni), ', Magazzini EoW rimossi: ', (SELECT COUNT(*) FROM #EoWMagazzini), ' (Lotti esterni scollegati: ', @eoWLottiScollegati, ')', ', Limiti rifiuti rimossi: ', (SELECT COUNT(*) FROM #RifiutiLimiti), '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
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

PRINT 'sql/procedures/uspSYS_del_SedeEsternaCascade.sql';
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.uspSYS_del_SedeEsternaCascade
    @IdSede   CHAR(16)    = NULL,
    @Conferma VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        DECLARE @returnValue   INT           = 0;
        DECLARE @returnMessage NVARCHAR(200) = NULL;

        SET @IdSede   = NULLIF(LTRIM(RTRIM(@IdSede)),   '');
        SET @Conferma = NULLIF(LTRIM(RTRIM(@Conferma)), '');

        IF @IdSede IS NULL
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Il parametro @IdSede non può essere vuoto';
            GOTO BRANCH_END;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.tblSedi WHERE Id = @IdSede AND InternaEsterna = 'E')
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'La sede indicata non esiste o non è una sede esterna';
            GOTO BRANCH_END;
        END

        -- Protezione: richiede conferma esplicita per evitare cancellazione accidentale (SP dev-only, non chiamata dall'app)
        IF ISNULL(@Conferma, '') <> 'conferma'
        BEGIN
            SET @returnValue = -1; SET @returnMessage = 'Passare @Conferma = ''conferma'' per procedere con la cancellazione definitiva';
            GOTO BRANCH_END;
        END

        -- Sede di partenza + eventuali sotto-sedi collegate tramite tblSedi.IdParent (es. altre
        -- sedi/filiali dello stesso cliente/fornitore esterno), a qualunque profondità. A
        -- differenza di una sede interna, da una sede esterna NON si scende mai tramite
        -- IdAziendaInterna (punta sempre in alto verso la sede interna che la gestisce, mai verso
        -- un'altra sede da cancellare) né tramite tblSediEsterne.IdSedeInterna (stesso concetto).
        -- COLLATE DATABASE_DEFAULT esplicito: senza, la colonna erediterebbe la collation di tempdb
        -- (non convertita insieme al DB, vedi project_collation_conversion), in conflitto con le
        -- colonne CHAR(16) del database nei confronti/JOIN sottostanti.
        CREATE TABLE #Sedi (Id CHAR(16) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
        INSERT INTO #Sedi (Id) VALUES (@IdSede);

        DECLARE @nuoveRighe INT = 1;
        WHILE @nuoveRighe > 0
        BEGIN
            INSERT INTO #Sedi (Id)
            SELECT DISTINCT s.Id
            FROM dbo.tblSedi s
            INNER JOIN #Sedi c ON s.IdParent = c.Id
            WHERE NOT EXISTS (SELECT 1 FROM #Sedi t WHERE t.Id = s.Id);

            SET @nuoveRighe = @@ROWCOUNT;
        END

        DECLARE @totaleSedi INT = (SELECT COUNT(*) FROM #Sedi);

        -- --------------------------------------------------------------------------------------
        -- Fase 1: raccolta degli Id da cancellare (nessuna DELETE eseguita qui). Stessa struttura
        -- generica di uspSYS_del_SedeInternaCascade: tutte queste tabelle referenziano tblSedi.Id
        -- indipendentemente dal tipo (interna/esterna), anche se in pratica per una sede esterna
        -- oggi solo Autorizzazioni e Movimenti risultano popolati (verificato). Gestione EoW esclusa:
        -- i Magazzini EoW sono di sede interna (confermato dall'utente), una sede esterna non ne ha
        -- di propri - può però avere un proprio Registro/Registrazioni referenziati da movimenti EoW
        -- di un magazzino interno, gestiti più sotto.
        -- --------------------------------------------------------------------------------------
        SELECT Id INTO #Etichette FROM dbo.tblEtichette WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Calendari FROM dbo.tblCalendari WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Eventi FROM dbo.tblEventi WHERE IdCalendario IN (SELECT Id FROM #Calendari);
        SELECT Id INTO #Tipi FROM dbo.tblTipi WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #TipiProprieta FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #Tipi);
        SELECT Id INTO #Persone FROM dbo.tblPersone WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #Oggetti FROM dbo.tblOggetti WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- Anagrafica estesa: schede cliente/fornitore sul soggetto
        SELECT Id INTO #ClientiFornitori FROM dbo.tblClientiFornitori WHERE IdSede IN (SELECT Id FROM #Sedi);
        -- Fatture delle schede cliente/fornitore del soggetto
        SELECT Id INTO #Fatture FROM dbo.tblFatture WHERE IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);        SELECT Id INTO #Amministratori FROM dbo.tblAmministratori WHERE IdSede IN (SELECT Id FROM #Sedi);

        -- tblSedi/tblPersone/tblOggetti sono sottotipi a chiave condivisa di tblOsepe (stesso Id)
        SELECT Id INTO #OsepeIds FROM (
            SELECT Id FROM #Sedi
            UNION
            SELECT Id FROM #Persone
            UNION
            SELECT Id FROM #Oggetti
        ) x;

        SELECT Id INTO #RifiutiRegistri FROM dbo.tblRifiutiRegistri WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiAutorizzazioni FROM dbo.tblRifiutiAutorizzazioni WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id INTO #RifiutiModelli FROM dbo.tblRifiutiModelli WHERE IdRegistro IN (SELECT Id FROM #RifiutiRegistri);

        -- tblRifiutiLimiti* non è mai popolato per una sede esterna (i Limiti si possono creare
        -- solo su sedi interne, confermato dall'utente): a differenza di uspSYS_del_SedeInternaCascade,
        -- qui non serve raccoglierlo/cancellarlo.

        SELECT Id INTO #RifiutiMovimenti
        FROM dbo.tblRifiutiMovimenti
        WHERE IdSedeProduttoreDetentore IN (SELECT Id FROM #Sedi)
           OR IdSedeDestinatario        IN (SELECT Id FROM #Sedi)
           OR IdSedeTrasportatore1      IN (SELECT Id FROM #Sedi)
           OR IdSedeIntermediario1      IN (SELECT Id FROM #Sedi)
           OR IdRegistro                IN (SELECT Id FROM #RifiutiRegistri);

        SELECT Id INTO #RifiutiFormulari FROM dbo.tblRifiutiFormulari WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);
        SELECT Id INTO #RifiutiRegistrazioni FROM dbo.tblRifiutiRegistrazioni WHERE IdMovimento IN (SELECT Id FROM #RifiutiMovimenti);

        SELECT Id INTO #Scadenze
        FROM dbo.tblScadenze
        WHERE IdEvento IN (SELECT Id FROM #Eventi)
           OR IdTipo   IN (SELECT Id FROM #Tipi);

        SELECT Id INTO #Servizi
        FROM dbo.tblServizi
        WHERE IdEvento      IN (SELECT Id FROM #Eventi)
           OR IdRichiedente IN (SELECT Id FROM #Sedi)
           OR IdTipo        IN (SELECT Id FROM #Tipi);

        -- tblAreeSediInterne/tblAreeOsepe sono giunzioni a chiave composita verso risorse condivise
        -- a livello di Dominio (tblAree), non di proprietà della sede: si cancellano solo le righe
        -- di giunzione, mai tblAree stessa.
        SELECT Id, IdSede  INTO #AreeSediInterne FROM dbo.tblAreeSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);
        SELECT Id, IdOsepe INTO #AreeOsepe       FROM dbo.tblAreeOsepe       WHERE IdOsepe IN (SELECT Id FROM #OsepeIds);

        -- Fatturazione: righe e rate delle fatture della cascata e pagamenti che coprono le loro
        -- rate, raccolti qui per la pulizia finale degli Id. Un pagamento che copre anche rate di
        -- altre fatture non viene cancellato: la pulizia toglie solo gli Id dei pagamenti che alla
        -- fine non esistono più
        SELECT Id INTO #FattureRighe FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT Id INTO #FattureRate FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
        SELECT DISTINCT rp.IdPagamento AS Id INTO #PagamentiCandidati
        FROM dbo.tblFattureRatePagamenti rp
        WHERE rp.IdRata IN (SELECT Id FROM #FattureRate);

        -- Offerte e contratti: offerte e contratti delle schede cliente del soggetto
        SELECT Id INTO #OfferteContratti FROM dbo.tblOfferteContratti
        WHERE IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori);

        -- --------------------------------------------------------------------------------------
        -- Fase 2: cancellazione fisica, dalle foglie verso le radici
        -- --------------------------------------------------------------------------------------
        BEGIN TRANSACTION;

            -- Offerte e contratti, per primi: referenziano fatture, schede cliente, etichette, tipi e
            -- sedi cancellati più sotto. I documenti fatturabili (registrazioni, servizi) hanno lo
            -- stesso Id del documento. Gli importi dei contratti cancellati restano all'azienda
            -- interna, senza contratto
            DELETE FROM dbo.tblFattureDocumenti
            WHERE
                Id IN (SELECT Id FROM #RifiutiRegistrazioni)
                OR Id IN (SELECT Id FROM #Servizi)
                OR IdFattura IN (SELECT Id FROM #Fatture)
                OR IdClienteFornitore IN (SELECT Id FROM #ClientiFornitori)
                OR IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContrattiImporti WHERE IdOffertaContratto IN (SELECT Id FROM #OfferteContratti);
            DELETE FROM dbo.tblOfferteContratti WHERE Id IN (SELECT Id FROM #OfferteContratti);
            -- Importi che citano una sede, un'etichetta o un tipo della cascata: perdono solo la variabile
            UPDATE dbo.tblImportiRifiuti SET IdProduttoreParent = NULL WHERE IdProduttoreParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdProduttore = NULL WHERE IdProduttore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdTrasportatore = NULL WHERE IdTrasportatore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdIntermediario = NULL WHERE IdIntermediario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiRifiuti SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiMagazzino SET IdMittenteParent = NULL WHERE IdMittenteParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdMittente = NULL WHERE IdMittente IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatarioParent = NULL WHERE IdDestinatarioParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdDestinatario = NULL WHERE IdDestinatario IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiMagazzino SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdRichiedenteParent = NULL WHERE IdRichiedenteParent IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdRichiedente = NULL WHERE IdRichiedente IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEsecutore = NULL WHERE IdEsecutore IN (SELECT Id FROM #Sedi);
            UPDATE dbo.tblImportiServizi SET IdEtichetta = NULL WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            UPDATE dbo.tblImportiServizi SET IdTipo = NULL WHERE IdTipo IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblRifiutiAutorizzazioniAttivita         WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniConducenti       WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniEer              WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTarghe           WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);
            DELETE FROM dbo.tblRifiutiAutorizzazioniTargheEerEsclusi WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblRifiutiModelliClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE Id IN (SELECT Id FROM #RifiutiModelli);
            -- FK NO_ACTION verso tblRifiutiModelli: righe della generazione automatica dei carichi
            -- (IdModello NOT NULL, si cancellano) e movimenti creati dal modello (IdModello nullable,
            -- perdono solo il collegamento)
            DELETE ae
            FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette ae
            INNER JOIN dbo.tblRifiutiModelliRegistrazioniAuto a ON ae.Id = a.Id
            WHERE a.IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAuto WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            UPDATE dbo.tblRifiutiMovimenti SET IdModello = NULL WHERE IdModello IN (SELECT Id FROM #RifiutiModelli);
            DELETE FROM dbo.tblRifiutiModelli                WHERE Id IN (SELECT Id FROM #RifiutiModelli);

            DELETE FROM dbo.tblRifiutiMovimentiClassiPericolo WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiDestinatari    WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari   WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiLog            WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiProduttori     WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori  WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            DELETE FROM dbo.tblRifiutiFormulariEtichette             WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiFerroviari   WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiMarittimi    WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulariTrasportiTerresti     WHERE Id IN (SELECT Id FROM #RifiutiFormulari);
            DELETE FROM dbo.tblRifiutiFormulari                      WHERE Id IN (SELECT Id FROM #RifiutiFormulari);

            -- Gestione EoW: questa sede esterna non ha lotti/allocazioni EoW propri (che referenziano
            -- solo Sede Interna), ma le sue Registrazioni possono essere referenziate da
            -- tblEoWLottiRifiutiRegistrazioni.IdRegistrazione (NOT NULL, parte della PK composta con
            -- IdLotto) - non azzerabile come il vecchio tblEoWMovimenti.IdRegistrazione (nullable),
            -- va rimossa la riga di collegamento; il Lotto di una sede interna resta intatto.
            DELETE FROM dbo.tblEoWLottiRifiutiRegistrazioni WHERE IdRegistrazione IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            -- tblRentriRegistrazioniRettifiche: FK su Id/IdRettifica verso tblRifiutiRegistrazioni,
            -- nessun ON DELETE CASCADE - va rimossa prima, altrimenti la DELETE sottostante fallisce
            -- per violazione FK se una registrazione in cancellazione è coinvolta in una rettifica.
            DELETE FROM dbo.tblRentriRegistrazioniRettifiche
            WHERE Id          IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdRettifica IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiRegistrazioniRelazioni
            WHERE Id       IN (SELECT Id FROM #RifiutiRegistrazioni)
               OR IdParent IN (SELECT Id FROM #RifiutiRegistrazioni);
            DELETE FROM dbo.tblRifiutiRegistrazioni WHERE Id IN (SELECT Id FROM #RifiutiRegistrazioni);

            DELETE FROM dbo.tblRifiutiMovimenti WHERE Id IN (SELECT Id FROM #RifiutiMovimenti);

            -- tblRentriRegistri è 1:1 a chiave condivisa su tblRifiutiRegistri.Id (NOT NULL, nessun
            -- ON DELETE CASCADE): va rimosso prima, altrimenti la DELETE sottostante fallisce per FK.
            -- In pratica un Registro RENTRI appartiene sempre a una sede interna, ma la SP resta
            -- generica per coerenza con la raccolta #RifiutiRegistri già fatta sopra.
            DELETE FROM dbo.tblRentriRegistri  WHERE Id IN (SELECT Id FROM #RifiutiRegistri);
            DELETE FROM dbo.tblRifiutiRegistri WHERE Id IN (SELECT Id FROM #RifiutiRegistri);

            DELETE FROM dbo.tblScadenzeOsepe
            WHERE Id      IN (SELECT Id FROM #Scadenze)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblScadenze WHERE Id IN (SELECT Id FROM #Scadenze);

            DELETE FROM dbo.tblServiziOsepe
            WHERE Id      IN (SELECT Id FROM #Servizi)
               OR IdOsepe IN (SELECT Id FROM #OsepeIds);
            DELETE FROM dbo.tblServizi WHERE Id IN (SELECT Id FROM #Servizi);

            DELETE FROM dbo.tblTipiProprieta WHERE Id IN (SELECT Id FROM #TipiProprieta);
            DELETE FROM dbo.tblTipi          WHERE Id IN (SELECT Id FROM #Tipi);

            DELETE FROM dbo.tblEventiFirme      WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiProprieta  WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventiUtenti     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenzeEccezioni
            WHERE Id       IN (SELECT Id FROM #Eventi)
               OR IdEvento IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblRicorrenze WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblEventi     WHERE Id IN (SELECT Id FROM #Eventi);
            DELETE FROM dbo.tblCalendari  WHERE Id IN (SELECT Id FROM #Calendari);

            -- Risorse riutilizzabili di proprietà della sede: prima di cancellarle si liberano da
            -- eventuali riferimenti di ALTRE sedi non coinvolte nella cascata (stessa logica
            -- ibrida di uspSYS_del_SedeInternaCascade: UPDATE=NULL dove la colonna è nullable,
            -- DELETE della riga di giunzione dove è NOT NULL).
            DECLARE @rifEsterniRimossi INT = 0;

            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneDestinatario = NULL         WHERE IdAutorizzazioneDestinatario         IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneIntermediario1 = NULL       WHERE IdAutorizzazioneIntermediario1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneProduttoreDetentore = NULL  WHERE IdAutorizzazioneProduttoreDetentore  IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore1 = NULL       WHERE IdAutorizzazioneTrasportatore1       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            UPDATE dbo.tblRifiutiModelli SET IdAutorizzazioneTrasportatore2 = NULL       WHERE IdAutorizzazioneTrasportatore2       IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiMovimentiDestinatari   WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiIntermediari  WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiProduttori    WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiMovimentiTrasportatori WHERE IdAutorizzazione IN (SELECT Id FROM #RifiutiAutorizzazioni);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblRifiutiFormulariEtichette     WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliEtichette       WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiModelliRegistrazioniAutoEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;
            DELETE FROM dbo.tblRifiutiRegistrazioniEtichette WHERE IdEtichetta IN (SELECT Id FROM #Etichette);
            SET @rifEsterniRimossi += @@ROWCOUNT;

            DELETE FROM dbo.tblEtichette             WHERE Id IN (SELECT Id FROM #Etichette);
            DELETE FROM dbo.tblRifiutiAutorizzazioni WHERE Id IN (SELECT Id FROM #RifiutiAutorizzazioni);

            DELETE FROM dbo.tblPersoneRuoli WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblPersone      WHERE Id IN (SELECT Id FROM #Persone);
            DELETE FROM dbo.tblOggetti      WHERE Id IN (SELECT Id FROM #Oggetti);

            -- Modulo Magazzino: una sede esterna può comparire su un DDT come mittente (es. il
            -- fornitore di un DDT ricevuto), destinatario, destinazione o trasportatore
            -- (Articoli/Lotti/Movimenti/Righe sono sempre su sedi interne). Il DDT viene rimosso,
            -- il movimento di magazzino della sede interna resta.
            DELETE FROM dbo.tblMagazziniDdt
            WHERE
                IdMittente IN (SELECT Id FROM #Sedi)
                OR IdDestinatario IN (SELECT Id FROM #Sedi)
                OR IdDestinazione IN (SELECT Id FROM #Sedi)
                OR IdTrasportatore IN (SELECT Id FROM #Sedi);

            -- Anagrafica estesa: schede cliente/fornitore sul soggetto
            -- Fatturazione: fatture con righe, rate e pagamenti (prima delle schede, delle banche e
            -- delle aliquote, che le fatture referenziano)
            DELETE FROM dbo.tblFattureRigheImporti WHERE Id IN (SELECT Id FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblFattureRighe WHERE IdFattura IN (SELECT Id FROM #Fatture);
            SELECT DISTINCT rp.IdPagamento AS Id INTO #Pagamenti
            FROM dbo.tblFattureRatePagamenti rp INNER JOIN dbo.tblFattureRate r ON rp.IdRata = r.Id
            WHERE r.IdFattura IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFattureRatePagamenti WHERE IdRata IN (SELECT Id FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture));
            DELETE FROM dbo.tblPagamenti
            WHERE Id IN (SELECT Id FROM #Pagamenti) AND Id NOT IN (SELECT IdPagamento FROM dbo.tblFattureRatePagamenti);
            DELETE FROM dbo.tblFattureRate WHERE IdFattura IN (SELECT Id FROM #Fatture);
            UPDATE dbo.tblFatture SET IdFatturaRiferimento = NULL WHERE IdFatturaRiferimento IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblFatture WHERE Id IN (SELECT Id FROM #Fatture);
            DELETE FROM dbo.tblClientiFornitori WHERE Id IN (SELECT Id FROM #ClientiFornitori);

            -- Anagrafica estesa: schede amministratore del soggetto con i loro amministrati, e il
            -- soggetto tolto dagli amministrati delle altre schede
            DELETE FROM dbo.tblAmministratoriSedi
            WHERE Id IN (SELECT Id FROM #Amministratori) OR IdSede IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblAmministratori WHERE Id IN (SELECT Id FROM #Amministratori);

            -- Giunzioni a chiave composita verso risorse condivise (tblAree non toccata)
            DELETE asi FROM dbo.tblAreeSediInterne asi INNER JOIN #AreeSediInterne t ON t.Id = asi.Id AND t.IdSede  = asi.IdSede;
            DELETE ao  FROM dbo.tblAreeOsepe       ao  INNER JOIN #AreeOsepe       t ON t.Id = ao.Id  AND t.IdOsepe = ao.IdOsepe;
            DELETE FROM dbo.tblUtentiSediInterne WHERE IdSede IN (SELECT Id FROM #Sedi);

            -- tblRentriCredenzialiSedi: giunzione Sede/Credenziale RENTRI, IdSede NOT NULL (nessuna
            -- colonna da azzerare). In pratica associata solo a sedi interne, ma la SP resta generica
            -- per lo stesso motivo della raccolta #RifiutiRegistri sopra.
            DELETE FROM dbo.tblRentriCredenzialiSedi WHERE IdSede IN (SELECT Id FROM #Sedi);

            DELETE FROM dbo.tblSediDatiEstesi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediIndirizzi WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediRecapiti  WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediEsterne   WHERE Id IN (SELECT Id FROM #Sedi);
            DELETE FROM dbo.tblSediInterne   WHERE Id IN (SELECT Id FROM #Sedi);

            -- Radice e sotto-sedi cancellate in un'unica istruzione set-based: il vincolo
            -- auto-referenziato IdParent è verificato a fine istruzione (non riga per riga), quindi
            -- non si blocca da solo anche su gerarchie a più livelli.
            DELETE FROM dbo.tblSedi WHERE Id IN (SELECT Id FROM #Sedi);

            -- tblOsepe: supertipo condiviso di Sedi/Persone/Oggetti, cancellato per ultimo
            DELETE FROM dbo.tblOsepe WHERE Id IN (SELECT Id FROM #OsepeIds);

            -- Pulizia del generatore di Id condiviso (dbo.uspId_get), solo per le entità con Id
            -- proprio (non per le tabelle a chiave condivisa/giunzione, già coperte a monte)
            SELECT Id INTO #IdDaRipulire FROM (
                SELECT Id FROM #OsepeIds
                UNION SELECT Id FROM #Calendari
                UNION SELECT Id FROM #Etichette
                UNION SELECT Id FROM #Eventi
                UNION SELECT Id FROM #ClientiFornitori
                UNION SELECT Id FROM #Fatture
                UNION SELECT Id FROM #FattureRighe
                UNION SELECT Id FROM #FattureRate
                UNION SELECT Id FROM #PagamentiCandidati WHERE Id NOT IN (SELECT Id FROM dbo.tblPagamenti)
                UNION SELECT Id FROM #OfferteContratti
                UNION SELECT Id FROM #Amministratori
                UNION SELECT Id FROM #RifiutiAutorizzazioni
                UNION SELECT Id FROM #RifiutiFormulari
                UNION SELECT Id FROM #RifiutiModelli
                UNION SELECT Id FROM #RifiutiMovimenti
                UNION SELECT Id FROM #RifiutiRegistri
                UNION SELECT Id FROM #RifiutiRegistrazioni
                UNION SELECT Id FROM #Scadenze
                UNION SELECT Id FROM #Servizi
                UNION SELECT Id FROM #Tipi
                UNION SELECT Id FROM #TipiProprieta
            ) x;

            DELETE dbo.tblIdCancellati WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblIdLog        WHERE Id IN (SELECT Id FROM #IdDaRipulire);
            DELETE dbo.tblId           WHERE Id IN (SELECT Id FROM #IdDaRipulire);

        COMMIT TRANSACTION;

        SET @returnMessage = CONCAT('Cancellazione completata. Sedi rimosse: ', @totaleSedi, '. Riferimenti esterni azzerati/rimossi su Etichette/Autorizzazioni condivise: ', @rifEsterniRimossi, '.');

        SELECT @returnValue AS ReturnValue, @returnMessage AS ReturnMessage;
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
