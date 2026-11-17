/*
	Deploy produzione - 2026-11-17 - Rentri > Importazione: importazione delle registrazioni trasmesse a RENTRI da
	altri gestionali (app 4.0, commit 215bd46 + 9fe307b)

	Solo 4_0_ecomatico (DB comune a 40-demo e produzione). Richiede prima, sul DB 1_0_rentri dell'hub,
	deploy_produzione_2026-11-17_importazione_rentri.sql (repo 1_0_rentri) e l'hub con le letture.
	Solo oggetti nuovi: nessuna tabella o SP esistente cambia. Rieseguibile (tabelle create solo se mancano, menu
	inserito solo se manca, SP con CREATE OR ALTER). Eseguire con sqlcmd -f 65001 -I (oppure da SSMS).

	1. Tabelle dell'area temporanea: tblRentriImportazioni, _Movimenti, _Causali, _Anomalie, _Relazioni, _Soggetti,
	   _MovimentiSoggetti.
	2. Voce di menu Rentri > Importazione (tblPagine RIM, funzione RNT; tblMenu AG6 sotto AG0).
	3. SP uspRentriImportazioni_upd_Analisi, _ins, _get, _get_Movimenti_List, _get_Anomalie_List,
	   _get_Relazioni_List, _upd_Relazione, _get_Soggetti_List, _get_Abbinamenti_SelectList, _upd_Soggetto, _esegui,
	   _del.
*/

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ===== 1. tblRentriImportazioni (saltata se esiste già)
IF OBJECT_ID(N'dbo.tblRentriImportazioni', N'U') IS NOT NULL
	SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioni](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdRegistro] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdUtente] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[DalAnno] [smallint] NOT NULL,
	[DalNumero] [int] NOT NULL,
	[AlAnno] [smallint] NOT NULL,
	[AlNumero] [int] NOT NULL,
	[Stato] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[FinoAlPrimoProblema] [bit] NULL,
	[DataCreazione] [datetime2](0) NOT NULL,
	[DataAnalisi] [datetime2](0) NULL,
	[DataEsecuzione] [datetime2](0) NULL,
	[Modalita] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRentriImportazioni] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RentriImportazioni_IdRegistro_Stato] ON [dbo].[tblRentriImportazioni]
(
	[IdRegistro] ASC,
	[Stato] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriImportazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioni_tblRifiutiRegistri] FOREIGN KEY([IdRegistro])
REFERENCES [dbo].[tblRifiutiRegistri] ([Id])
GO

ALTER TABLE [dbo].[tblRentriImportazioni] CHECK CONSTRAINT [FK_tblRentriImportazioni_tblRifiutiRegistri]
GO

ALTER TABLE [dbo].[tblRentriImportazioni]  WITH CHECK ADD  CONSTRAINT [CK_tblRentriImportazioni_Modalita] CHECK  (([Modalita]='F' OR [Modalita]='I'))
GO

ALTER TABLE [dbo].[tblRentriImportazioni] CHECK CONSTRAINT [CK_tblRentriImportazioni_Modalita]
GO

ALTER TABLE [dbo].[tblRentriImportazioni]  WITH CHECK ADD  CONSTRAINT [CK_tblRentriImportazioni_Stato] CHECK  (([Stato]='P' OR [Stato]='E'))
GO

ALTER TABLE [dbo].[tblRentriImportazioni] CHECK CONSTRAINT [CK_tblRentriImportazioni_Stato]
GO

GO
PRINT 'tblRentriImportazioni creata';
GO
SET NOEXEC OFF;
GO

-- ===== 1. tblRentriImportazioniMovimenti (saltata se esiste già)
IF OBJECT_ID(N'dbo.tblRentriImportazioniMovimenti', N'U') IS NOT NULL
	SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioniMovimenti](
	[IdImportazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Anno] [smallint] NOT NULL,
	[Progressivo] [int] NOT NULL,
	[Identificativo] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[IsIntervallo] [bit] NOT NULL,
	[Json] [nvarchar](max) COLLATE Latin1_General_CI_AS NOT NULL,
	[JsonDettaglio] [nvarchar](max) COLLATE Latin1_General_CI_AS NULL,
	[JsonValori] [nvarchar](max) COLLATE Latin1_General_CI_AS NULL,
	[Tipo] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[RettificaAnno] [smallint] NULL,
	[RettificaProgressivo] [int] NULL,
	[Data] [date] NULL,
	[DataOra] [datetime2](0) NULL,
	[DataTrasmissione] [datetime2](0) NULL,
	[Causale] [varchar](5) COLLATE Latin1_General_CI_AS NULL,
	[IdOperazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[Eer] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[StatoFisico] [varchar](5) COLLATE Latin1_General_CI_AS NULL,
	[Quantita] [decimal](18, 4) NULL,
	[UnitaMisura] [varchar](5) COLLATE Latin1_General_CI_AS NULL,
	[IsAnnullato] [bit] NULL,
	[IsRettificato] [bit] NULL,
	[Azione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdRegistrazione] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdEer] [char](6) COLLATE Latin1_General_CI_AS NULL,
	[IdMateriale] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[IdStatoFisico] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[IdUnitaMisura] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[JsonFormulario] [nvarchar](max) COLLATE Latin1_General_CI_AS NULL,
	[FormularioStato] [char](1) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblRentriImportazioniMovimenti] PRIMARY KEY CLUSTERED 
(
	[IdImportazione] ASC,
	[Anno] ASC,
	[Progressivo] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriImportazioniMovimenti]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniMovimenti_tblRentriImportazioni] FOREIGN KEY([IdImportazione])
REFERENCES [dbo].[tblRentriImportazioni] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblRentriImportazioniMovimenti] CHECK CONSTRAINT [FK_tblRentriImportazioniMovimenti_tblRentriImportazioni]
GO

GO
PRINT 'tblRentriImportazioniMovimenti creata';
GO
SET NOEXEC OFF;
GO

-- ===== 1. tblRentriImportazioniCausali (saltata se esiste già)
IF OBJECT_ID(N'dbo.tblRentriImportazioniCausali', N'U') IS NOT NULL
	SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioniCausali](
	[IdImportazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Causale] [varchar](5) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdOperazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblRentriImportazioniCausali] PRIMARY KEY CLUSTERED 
(
	[IdImportazione] ASC,
	[Causale] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriImportazioniCausali]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniCausali_tblRentriImportazioni] FOREIGN KEY([IdImportazione])
REFERENCES [dbo].[tblRentriImportazioni] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblRentriImportazioniCausali] CHECK CONSTRAINT [FK_tblRentriImportazioniCausali_tblRentriImportazioni]
GO

ALTER TABLE [dbo].[tblRentriImportazioniCausali]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniCausali_tblRifiutiOperazioni] FOREIGN KEY([IdOperazione])
REFERENCES [dbo].[tblRifiutiOperazioni] ([Id])
GO

ALTER TABLE [dbo].[tblRentriImportazioniCausali] CHECK CONSTRAINT [FK_tblRentriImportazioniCausali_tblRifiutiOperazioni]
GO

GO
PRINT 'tblRentriImportazioniCausali creata';
GO
SET NOEXEC OFF;
GO

-- ===== 1. tblRentriImportazioniAnomalie (saltata se esiste già)
IF OBJECT_ID(N'dbo.tblRentriImportazioniAnomalie', N'U') IS NOT NULL
	SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioniAnomalie](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[IdImportazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Anno] [smallint] NULL,
	[Progressivo] [int] NULL,
	[Livello] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[Codice] [varchar](30) COLLATE Latin1_General_CI_AS NOT NULL,
	[Messaggio] [nvarchar](400) COLLATE Latin1_General_CI_AS NOT NULL,
 CONSTRAINT [PK_tblRentriImportazioniAnomalie] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE NONCLUSTERED INDEX [IX_RentriImportazioniAnomalie_IdImportazione] ON [dbo].[tblRentriImportazioniAnomalie]
(
	[IdImportazione] ASC,
	[Anno] ASC,
	[Progressivo] ASC
)
INCLUDE([Livello]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriImportazioniAnomalie]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniAnomalie_tblRentriImportazioni] FOREIGN KEY([IdImportazione])
REFERENCES [dbo].[tblRentriImportazioni] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblRentriImportazioniAnomalie] CHECK CONSTRAINT [FK_tblRentriImportazioniAnomalie_tblRentriImportazioni]
GO

ALTER TABLE [dbo].[tblRentriImportazioniAnomalie]  WITH CHECK ADD  CONSTRAINT [CK_tblRentriImportazioniAnomalie_Livello] CHECK  (([Livello]='E' OR [Livello]='W' OR [Livello]='I'))
GO

ALTER TABLE [dbo].[tblRentriImportazioniAnomalie] CHECK CONSTRAINT [CK_tblRentriImportazioniAnomalie_Livello]
GO

GO
PRINT 'tblRentriImportazioniAnomalie creata';
GO
SET NOEXEC OFF;
GO

-- ===== 1. tblRentriImportazioniRelazioni (saltata se esiste già)
IF OBJECT_ID(N'dbo.tblRentriImportazioniRelazioni', N'U') IS NOT NULL
	SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioniRelazioni](
	[IdImportazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[PadreAnno] [smallint] NOT NULL,
	[PadreProgressivo] [int] NOT NULL,
	[FiglioAnno] [smallint] NOT NULL,
	[FiglioProgressivo] [int] NOT NULL,
	[FiglioIdentificativo] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[IdRegistrazioneFiglio] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Pos] [int] NOT NULL,
	[Operazione] [char](1) COLLATE Latin1_General_CI_AS NULL,
	[DisponibilePrima] [decimal](18, 4) NULL,
	[QuantitaProposta] [decimal](18, 4) NULL,
	[Quantita] [decimal](18, 4) NULL,
	[IsModificata] [bit] NOT NULL,
 CONSTRAINT [PK_tblRentriImportazioniRelazioni] PRIMARY KEY CLUSTERED 
(
	[IdImportazione] ASC,
	[PadreAnno] ASC,
	[PadreProgressivo] ASC,
	[FiglioAnno] ASC,
	[FiglioProgressivo] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriImportazioniRelazioni]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniRelazioni_tblRentriImportazioni] FOREIGN KEY([IdImportazione])
REFERENCES [dbo].[tblRentriImportazioni] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblRentriImportazioniRelazioni] CHECK CONSTRAINT [FK_tblRentriImportazioniRelazioni_tblRentriImportazioni]
GO

GO
PRINT 'tblRentriImportazioniRelazioni creata';
GO
SET NOEXEC OFF;
GO

-- ===== 1. tblRentriImportazioniSoggetti (saltata se esiste già)
IF OBJECT_ID(N'dbo.tblRentriImportazioniSoggetti', N'U') IS NOT NULL
	SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioniSoggetti](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[IdImportazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Ruolo] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[CodiceFiscale] [varchar](20) COLLATE Latin1_General_CI_AS NOT NULL,
	[Numero] [varchar](50) COLLATE Latin1_General_CI_AS NOT NULL,
	[Denominazione] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	[NazioneId] [varchar](5) COLLATE Latin1_General_CI_AS NULL,
	[IndirizzoJson] [nvarchar](1000) COLLATE Latin1_General_CI_AS NULL,
	[Stato] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdAutorizzazione] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IdSede] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[IsModificato] [bit] NOT NULL,
	[PartitaIva] [varchar](20) COLLATE Latin1_General_CI_AS NULL,
	[IdNazione] [char](3) COLLATE Latin1_General_CI_AS NULL,
	[IdComune] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Localita] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[CAP] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[Indirizzo] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[NumeroCivico] [varchar](10) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
 CONSTRAINT [PK_tblRentriImportazioniSoggetti] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING ON

GO

CREATE UNIQUE NONCLUSTERED INDEX [IX_RentriImportazioniSoggetti_Chiave] ON [dbo].[tblRentriImportazioniSoggetti]
(
	[IdImportazione] ASC,
	[Ruolo] ASC,
	[CodiceFiscale] ASC,
	[Numero] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriImportazioniSoggetti]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniSoggetti_tblRentriImportazioni] FOREIGN KEY([IdImportazione])
REFERENCES [dbo].[tblRentriImportazioni] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblRentriImportazioniSoggetti] CHECK CONSTRAINT [FK_tblRentriImportazioniSoggetti_tblRentriImportazioni]
GO

ALTER TABLE [dbo].[tblRentriImportazioniSoggetti]  WITH CHECK ADD  CONSTRAINT [CK_tblRentriImportazioniSoggetti_Stato] CHECK  (([Stato]='A' OR [Stato]='N' OR [Stato]='M' OR [Stato]='U' OR [Stato]='C'))
GO

ALTER TABLE [dbo].[tblRentriImportazioniSoggetti] CHECK CONSTRAINT [CK_tblRentriImportazioniSoggetti_Stato]
GO

GO
PRINT 'tblRentriImportazioniSoggetti creata';
GO
SET NOEXEC OFF;
GO

-- ===== 1. tblRentriImportazioniMovimentiSoggetti (saltata se esiste già)
IF OBJECT_ID(N'dbo.tblRentriImportazioniMovimentiSoggetti', N'U') IS NOT NULL
	SET NOEXEC ON;
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblRentriImportazioniMovimentiSoggetti](
	[IdImportazione] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Anno] [smallint] NOT NULL,
	[Progressivo] [int] NOT NULL,
	[Ruolo] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[Pos] [tinyint] NOT NULL,
	[IdSoggetto] [int] NOT NULL,
 CONSTRAINT [PK_tblRentriImportazioniMovimentiSoggetti] PRIMARY KEY CLUSTERED 
(
	[IdImportazione] ASC,
	[Anno] ASC,
	[Progressivo] ASC,
	[Ruolo] ASC,
	[Pos] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblRentriImportazioniMovimentiSoggetti]  WITH CHECK ADD  CONSTRAINT [FK_tblRentriImportazioniMovimentiSoggetti_tblRentriImportazioni] FOREIGN KEY([IdImportazione])
REFERENCES [dbo].[tblRentriImportazioni] ([Id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[tblRentriImportazioniMovimentiSoggetti] CHECK CONSTRAINT [FK_tblRentriImportazioniMovimentiSoggetti_tblRentriImportazioni]
GO

GO
PRINT 'tblRentriImportazioniMovimentiSoggetti creata';
GO
SET NOEXEC OFF;
GO

-- ===== 2. Voce di menu
-- Voce di menu Rentri > Importazione, sotto la funzione RNT (configurazione RENTRI, solo amministratori)
IF NOT EXISTS (SELECT 1 FROM dbo.tblPagine WHERE Id = 'RIM')
	INSERT dbo.tblPagine (Id, IdFunzione, Nome, Url, Note, IdModulo)
	VALUES ('RIM', 'RNT', 'Importazione', NULL, NULL, NULL);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.tblMenu WHERE Id = 'AG6')
	INSERT dbo.tblMenu (Id, IdParent, IdArea, IdPagina, Pos)
	VALUES ('AG6', 'AG0', NULL, 'RIM', 5);
GO

-- ===== 3. uspRentriImportazioni_upd_Analisi
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: analisi dei movimenti letti da RENTRI (area temporanea) rispetto al registro di
-- destinazione. Si può rilanciare a piacere finché l'importazione non è eseguita: ricalcola da zero i campi
-- letti dai JSON, l'azione di ogni movimento e le anomalie. I JSON originali (Json, JsonDettaglio) non si toccano.
--
-- Come RENTRI rappresenta le rettifiche (verificato sulla sandbox il 2026-11-14): la registrazione di rettifica o
-- di annullamento porta solo i propri riferimenti (numero, data, numero_registrazione_rettifica = originale), mai i
-- valori. I valori stanno negli stati dell'originale (dettaglio: stato corrente + array variazioni): ogni stato
-- indica con numero_registrazione_di_rettifica la rettifica che l'ha prodotto; lo stato senza quel riferimento è
-- quello trasmesso in origine; lo stato prodotto da un annullamento ha annullato = true e le annotazioni.
--
-- Valori da importare (JsonValori), mai lo stato corrente rettificato al posto dell'originale:
--   - movimento mai rettificato né annullato: il movimento stesso;
--   - originale rettificato o annullato: lo stato senza numero_registrazione_di_rettifica; per un originale solo
--     annullato, se il dettaglio non c'è, il movimento stesso (l'annullamento non cambia i valori);
--   - rettifica o annullamento: lo stato dell'originale prodotto da questa rettifica.
-- Numero, data e data di trasmissione sono sempre quelli del movimento stesso (Json).
--
-- Tipo: M movimento, R rettifica di correzione, A annullamento (stato prodotto con annullato = true).
-- Azione: I da importare, P già presente in Ecomatico (stesso identificativo RENTRI nel registro), X esclusa per
-- un'anomalia bloccante. Anomalie: E bloccante, W avviso, I informazione.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_upd_Analisi]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		DECLARE @idRegistro CHAR(16), @stato CHAR(1), @dalAnno SMALLINT, @dalNumero INT;
		SELECT
			@idRegistro = m.IdRegistro,
			@stato = m.Stato,
			@dalAnno = m.DalAnno,
			@dalNumero = m.DalNumero
		FROM
			dbo.tblRentriImportazioni m
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE m.Id = @Id;

		IF @idRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Importazione non trovata';
			GOTO BRANCH_END;
		END
		IF @stato <> 'P'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importazione è già stata eseguita';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			-- Blocca la riga dell'importazione: due analisi contemporanee si mettono in fila
			UPDATE dbo.tblRentriImportazioni WITH (UPDLOCK, HOLDLOCK)
			SET DataAnalisi = SYSDATETIME()
			WHERE Id = @Id;

			-- ── 1. Riferimenti del movimento stesso (numero, data, trasmissione, originale rettificato) ──
			-- La data di registrazione è quella italiana; se cambia anno rispetto alla numerazione (registrazione
			-- vicino alla mezzanotte del 31 dicembre) si usa la data UTC, con cui RENTRI ha numerato
			UPDATE m
			SET
				RettificaAnno = j.RettificaAnno,
				RettificaProgressivo = j.RettificaProgressivo,
				Tipo = IIF(j.RettificaProgressivo IS NULL, 'M', 'R'),
				DataOra = d.DataOraLocale,
				Data = IIF(YEAR(d.DataOraLocale) <> m.Anno AND YEAR(d.DataOraUtc) = m.Anno, CAST(d.DataOraUtc AS DATE), CAST(d.DataOraLocale AS DATE)),
				DataTrasmissione = CONVERT(DATETIME2(0), TRY_CONVERT(DATETIMEOFFSET(0), j.DataTrasmissione) AT TIME ZONE 'W. Europe Standard Time'),
				IsAnnullato = ISNULL(j.Annullato, 0),
				IsRettificato = ISNULL(j.Rettificato, 0),
				JsonValori = NULL
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY OPENJSON(m.Json)
				WITH (
					RettificaAnno SMALLINT '$.riferimenti.numero_registrazione_rettifica.anno',
					RettificaProgressivo INT '$.riferimenti.numero_registrazione_rettifica.progressivo',
					DataOra VARCHAR(40) '$.riferimenti.data_ora_registrazione',
					DataTrasmissione VARCHAR(40) '$.riferimenti.data_trasmissione',
					Annullato BIT '$.annullato',
					Rettificato BIT '$.rettificato'
				) j
				CROSS APPLY (
					SELECT
						DataOraUtc = CONVERT(DATETIME2(0), TRY_CONVERT(DATETIMEOFFSET(0), j.DataOra)),
						DataOraLocale = CONVERT(DATETIME2(0), TRY_CONVERT(DATETIMEOFFSET(0), j.DataOra) AT TIME ZONE 'W. Europe Standard Time')
				) d
			WHERE m.IdImportazione = @Id;

			-- Stati degli originali letti con il dettaglio: stato corrente e variazioni
			SELECT
				m.Anno, m.Progressivo,
				DiRettificaAnno = TRY_CAST(JSON_VALUE(s.Json, '$.riferimenti.numero_registrazione_di_rettifica.anno') AS SMALLINT),
				DiRettificaProgressivo = TRY_CAST(JSON_VALUE(s.Json, '$.riferimenti.numero_registrazione_di_rettifica.progressivo') AS INT),
				IsAnnullato = IIF(JSON_VALUE(s.Json, '$.annullato') = 'true', 1, 0),
				s.Json
			INTO #stati
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY (
					SELECT m.JsonDettaglio AS Json
					UNION ALL
					SELECT v.value
					FROM OPENJSON(m.JsonDettaglio, '$.variazioni') v
					WHERE v.type = 5
				) s
			WHERE
				m.IdImportazione = @Id
				AND m.JsonDettaglio IS NOT NULL;

			-- ── 2. Valori da importare ────────────────────────────────────────────────────────────
			-- Movimento: trasmesso in origine (stato senza rettifica)
			UPDATE m
			SET JsonValori =
				CASE
					WHEN m.IsRettificato = 0 AND m.IsAnnullato = 0 THEN m.Json
					ELSE ISNULL(o.Json, IIF(m.IsRettificato = 0 AND m.JsonDettaglio IS NULL, m.Json, NULL))
				END
			FROM
				dbo.tblRentriImportazioniMovimenti m
				OUTER APPLY (
					SELECT TOP 1 s.Json
					FROM #stati s
					WHERE s.Anno = m.Anno AND s.Progressivo = m.Progressivo AND s.DiRettificaProgressivo IS NULL
				) o
			WHERE
				m.IdImportazione = @Id
				AND m.Tipo = 'M';

			-- Rettifica o annullamento: stato dell'originale prodotto da questa registrazione
			UPDATE m
			SET
				JsonValori = o.Json,
				Tipo = IIF(o.IsAnnullato = 1, 'A', 'R')
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY (
					SELECT TOP 1 s.Json, s.IsAnnullato
					FROM #stati s
					WHERE
						s.Anno = m.RettificaAnno AND s.Progressivo = m.RettificaProgressivo
						AND s.DiRettificaAnno = m.Anno AND s.DiRettificaProgressivo = m.Progressivo
				) o
			WHERE
				m.IdImportazione = @Id
				AND m.Tipo = 'R';

			-- ── 3. Causale e dati del rifiuto o del materiale dai valori da importare ─────────────
			UPDATE m
			SET
				-- RENTRI valorizza stoccaggio_istantaneo con la data fittizia 0001-01-01 anche quando non c'è
				Causale = IIF(j.Causale IS NULL AND TRY_CONVERT(DATETIMEOFFSET(0), j.StoccaggioIstantaneo) > '19000101', 'SI', j.Causale),
				Eer = COALESCE(j.Eer, j.Materiale),
				StatoFisico = j.StatoFisico,
				Quantita = TRY_CONVERT(DECIMAL(18, 4), COALESCE(j.Quantita, j.MaterialeQuantita)),
				UnitaMisura = COALESCE(j.UnitaMisura, j.MaterialeUnitaMisura)
			FROM
				dbo.tblRentriImportazioniMovimenti m
				OUTER APPLY OPENJSON(m.JsonValori)
				WITH (
					Causale VARCHAR(5) '$.riferimenti.causale_operazione',
					StoccaggioIstantaneo VARCHAR(40) '$.riferimenti.stoccaggio_istantaneo',
					Eer VARCHAR(10) '$.rifiuto.codice_eer',
					StatoFisico VARCHAR(5) '$.rifiuto.stato_fisico',
					Quantita VARCHAR(40) '$.rifiuto.quantita.valore',
					UnitaMisura VARCHAR(5) '$.rifiuto.quantita.unita_misura',
					Materiale VARCHAR(10) '$.materiali.materiale',
					MaterialeQuantita VARCHAR(40) '$.materiali.quantita.valore',
					MaterialeUnitaMisura VARCHAR(5) '$.materiali.quantita.unita_misura'
				) j
			WHERE m.IdImportazione = @Id;

			-- Codici di Ecomatico (tabelle di decodifica, colonna Codice; l'EER ha come Id il codice stesso)
			UPDATE m
			SET
				IdEer = IIF(x.IsMateriale = 0, (SELECT TOP 1 e.Id FROM dbo.tblRifiutiEer e WHERE e.Id = m.Eer), NULL),
				IdMateriale = IIF(x.IsMateriale = 1, (SELECT TOP 1 t.Id FROM dbo.tblRifiutiMateriali t WHERE t.Codice = m.Eer), NULL),
				IdStatoFisico = (SELECT TOP 1 s.Id FROM dbo.tblRifiutiStatiFisici s WHERE s.Codice = m.StatoFisico),
				IdUnitaMisura = (SELECT TOP 1 u.Id FROM dbo.tblUnitaMisura u WHERE u.Codice = m.UnitaMisura)
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY (SELECT IsMateriale = IIF(JSON_QUERY(m.JsonValori, '$.materiali') IS NOT NULL, 1, 0)) x
			WHERE m.IdImportazione = @Id;

			-- ── 4. Causali RENTRI -> operazioni Ecomatico ─────────────────────────────────────────
			-- Proposta: l'operazione con lo stesso codice RENTRI, esclusa quella del formulario unico degli
			-- spurghisti (si vidima su Vi.Vi.FIR, non arriva dal registro). La scelta dell'utente resta.
			INSERT dbo.tblRentriImportazioniCausali (IdImportazione, Causale, IdOperazione)
			SELECT
				@Id,
				c.Causale,
				(
					SELECT TOP 1 o.Id
					FROM dbo.tblRifiutiOperazioni o
					WHERE
						o.Codice = c.Causale
						AND ISNULL(o.IsRentri, 0) = 1
						AND ISNULL(o.IsFormularioUnico, 0) = 0
					ORDER BY o.Pos
				)
			FROM (
				SELECT DISTINCT m.Causale
				FROM dbo.tblRentriImportazioniMovimenti m
				WHERE m.IdImportazione = @Id AND m.Causale IS NOT NULL
			) c
			WHERE NOT EXISTS (
				SELECT 1
				FROM dbo.tblRentriImportazioniCausali x
				WHERE x.IdImportazione = @Id AND x.Causale = c.Causale);

			UPDATE m
			SET IdOperazione = c.IdOperazione
			FROM
				dbo.tblRentriImportazioniMovimenti m
				LEFT JOIN dbo.tblRentriImportazioniCausali c ON c.IdImportazione = m.IdImportazione AND c.Causale = m.Causale
			WHERE m.IdImportazione = @Id;

			-- ── 5. Registrazioni del registro già in Ecomatico ────────────────────────────────────
			-- Valori di lettura: numero, anno (anno della data) e identificativo RENTRI delle registrazioni attive
			SELECT
				r.Id, r.Numero, YEAR(r.Data) AS Anno, r.Data, r.RentriIdentificativo
			INTO #registro
			FROM
				dbo.tblRifiutiRegistrazioni r
				INNER JOIN dbo.tblRifiutiMovimenti v ON r.IdMovimento = v.Id
			WHERE
				v.IdRegistro = @idRegistro
				AND r.Lock < 2;

			UPDATE m
			SET
				IdRegistrazione = x.Id,
				Azione = NULL
			FROM
				dbo.tblRentriImportazioniMovimenti m
				OUTER APPLY (
					SELECT TOP 1 g.Id
					FROM #registro g
					WHERE g.RentriIdentificativo = m.Identificativo
				) x
			WHERE m.IdImportazione = @Id;

			-- ── 6. Anomalie ───────────────────────────────────────────────────────────────────────
			DELETE dbo.tblRentriImportazioniAnomalie
			WHERE IdImportazione = @Id;

			-- Già presente in Ecomatico con lo stesso identificativo RENTRI: non si importa di nuovo
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo,
				IIF(g.Numero = m.Progressivo AND g.Anno = m.Anno, 'I', 'W'),
				'GIA_PRESENTE',
				IIF(g.Numero = m.Progressivo AND g.Anno = m.Anno,
					'Già presente in Ecomatico: non viene importata di nuovo',
					CONCAT('Già presente in Ecomatico con il numero ', g.Numero, '/', g.Anno, ' invece di ', m.Progressivo, '/', m.Anno, ': non viene importata di nuovo'))
			FROM
				dbo.tblRentriImportazioniMovimenti m
				INNER JOIN #registro g ON m.IdRegistrazione = g.Id
			WHERE m.IdImportazione = @Id;

			-- Stesso identificativo RENTRI su un altro registro
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT DISTINCT
				@Id, m.Anno, m.Progressivo, 'E', 'ALTRO_REGISTRO',
				'La registrazione è già presente in Ecomatico in un altro registro'
			FROM
				dbo.tblRentriImportazioniMovimenti m
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON r.RentriIdentificativo = m.Identificativo AND r.Lock < 2
				INNER JOIN dbo.tblRifiutiMovimenti v ON r.IdMovimento = v.Id
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND v.IdRegistro <> @idRegistro;

			-- Numero già usato nel registro da un'altra registrazione
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'NUMERO_OCCUPATO',
				CONCAT('Il numero ', m.Progressivo, '/', m.Anno, ' è già usato in Ecomatico dalla registrazione del ', FORMAT(g.Data, 'dd/MM/yyyy'),
					IIF(g.RentriIdentificativo IS NULL, ', non inviata al RENTRI', ', inviata al RENTRI con un altro identificativo'))
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY (
					SELECT TOP 1 x.Data, x.RentriIdentificativo
					FROM #registro x
					WHERE
						x.Anno = m.Anno
						AND x.Numero = m.Progressivo
						AND (m.IdRegistrazione IS NULL OR x.Id <> m.IdRegistrazione)
					ORDER BY x.Data
				) g
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL;

			-- Data di registrazione non leggibile
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT @Id, m.Anno, m.Progressivo, 'E', 'DATA', 'La data di registrazione restituita da RENTRI non è valida'
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND (m.Data IS NULL OR YEAR(m.Data) <> m.Anno);

			-- Numerazione non coerente con le date delle registrazioni già nel registro (stessa regola del salvataggio)
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'DATA_INCOERENTE',
				CONCAT('La data ', FORMAT(m.Data, 'dd/MM/yyyy'), ' non è coerente con la registrazione n. ', g.Numero, '/', g.Anno,
					' del ', FORMAT(g.Data, 'dd/MM/yyyy'), ' già presente in Ecomatico')
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY (
					SELECT TOP 1 x.Numero, x.Anno, x.Data
					FROM #registro x
					WHERE
						x.Anno = m.Anno
						AND ((x.Numero < m.Progressivo AND x.Data > m.Data) OR (x.Numero > m.Progressivo AND x.Data < m.Data))
						AND NOT EXISTS (
							SELECT 1
							FROM dbo.tblRentriImportazioniMovimenti y
							WHERE y.IdImportazione = @Id AND y.IdRegistrazione = x.Id)
					ORDER BY ABS(x.Numero - m.Progressivo)
				) g
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Data IS NOT NULL;

			-- Causale non riconosciuta
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'CAUSALE',
				IIF(m.Causale IS NULL, 'Causale RENTRI mancante', CONCAT('Nessuna operazione di Ecomatico corrisponde alla causale RENTRI "', m.Causale, '"'))
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Tipo = 'M'
				AND m.IdOperazione IS NULL;

			-- Valori non disponibili: trasmessi in origine (originale rettificato) o della rettifica (stato
			-- dell'originale che la rettifica ha prodotto); originale assente = ORIGINALE_MANCANTE
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'VALORI_ORIGINALI',
				IIF(m.Tipo = 'M',
					'RENTRI non ha restituito i valori trasmessi in origine di questa registrazione rettificata',
					CONCAT('RENTRI non ha restituito i valori di questa rettifica nella storia della registrazione n. ', m.RettificaProgressivo, '/', m.RettificaAnno))
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.JsonValori IS NULL
				AND (
					m.Tipo = 'M'
					OR EXISTS (
						SELECT 1
						FROM dbo.tblRentriImportazioniMovimenti o
						WHERE o.IdImportazione = @Id AND o.Anno = m.RettificaAnno AND o.Progressivo = m.RettificaProgressivo));

			-- Dati del rifiuto o del materiale mancanti
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'DATI_RIFIUTO',
				'Codice EER (o materiale), quantità o unità di misura mancanti'
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.JsonValori IS NOT NULL
				AND m.Tipo IN ('M', 'R')
				AND (m.Eer IS NULL OR m.Quantita IS NULL OR m.UnitaMisura IS NULL);

			-- Codici RENTRI senza corrispondenza nelle tabelle di Ecomatico
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'CODICI',
				CONCAT('Codici RENTRI non presenti in Ecomatico:',
					IIF(m.IdEer IS NULL AND m.IdMateriale IS NULL, CONCAT(' ', IIF(JSON_QUERY(m.JsonValori, '$.materiali') IS NULL, 'EER ', 'materiale '), m.Eer), ''),
					IIF(m.StatoFisico IS NOT NULL AND m.IdStatoFisico IS NULL, CONCAT(' stato fisico ', m.StatoFisico), ''),
					IIF(m.IdUnitaMisura IS NULL, CONCAT(' unità di misura ', m.UnitaMisura), ''))
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Tipo IN ('M', 'R')
				AND m.Eer IS NOT NULL AND m.UnitaMisura IS NOT NULL
				AND (
					(m.IdEer IS NULL AND m.IdMateriale IS NULL)
					OR (m.StatoFisico IS NOT NULL AND m.IdStatoFisico IS NULL)
					OR m.IdUnitaMisura IS NULL);

			-- Testi più lunghi delle colonne di Ecomatico: non si troncano
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'LUNGHEZZA',
				CONCAT('Testo più lungo di quanto Ecomatico può memorizzare: ', STUFF(CONCAT(
					IIF(LEN(j.NumeroFir) > 20, ', numero del formulario', ''),
					IIF(LEN(j.CausaleAltro) > 100, ', causale di respingimento', ''),
					IIF(LEN(j.DescrizioneMateriale) > 200, ', descrizione del materiale', ''),
					IIF(LEN(j.DescrizioneEer) > 200, ', descrizione EER', ''),
					IIF(LEN(j.Annotazioni) > 500, ', annotazioni', ''),
					IIF(LEN(j.VeicoloNumero) > 50, ', numero del veicolo fuori uso', '')), 1, 2, ''))
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY OPENJSON(m.JsonValori)
				WITH (
					NumeroFir NVARCHAR(200) '$.integrazione_fir.numero_fir',
					CausaleAltro NVARCHAR(1000) '$.esito.respingimento.causale_altro',
					DescrizioneMateriale NVARCHAR(1000) '$.materiali.descrizione_materiale',
					DescrizioneEer NVARCHAR(1000) '$.rifiuto.descrizione_eer',
					Annotazioni NVARCHAR(2000) '$.annotazioni',
					VeicoloNumero NVARCHAR(200) '$.rifiuto.veicolo_fuori_uso_reg_pubblica_sicurezza.numero'
				) j
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.JsonValori IS NOT NULL
				AND (LEN(j.NumeroFir) > 20 OR LEN(j.CausaleAltro) > 100 OR LEN(j.DescrizioneMateriale) > 200 OR LEN(j.DescrizioneEer) > 200
					OR LEN(j.Annotazioni) > 500 OR LEN(j.VeicoloNumero) > 50);

			-- Più di 2 decimali: Ecomatico ne gestisce 2, la quantità non si arrotonda
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'DECIMALI',
				CONCAT('La quantità ', FORMAT(m.Quantita, '0.####', 'it-IT'), ' ha più di 2 decimali: Ecomatico ne gestisce 2 e non la arrotonda')
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Quantita <> ROUND(m.Quantita, 2);

			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'DECIMALI_ESITO',
				'Il peso verificato a destino o la quantità respinta hanno più di 2 decimali: Ecomatico ne gestisce 2 e non li arrotonda'
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY OPENJSON(m.JsonValori)
				WITH (
					PesoVerificato VARCHAR(40) '$.esito.peso_verificato_destino',
					QuantitaRespinta VARCHAR(40) '$.esito.respingimento.quantita.valore'
				) j
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.JsonValori IS NOT NULL
				AND (
					TRY_CONVERT(DECIMAL(18, 4), j.PesoVerificato) <> ROUND(TRY_CONVERT(DECIMAL(18, 4), j.PesoVerificato), 2)
					OR TRY_CONVERT(DECIMAL(18, 4), j.QuantitaRespinta) <> ROUND(TRY_CONVERT(DECIMAL(18, 4), j.QuantitaRespinta), 2));

			-- Rettifica o annullamento senza la registrazione originale (né letta da RENTRI né in Ecomatico)
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'E', 'ORIGINALE_MANCANTE',
				CONCAT(IIF(m.Tipo = 'A', 'Annullamento', 'Rettifica'), ' della registrazione n. ', m.RettificaProgressivo, '/', m.RettificaAnno,
					', che non è stata trovata né su RENTRI né in Ecomatico')
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Tipo IN ('R', 'A')
				AND NOT EXISTS (
					SELECT 1
					FROM dbo.tblRentriImportazioniMovimenti o
					WHERE o.IdImportazione = @Id AND o.Anno = m.RettificaAnno AND o.Progressivo = m.RettificaProgressivo)
				AND NOT EXISTS (
					SELECT 1
					FROM #registro g
					WHERE g.Anno = m.RettificaAnno AND g.Numero = m.RettificaProgressivo AND g.RentriIdentificativo IS NOT NULL);

			-- ── 6b. Soggetti (produttore, trasportatore, destinatario, intermediari) ─────────────
			-- Dai valori da importare, solo per i ruoli che l'operazione di Ecomatico prevede (IsProduttore,
			-- IsTrasportatore, IsDestinatario, IsIntermediario). Un soggetto per ruolo, codice fiscale e numero
			-- (iscrizione all'Albo o autorizzazione), condiviso da tutte le registrazioni che lo usano. Anche le rettifiche e gli
			-- annullamenti: in Ecomatico riportano i valori in vigore, soggetti compresi (R2.6).
			-- Trasportatore, destinatario e intermediari che la registrazione su RENTRI non riporta (altri gestionali
			-- trasmettono solo il numero del formulario) si prendono dal formulario digitale con quel numero, letto da
			-- RENTRI (FormularioStato D, JSON originale del formulario letto dall'hub): servono anche per il MUD.
			-- Formulari digitali letti da RENTRI, una riga per numero (letti una sola volta: con migliaia di registrazioni
			-- leggere il JSON a ogni confronto costa decine di secondi)
			SELECT Numero = CAST(JSON_VALUE(f.JsonFormulario, '$.dati_partenza.numero_fir') AS VARCHAR(50)), Json = MIN(f.JsonFormulario)
			INTO #fir
			FROM dbo.tblRentriImportazioniMovimenti f
			WHERE f.IdImportazione = @Id AND f.FormularioStato = 'D' AND JSON_VALUE(f.JsonFormulario, '$.dati_partenza.numero_fir') IS NOT NULL
			GROUP BY JSON_VALUE(f.JsonFormulario, '$.dati_partenza.numero_fir');
			CREATE UNIQUE CLUSTERED INDEX IX_fir ON #fir (Numero);

			-- Formulari non letti: N non digitale (cartaceo), X non leggibili con la credenziale del registro
			SELECT Numero = CAST(JSON_VALUE(f.Json, '$.integrazione_fir.numero_fir') AS VARCHAR(50)), Stato = MAX(f.FormularioStato)
			INTO #firNonLetti
			FROM dbo.tblRentriImportazioniMovimenti f
			WHERE f.IdImportazione = @Id AND f.FormularioStato IN ('N', 'X') AND JSON_VALUE(f.Json, '$.integrazione_fir.numero_fir') IS NOT NULL
			GROUP BY JSON_VALUE(f.Json, '$.integrazione_fir.numero_fir');

			SELECT
				m.Anno, m.Progressivo,
				s.Ruolo, s.Pos,
				CodiceFiscale = UPPER(LTRIM(RTRIM(s.CodiceFiscale))),
				Numero = ISNULL(UPPER(REPLACE(LTRIM(RTRIM(s.Numero)), ' ', '')), ''),
				Denominazione = LEFT(s.Denominazione, 200),
				s.NazioneId,
				s.IndirizzoJson
			INTO #ms
			FROM
				dbo.tblRentriImportazioniMovimenti m
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				LEFT JOIN #fir fir ON fir.Numero = CAST(JSON_VALUE(m.JsonValori, '$.integrazione_fir.numero_fir') AS VARCHAR(50))
				CROSS APPLY (
					SELECT 'P', 1, JSON_VALUE(m.JsonValori, '$.produttore.codice_fiscale'), NULL,
						JSON_VALUE(m.JsonValori, '$.produttore.denominazione'), JSON_VALUE(m.JsonValori, '$.produttore.nazione_id'),
						JSON_QUERY(m.JsonValori, '$.produttore.indirizzo')
					WHERE ISNULL(o.IsProduttore, 0) = 1
					UNION ALL
					SELECT 'T', 1, JSON_VALUE(m.JsonValori, '$.trasportatore.codice_fiscale'), JSON_VALUE(m.JsonValori, '$.trasportatore.num_iscrizione_albo'),
						JSON_VALUE(m.JsonValori, '$.trasportatore.denominazione'), JSON_VALUE(m.JsonValori, '$.trasportatore.nazione_id'), NULL
					WHERE ISNULL(o.IsTrasportatore, 0) = 1 AND JSON_QUERY(m.JsonValori, '$.trasportatore') IS NOT NULL
					UNION ALL
					SELECT 'T', 1, JSON_VALUE(fir.Json, '$.dati_partenza.trasportatori[0].codice_fiscale'), JSON_VALUE(fir.Json, '$.dati_partenza.trasportatori[0].numero_iscrizione_albo'),
						JSON_VALUE(fir.Json, '$.dati_partenza.trasportatori[0].denominazione'), JSON_VALUE(fir.Json, '$.dati_partenza.trasportatori[0].nazione_id'), NULL
					WHERE ISNULL(o.IsTrasportatore, 0) = 1 AND JSON_QUERY(m.JsonValori, '$.trasportatore') IS NULL AND fir.Json IS NOT NULL
					UNION ALL
					SELECT 'D', 1, JSON_VALUE(m.JsonValori, '$.destinatario.codice_fiscale'), JSON_VALUE(m.JsonValori, '$.destinatario.num_autorizzazione'),
						JSON_VALUE(m.JsonValori, '$.destinatario.denominazione'), JSON_VALUE(m.JsonValori, '$.destinatario.nazione_id'), NULL
					WHERE ISNULL(o.IsDestinatario, 0) = 1 AND JSON_QUERY(m.JsonValori, '$.destinatario') IS NOT NULL
					UNION ALL
					SELECT 'D', 1, JSON_VALUE(fir.Json, '$.dati_partenza.destinatario.codice_fiscale'), JSON_VALUE(fir.Json, '$.dati_partenza.destinatario.autorizzazione.numero'),
						JSON_VALUE(fir.Json, '$.dati_partenza.destinatario.denominazione'), JSON_VALUE(fir.Json, '$.dati_partenza.destinatario.nazione_id'),
						JSON_QUERY(fir.Json, '$.dati_partenza.destinatario.indirizzo')
					WHERE ISNULL(o.IsDestinatario, 0) = 1 AND JSON_QUERY(m.JsonValori, '$.destinatario') IS NULL AND fir.Json IS NOT NULL
					UNION ALL
					SELECT 'I', CAST(i.[key] AS INT) + 1, JSON_VALUE(i.value, '$.codice_fiscale'), JSON_VALUE(i.value, '$.num_iscrizione_albo'),
						JSON_VALUE(i.value, '$.denominazione'), JSON_VALUE(i.value, '$.nazione_id'), NULL
					FROM OPENJSON(m.JsonValori, '$.intermediari') i
					WHERE ISNULL(o.IsIntermediario, 0) = 1
					UNION ALL
					SELECT 'I', CAST(k.[key] AS INT) + 1, JSON_VALUE(k.value, '$.codice_fiscale'), JSON_VALUE(k.value, '$.numero_iscrizione_albo'),
						JSON_VALUE(k.value, '$.denominazione'), JSON_VALUE(k.value, '$.nazione_id'), NULL
					FROM OPENJSON(fir.Json, '$.dati_partenza.intermediari') k
					WHERE
						ISNULL(o.IsIntermediario, 0) = 1
						AND fir.Json IS NOT NULL
						AND ISNULL(JSON_QUERY(m.JsonValori, '$.intermediari'), '[]') = '[]'
						AND JSON_QUERY(m.JsonValori, '$.intermediario') IS NULL
				) s (Ruolo, Pos, CodiceFiscale, Numero, Denominazione, NazioneId, IndirizzoJson)
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Tipo IN ('M', 'R', 'A')
				AND m.JsonValori IS NOT NULL
				AND NULLIF(LTRIM(RTRIM(s.CodiceFiscale)), '') IS NOT NULL;

			-- Soggetti non più usati: via; nuovi: da abbinare
			DELETE x
			FROM dbo.tblRentriImportazioniSoggetti x
			WHERE
				x.IdImportazione = @Id
				AND NOT EXISTS (
					SELECT 1
					FROM #ms s
					WHERE s.Ruolo = x.Ruolo AND s.CodiceFiscale = x.CodiceFiscale AND s.Numero = x.Numero);

			INSERT dbo.tblRentriImportazioniSoggetti (IdImportazione, Ruolo, CodiceFiscale, Numero, Denominazione, NazioneId, IndirizzoJson, Stato, IsModificato)
			SELECT @Id, s.Ruolo, s.CodiceFiscale, s.Numero, MIN(s.Denominazione), MIN(s.NazioneId), MIN(s.IndirizzoJson), 'M', 0
			FROM #ms s
			WHERE NOT EXISTS (
				SELECT 1
				FROM dbo.tblRentriImportazioniSoggetti x
				WHERE x.IdImportazione = @Id AND x.Ruolo = s.Ruolo AND x.CodiceFiscale = s.CodiceFiscale AND x.Numero = s.Numero)
			GROUP BY s.Ruolo, s.CodiceFiscale, s.Numero;

			-- Sedi visibili all'azienda interna del registro (stesso calcolo di uspRifiutiAutorizzazioni_get_MatchImportazione)
			DECLARE @idAziendaInterna CHAR(16), @idUtente CHAR(16);
			SELECT @idAziendaInterna = s.IdAziendaInterna
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			WHERE g.Id = @idRegistro;
			SELECT @idUtente = IdUtente FROM dbo.tblSessioni WHERE Id = @IdSessione;

			SELECT s.Id, CodiceFiscale = UPPER(s.CodiceFiscale), PartitaIva = UPPER(s.PartitaIva)
			INTO #sedi
			FROM
				dbo.ufnSedi_get_SediByUtente_List(@idUtente) u
				INNER JOIN dbo.tblSedi s ON u.Id = s.Id
			WHERE
				u.Disabilitata = 0
				AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
				AND s.Disabilitata = 0
				AND s.Lock < 2;

			-- Abbinamento automatico (non tocca le scelte dell'utente, IsModificato):
			--   A  autorizzazione dello stesso ruolo con lo stesso numero, su una sede con quel codice fiscale (o
			--      partita IVA); senza numero (produttore), l'unica autorizzazione del ruolo su quelle sedi;
			--   N  nessuna autorizzazione ma una sola sede con quel codice fiscale: all'importazione le si aggiunge
			--      l'autorizzazione con il numero di RENTRI (per il produttore la "Nessuna");
			--   M  da completare: nessuna sede, oppure più sedi o autorizzazioni possibili (sceglie l'utente).
			UPDATE x
			SET
				Stato = CASE WHEN a.Conteggio = 1 THEN 'A' WHEN c.Conteggio = 1 THEN 'N' ELSE 'M' END,
				IdAutorizzazione = IIF(a.Conteggio = 1, a.Id, NULL),
				IdSede = IIF(a.Conteggio = 1, NULL, IIF(c.Conteggio = 1, c.Id, NULL)),
				-- Dati proposti per creare il soggetto (completati dall'utente nell'anteprima)
				Nome = LEFT(x.Denominazione, 50),
				IdNazione = ISNULL((SELECT TOP 1 n.Id FROM dbo.tblNazioni n WHERE n.Sigla = ISNULL(NULLIF(x.NazioneId, ''), 'IT')), '380'),
				PartitaIva = IIF(LEN(x.CodiceFiscale) = 11 AND x.CodiceFiscale NOT LIKE '%[^0-9]%', x.CodiceFiscale, NULL),
				IdComune = (SELECT TOP 1 k.Id FROM dbo.tblComuni k WHERE k.Id = JSON_VALUE(x.IndirizzoJson, '$.citta.comune_id')),
				Localita = LEFT(JSON_VALUE(x.IndirizzoJson, '$.citta.nome_citta'), 50),
				CAP = LEFT(NULLIF(JSON_VALUE(x.IndirizzoJson, '$.cap'), ''), 10),
				Indirizzo = LEFT(NULLIF(JSON_VALUE(x.IndirizzoJson, '$.indirizzo'), ''), 50),
				NumeroCivico = LEFT(NULLIF(JSON_VALUE(x.IndirizzoJson, '$.civico'), ''), 10)
			FROM
				dbo.tblRentriImportazioniSoggetti x
				OUTER APPLY (
					SELECT Conteggio = COUNT(DISTINCT z.Id), Id = MIN(z.Id)
					FROM
						dbo.tblRifiutiAutorizzazioni z
						INNER JOIN #sedi s ON z.IdSede = s.Id
					WHERE
						z.IdRuolo = x.Ruolo
						AND z.Disabilitata = 0
						AND z.Lock < 2
						AND (s.CodiceFiscale = x.CodiceFiscale OR s.PartitaIva = x.CodiceFiscale)
						AND (
							(x.Numero <> '' AND UPPER(REPLACE(z.Numero, ' ', '')) = x.Numero)
							OR (x.Numero = '' AND (x.Ruolo <> 'P' OR ISNULL(z.Nessuna, 0) = 1 OR z.Numero IS NULL)))
				) a
				OUTER APPLY (
					SELECT Conteggio = COUNT(*), Id = MIN(s.Id)
					FROM #sedi s
					WHERE s.CodiceFiscale = x.CodiceFiscale OR s.PartitaIva = x.CodiceFiscale
				) c
			WHERE
				x.IdImportazione = @Id
				AND x.IsModificato = 0;

			-- Scelte dell'utente non più valide (autorizzazione cancellata o non più visibile): di nuovo da completare
			UPDATE x
			SET Stato = 'M', IsModificato = 0, IdAutorizzazione = NULL, IdSede = NULL
			FROM dbo.tblRentriImportazioniSoggetti x
			WHERE
				x.IdImportazione = @Id
				AND x.Stato = 'U'
				AND NOT EXISTS (
					SELECT 1
					FROM
						dbo.tblRifiutiAutorizzazioni z
						INNER JOIN #sedi s ON z.IdSede = s.Id
					WHERE z.Id = x.IdAutorizzazione AND z.IdRuolo = x.Ruolo AND z.Disabilitata = 0 AND z.Lock < 2)
				AND NOT EXISTS (SELECT 1 FROM #sedi s WHERE x.IdAutorizzazione IS NULL AND s.Id = x.IdSede);

			DELETE dbo.tblRentriImportazioniMovimentiSoggetti
			WHERE IdImportazione = @Id;

			INSERT dbo.tblRentriImportazioniMovimentiSoggetti (IdImportazione, Anno, Progressivo, Ruolo, Pos, IdSoggetto)
			SELECT DISTINCT @Id, s.Anno, s.Progressivo, s.Ruolo, s.Pos, x.Id
			FROM
				#ms s
				INNER JOIN dbo.tblRentriImportazioniSoggetti x
					ON x.IdImportazione = @Id AND x.Ruolo = s.Ruolo AND x.CodiceFiscale = s.CodiceFiscale AND x.Numero = s.Numero;

			-- Soggetti presi dal formulario digitale, oppure assenti perché il formulario non è digitale
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo,
				IIF(fir.Numero IS NOT NULL, 'I', 'W'),
				'SOGGETTI_FORMULARIO',
				IIF(fir.Numero IS NOT NULL,
					CONCAT('Trasportatore e destinatario non sono nella registrazione su RENTRI: letti dal formulario digitale n. ', x.NumeroFir),
					IIF(fnl.Stato = 'X',
						CONCAT('Trasportatore e destinatario non sono nella registrazione su RENTRI e il formulario n. ', x.NumeroFir,
							' non si può leggere: la sede è collegata al RENTRI come delegato senza la credenziale da operatore (Rentri > Sedi, credenziale secondaria)'),
						CONCAT('Trasportatore e destinatario non sono nella registrazione su RENTRI e il formulario n. ', x.NumeroFir,
							' non è digitale: verrà importata senza, da completare a mano se servono (per esempio per il MUD)')))
			FROM
				dbo.tblRentriImportazioniMovimenti m
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
				CROSS APPLY (SELECT NumeroFir = CAST(JSON_VALUE(m.JsonValori, '$.integrazione_fir.numero_fir') AS VARCHAR(50))) x
				LEFT JOIN #fir fir ON fir.Numero = x.NumeroFir
				LEFT JOIN #firNonLetti fnl ON fnl.Numero = x.NumeroFir
			WHERE
				m.IdImportazione = @Id
				AND m.IdRegistrazione IS NULL
				AND m.Tipo IN ('M', 'R', 'A')
				AND x.NumeroFir IS NOT NULL
				AND (
					(ISNULL(o.IsTrasportatore, 0) = 1 AND JSON_QUERY(m.JsonValori, '$.trasportatore') IS NULL)
					OR (ISNULL(o.IsDestinatario, 0) = 1 AND JSON_QUERY(m.JsonValori, '$.destinatario') IS NULL));

			-- Soggetto da completare: bloccante per ogni registrazione che lo usa (mai un soggetto vuoto)
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, ms.Anno, ms.Progressivo, 'E', 'SOGGETTO',
				CONCAT(
					CASE x.Ruolo WHEN 'P' THEN 'Produttore' WHEN 'T' THEN 'Trasportatore' WHEN 'D' THEN 'Destinatario' ELSE 'Intermediario' END,
					' ', ISNULL(x.Denominazione, ''), ' (', x.CodiceFiscale, ') da abbinare o completare nella sezione Soggetti')
			FROM
				dbo.tblRentriImportazioniMovimentiSoggetti ms
				INNER JOIN dbo.tblRentriImportazioniSoggetti x ON ms.IdSoggetto = x.Id
			WHERE
				ms.IdImportazione = @Id
				AND x.Stato = 'M';

			-- ── 7. Azione e relazioni carico/scarico ─────────────────────────────────────────────
			UPDATE m
			SET Azione =
				CASE
					WHEN m.IdRegistrazione IS NOT NULL THEN 'P'
					WHEN EXISTS (
						SELECT 1
						FROM dbo.tblRentriImportazioniAnomalie a
						WHERE a.IdImportazione = @Id AND a.Anno = m.Anno AND a.Progressivo = m.Progressivo AND a.Livello = 'E') THEN 'X'
					ELSE 'I'
				END
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE m.IdImportazione = @Id;

			-- Riferimenti di RENTRI: ogni registrazione riporta le associate su entrambi i lati, con associazione_diretta
			-- = true sul lato di chi le ha scelte; nei dati più vecchi però il flag è true su tutti e due i lati
			-- (verificato sulla sandbox). Il verso si decide quindi così, per ogni coppia:
			--   1. le coppie ammesse da Ecomatico (tblRifiutiOperazioniRelazioni): se è ammesso un solo verso, vale quello;
			--   2. se sono ammessi tutti e due i versi (scarico R e carico M: consumo o derivazione), il padre è la
			--      registrazione successiva (data, poi anno e numero), perché il padre non precede mai il figlio;
			--   3. se non è ammesso nessun verso, o l'associata non è nell'area temporanea, vale associazione_diretta.
			-- Il padre (IdParent in Ecomatico) è lo scarico S/R che preleva dai carichi (consumo) o il carico K/M che
			-- deriva dallo scarico R (derivazione). Le rettifiche non hanno relazioni proprie (R2.7).
			SELECT
				AAnno = m.Anno,
				AProgressivo = m.Progressivo,
				BAnno = r.Anno,
				BProgressivo = r.Progressivo,
				BIdentificativo = r.Identificativo,
				Diretta = IIF(r.Diretta = 'true', 1, 0)
			INTO #rif
			FROM
				dbo.tblRentriImportazioniMovimenti m
				CROSS APPLY OPENJSON(ISNULL(m.JsonValori, m.Json), '$.riferimenti.riferimento_operazione') x
				CROSS APPLY (
					SELECT
						Anno = TRY_CAST(JSON_VALUE(x.value, '$.anno') AS SMALLINT),
						Progressivo = TRY_CAST(JSON_VALUE(x.value, '$.progressivo') AS INT),
						Identificativo = JSON_VALUE(x.value, '$.identificativo'),
						Diretta = JSON_VALUE(x.value, '$.associazione_diretta')
				) r
			WHERE
				m.IdImportazione = @Id
				AND m.Tipo = 'M'
				AND m.Azione IN ('I', 'X')
				AND r.Anno IS NOT NULL
				AND r.Progressivo IS NOT NULL;

			SELECT
				r.AAnno, r.AProgressivo, r.BAnno, r.BProgressivo, r.BIdentificativo,
				BInArea = IIF(b.Anno IS NULL, 0, 1),
				BAzione = b.Azione,
				PadreA =
					CASE
						WHEN b.Anno IS NULL THEN MAX(r.Diretta) OVER (PARTITION BY r.AAnno, r.AProgressivo, r.BAnno, r.BProgressivo)
						WHEN v.AB = 1 AND v.BA = 0 THEN 1
						WHEN v.BA = 1 AND v.AB = 0 THEN 0
						WHEN v.AB = 0 AND v.BA = 0 THEN MAX(r.Diretta) OVER (PARTITION BY r.AAnno, r.AProgressivo, r.BAnno, r.BProgressivo)
						WHEN a.Data > b.Data OR (a.Data = b.Data AND (a.Anno > b.Anno OR (a.Anno = b.Anno AND a.Progressivo > b.Progressivo))) THEN 1
						ELSE 0
					END
			INTO #verso
			FROM
				#rif r
				INNER JOIN dbo.tblRentriImportazioniMovimenti a
					ON a.IdImportazione = @Id AND a.Anno = r.AAnno AND a.Progressivo = r.AProgressivo
				LEFT JOIN dbo.tblRentriImportazioniMovimenti b
					ON b.IdImportazione = @Id AND b.Anno = r.BAnno AND b.Progressivo = r.BProgressivo AND b.Tipo = 'M'
				CROSS APPLY (
					SELECT
						AB = IIF(EXISTS (SELECT 1 FROM dbo.tblRifiutiOperazioniRelazioni z WHERE z.Id = a.IdOperazione AND z.IdParent = b.IdOperazione), 1, 0),
						BA = IIF(EXISTS (SELECT 1 FROM dbo.tblRifiutiOperazioniRelazioni z WHERE z.Id = b.IdOperazione AND z.IdParent = a.IdOperazione), 1, 0)
				) v;

			SELECT
				PadreAnno, PadreProgressivo, FiglioAnno, FiglioProgressivo,
				FiglioIdentificativo = MIN(FiglioIdentificativo),
				Pos = ROW_NUMBER() OVER (PARTITION BY PadreAnno, PadreProgressivo ORDER BY FiglioAnno, FiglioProgressivo)
			INTO #riferimenti
			FROM (
				SELECT
					PadreAnno = AAnno, PadreProgressivo = AProgressivo,
					FiglioAnno = BAnno, FiglioProgressivo = BProgressivo, FiglioIdentificativo = BIdentificativo
				FROM #verso
				WHERE PadreA = 1
				UNION ALL
				SELECT
					BAnno, BProgressivo, AAnno, AProgressivo,
					(SELECT TOP 1 m.Identificativo FROM dbo.tblRentriImportazioniMovimenti m WHERE m.IdImportazione = @Id AND m.Anno = AAnno AND m.Progressivo = AProgressivo)
				FROM #verso
				WHERE PadreA = 0 AND BInArea = 1 AND BAzione IN ('I', 'X')
			) z
			GROUP BY PadreAnno, PadreProgressivo, FiglioAnno, FiglioProgressivo;

			-- Le relazioni corrette dall'utente (IsModificata) restano; le altre si ripropongono da zero
			DELETE l
			FROM dbo.tblRentriImportazioniRelazioni l
			WHERE
				l.IdImportazione = @Id
				AND (
					l.IsModificata = 0
					OR NOT EXISTS (
						SELECT 1
						FROM dbo.tblRentriImportazioniMovimenti m
						WHERE m.IdImportazione = @Id AND m.Anno = l.PadreAnno AND m.Progressivo = l.PadreProgressivo AND m.Azione IN ('I', 'X')));

			INSERT dbo.tblRentriImportazioniRelazioni (
				IdImportazione, PadreAnno, PadreProgressivo, FiglioAnno, FiglioProgressivo, FiglioIdentificativo, Pos, Operazione, IsModificata)
			SELECT
				@Id, r.PadreAnno, r.PadreProgressivo, r.FiglioAnno, r.FiglioProgressivo, MIN(r.FiglioIdentificativo), MIN(r.Pos), MIN(o.Operazione), 0
			FROM
				#riferimenti r
				INNER JOIN dbo.tblRentriImportazioniMovimenti p
					ON p.IdImportazione = @Id AND p.Anno = r.PadreAnno AND p.Progressivo = r.PadreProgressivo
				LEFT JOIN dbo.tblRifiutiOperazioni o ON p.IdOperazione = o.Id
			WHERE NOT EXISTS (
				SELECT 1
				FROM dbo.tblRentriImportazioniRelazioni l
				WHERE l.IdImportazione = @Id AND l.PadreAnno = r.PadreAnno AND l.PadreProgressivo = r.PadreProgressivo)
			GROUP BY r.PadreAnno, r.PadreProgressivo, r.FiglioAnno, r.FiglioProgressivo;

			-- Figlio già in Ecomatico: per identificativo RENTRI, altrimenti per numero e anno tra le inviate
			UPDATE l
			SET IdRegistrazioneFiglio = COALESCE(f.IdRegistrazione, g1.Id, g2.Id)
			FROM
				dbo.tblRentriImportazioniRelazioni l
				LEFT JOIN dbo.tblRentriImportazioniMovimenti f
					ON f.IdImportazione = @Id AND f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
				OUTER APPLY (SELECT TOP 1 g.Id FROM #registro g WHERE g.RentriIdentificativo = l.FiglioIdentificativo) g1
				OUTER APPLY (
					SELECT TOP 1 g.Id
					FROM #registro g
					WHERE g.Anno = l.FiglioAnno AND g.Numero = l.FiglioProgressivo AND g.RentriIdentificativo IS NOT NULL
				) g2
			WHERE l.IdImportazione = @Id;

			-- Registrazioni associate (figli) con la quantità disponibile di partenza: nell'area temporanea la
			-- quantità trasmessa in origine, in Ecomatico il residuo operativo (giacenza: R7 delle rettifiche)
			SELECT
				f.Anno, f.Progressivo, f.Data, f.IdOperazione, f.IdEer, f.IdStatoFisico, f.IdUnitaMisura,
				Disponibile = ISNULL(f.Quantita, 0),
				IsStaging = CAST(1 AS BIT),
				f.Azione
			INTO #figli
			FROM dbo.tblRentriImportazioniMovimenti f
			WHERE
				f.IdImportazione = @Id
				AND f.Azione IN ('I', 'X')
				AND EXISTS (
					SELECT 1
					FROM dbo.tblRentriImportazioniRelazioni l
					WHERE l.IdImportazione = @Id AND l.FiglioAnno = f.Anno AND l.FiglioProgressivo = f.Progressivo);

			CREATE UNIQUE CLUSTERED INDEX IX_figli ON #figli (Anno, Progressivo);

			INSERT #figli (Anno, Progressivo, Data, IdOperazione, IdEer, IdStatoFisico, IdUnitaMisura, Disponibile, IsStaging, Azione)
			SELECT
				l.FiglioAnno, l.FiglioProgressivo, r.Data, v.IdOperazione, e.IdEer, e.IdStatoFisico, e.IdUnitaMisura,
				ISNULL(e.Quantita, 0) - ISNULL((
					SELECT SUM(x.Quantita)
					FROM
						dbo.tblRifiutiRegistrazioniRelazioni x
						INNER JOIN dbo.tblRifiutiRegistrazioni rp ON x.IdParent = rp.Id
						INNER JOIN dbo.viewRifiutiRegistrazioniEffettive vp ON rp.Id = vp.Id
					WHERE
						x.Id = r.Id
						AND x.Quantita > 0
						AND rp.Lock < 2
						AND vp.IsAnnullata = 0
				), 0),
				0,
				'P'
			FROM
				(
					SELECT FiglioAnno, FiglioProgressivo, IdRegistrazioneFiglio = MIN(IdRegistrazioneFiglio)
					FROM dbo.tblRentriImportazioniRelazioni
					WHERE IdImportazione = @Id AND IdRegistrazioneFiglio IS NOT NULL
					GROUP BY FiglioAnno, FiglioProgressivo
				) l
				INNER JOIN dbo.tblRifiutiRegistrazioni r ON l.IdRegistrazioneFiglio = r.Id
				INNER JOIN dbo.tblRifiutiMovimenti v ON r.IdMovimento = v.Id
				INNER JOIN dbo.viewRifiutiRegistrazioniEffettive e ON r.Id = e.Id
			WHERE NOT EXISTS (
				SELECT 1
				FROM #figli f
				WHERE f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo);

			-- Ripartizione FIFO: padri in ordine di data e numero, figli di ciascun padre in ordine di data e numero.
			-- Un solo figlio: riceve tutta la quantità del padre (l'eventuale eccedenza è un'anomalia). Più figli:
			-- ognuno dà al massimo il proprio residuo, solo tra i figli che RENTRI riporta. Le relazioni corrette
			-- dall'utente si tengono come sono. Un padre annullato su RENTRI non consuma (annullamento operativo, R4.6).
			DECLARE
				@pAnno SMALLINT, @pProgressivo INT, @pQuantita DECIMAL(18, 4), @pAnnullato BIT, @pModificata INT, @pFigli INT,
				@fAnno SMALLINT, @fProgressivo INT, @fQuantita DECIMAL(18, 4), @disponibile DECIMAL(18, 4), @quota DECIMAL(18, 4);

			DECLARE cPadri CURSOR LOCAL FAST_FORWARD FOR
				SELECT p.Anno, p.Progressivo, ISNULL(p.Quantita, 0), ISNULL(p.IsAnnullato, 0), MAX(CAST(l.IsModificata AS INT)), COUNT(*)
				FROM
					dbo.tblRentriImportazioniRelazioni l
					INNER JOIN dbo.tblRentriImportazioniMovimenti p
						ON p.IdImportazione = l.IdImportazione AND p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
				WHERE l.IdImportazione = @Id
				GROUP BY p.Anno, p.Progressivo, p.Quantita, p.IsAnnullato, p.Data
				ORDER BY p.Data, p.Anno, p.Progressivo;

			OPEN cPadri;
			FETCH cPadri INTO @pAnno, @pProgressivo, @pQuantita, @pAnnullato, @pModificata, @pFigli;
			WHILE @@FETCH_STATUS = 0
			BEGIN
				DECLARE cFigli CURSOR LOCAL FAST_FORWARD FOR
					SELECT l.FiglioAnno, l.FiglioProgressivo, l.Quantita
					FROM
						dbo.tblRentriImportazioniRelazioni l
						LEFT JOIN #figli f ON f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
					WHERE l.IdImportazione = @Id AND l.PadreAnno = @pAnno AND l.PadreProgressivo = @pProgressivo
					ORDER BY IIF(f.Data IS NULL, 1, 0), f.Data, l.FiglioAnno, l.FiglioProgressivo;

				OPEN cFigli;
				FETCH cFigli INTO @fAnno, @fProgressivo, @fQuantita;
				WHILE @@FETCH_STATUS = 0
				BEGIN
					SET @disponibile = (SELECT Disponibile FROM #figli WHERE Anno = @fAnno AND Progressivo = @fProgressivo);

					IF @pModificata = 1
						SET @quota = ISNULL(@fQuantita, 0);
					ELSE IF @pFigli = 1
						SET @quota = @pQuantita;
					ELSE
						SET @quota = CASE
							WHEN ISNULL(@disponibile, 0) <= 0 THEN 0
							WHEN @disponibile < @pQuantita THEN @disponibile
							ELSE @pQuantita
						END;

					UPDATE dbo.tblRentriImportazioniRelazioni
					SET
						DisponibilePrima = @disponibile,
						QuantitaProposta = IIF(@pModificata = 1, QuantitaProposta, @quota),
						Quantita = @quota
					WHERE
						IdImportazione = @Id
						AND PadreAnno = @pAnno AND PadreProgressivo = @pProgressivo
						AND FiglioAnno = @fAnno AND FiglioProgressivo = @fProgressivo;

					SET @pQuantita = @pQuantita - @quota;
					IF @pQuantita < 0 SET @pQuantita = 0;

					IF @pAnnullato = 0
						UPDATE #figli
						SET Disponibile = Disponibile - @quota
						WHERE Anno = @fAnno AND Progressivo = @fProgressivo;

					FETCH cFigli INTO @fAnno, @fProgressivo, @fQuantita;
				END
				CLOSE cFigli;
				DEALLOCATE cFigli;

				FETCH cPadri INTO @pAnno, @pProgressivo, @pQuantita, @pAnnullato, @pModificata, @pFigli;
			END
			CLOSE cPadri;
			DEALLOCATE cPadri;

			-- Anomalie delle relazioni (sul padre)
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, l.PadreAnno, l.PadreProgressivo, 'E', 'RIFERIMENTO_MANCANTE',
				CONCAT('Si riferisce alla registrazione n. ', l.FiglioProgressivo, '/', l.FiglioAnno, ', che non è stata trovata né su RENTRI né in Ecomatico')
			FROM dbo.tblRentriImportazioniRelazioni l
			WHERE
				l.IdImportazione = @Id
				AND NOT EXISTS (SELECT 1 FROM #figli f WHERE f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo);

			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, l.PadreAnno, l.PadreProgressivo, 'E', 'RELAZIONE_NON_AMMESSA',
				CONCAT('In Ecomatico la registrazione n. ', l.FiglioProgressivo, '/', l.FiglioAnno, ' (', ISNULL(oFiglio.Nome, 'operazione sconosciuta'),
					') non può essere associata a questa (', ISNULL(oPadre.Nome, 'operazione sconosciuta'), ')')
			FROM
				dbo.tblRentriImportazioniRelazioni l
				INNER JOIN dbo.tblRentriImportazioniMovimenti p
					ON p.IdImportazione = l.IdImportazione AND p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
				INNER JOIN #figli f ON f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
				LEFT JOIN dbo.tblRifiutiOperazioni oPadre ON p.IdOperazione = oPadre.Id
				LEFT JOIN dbo.tblRifiutiOperazioni oFiglio ON f.IdOperazione = oFiglio.Id
			WHERE
				l.IdImportazione = @Id
				AND p.IdOperazione IS NOT NULL
				AND f.IdOperazione IS NOT NULL
				AND NOT EXISTS (
					SELECT 1
					FROM dbo.tblRifiutiOperazioniRelazioni x
					WHERE x.Id = p.IdOperazione AND x.IdParent = f.IdOperazione);

			-- Stesso EER, stato fisico e unità di misura (come al salvataggio; non per la derivazione da K/M)
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, l.PadreAnno, l.PadreProgressivo, 'E', 'RELAZIONE_EER',
				CONCAT('La registrazione associata n. ', l.FiglioProgressivo, '/', l.FiglioAnno, ' ha EER, stato fisico o unità di misura diversi')
			FROM
				dbo.tblRentriImportazioniRelazioni l
				INNER JOIN dbo.tblRentriImportazioniMovimenti p
					ON p.IdImportazione = l.IdImportazione AND p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
				INNER JOIN #figli f ON f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
			WHERE
				l.IdImportazione = @Id
				AND ISNULL(p.IdOperazione, '') NOT IN ('K', 'M')
				AND (
					ISNULL(f.IdEer, '') <> ISNULL(p.IdEer, '')
					OR ISNULL(f.IdStatoFisico, '') <> ISNULL(p.IdStatoFisico, '')
					OR ISNULL(f.IdUnitaMisura, '') <> ISNULL(p.IdUnitaMisura, ''));

			-- La registrazione associata non può essere successiva (data, poi numero) a quella che la associa
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, l.PadreAnno, l.PadreProgressivo, 'E', 'RELAZIONE_DATA',
				CONCAT('La registrazione associata n. ', l.FiglioProgressivo, '/', l.FiglioAnno, ' ha data o numero successivi a questa')
			FROM
				dbo.tblRentriImportazioniRelazioni l
				INNER JOIN dbo.tblRentriImportazioniMovimenti p
					ON p.IdImportazione = l.IdImportazione AND p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
				INNER JOIN #figli f ON f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
			WHERE
				l.IdImportazione = @Id
				AND (
					f.Data > p.Data
					OR (f.Data = p.Data AND (f.Anno > p.Anno OR (f.Anno = p.Anno AND f.Progressivo > p.Progressivo))));

			-- Quantità: disponibilità superata o quantità attribuite diverse da quella del padre
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, l.PadreAnno, l.PadreProgressivo, 'E', 'GIACENZA_INSUFFICIENTE',
				CONCAT('La registrazione associata n. ', l.FiglioProgressivo, '/', l.FiglioAnno, ' ha disponibili ',
					FORMAT(IIF(ISNULL(l.DisponibilePrima, 0) < 0, 0, ISNULL(l.DisponibilePrima, 0)), '0.##', 'it-IT'),
					', ne vengono attribuiti ', FORMAT(l.Quantita, '0.##', 'it-IT'))
			FROM dbo.tblRentriImportazioniRelazioni l
			WHERE
				l.IdImportazione = @Id
				AND l.Quantita > ISNULL(l.DisponibilePrima, 0)
				AND EXISTS (SELECT 1 FROM #figli f WHERE f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo);

			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, p.Anno, p.Progressivo, 'E', 'QUANTITA_RELAZIONI',
				IIF(s.Modificata = 0 AND s.Attribuita < ISNULL(p.Quantita, 0),
					CONCAT('Quantità insufficiente nelle registrazioni associate: disponibili ', FORMAT(s.Attribuita, '0.##', 'it-IT'),
						' su ', FORMAT(p.Quantita, '0.##', 'it-IT')),
					CONCAT('Le quantità attribuite alle registrazioni associate (', FORMAT(s.Attribuita, '0.##', 'it-IT'),
						') non corrispondono alla quantità della registrazione (', FORMAT(p.Quantita, '0.##', 'it-IT'), ')'))
			FROM
				dbo.tblRentriImportazioniMovimenti p
				CROSS APPLY (
					SELECT Attribuita = SUM(ISNULL(l.Quantita, 0)), Modificata = MAX(CAST(l.IsModificata AS INT))
					FROM dbo.tblRentriImportazioniRelazioni l
					WHERE l.IdImportazione = @Id AND l.PadreAnno = p.Anno AND l.PadreProgressivo = p.Progressivo
					HAVING COUNT(*) > 0
				) s
			WHERE
				p.IdImportazione = @Id
				AND s.Attribuita <> ISNULL(p.Quantita, 0);

			-- Registrazione che in Ecomatico prevede associazioni ma su RENTRI non ne ha
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'W', 'SENZA_RELAZIONI',
				IIF(m.IdOperazione = 'S',
					'Scarico senza registrazioni associate su RENTRI: verrà importato con "Nessuna registrazione associata"',
					'Su RENTRI non ha registrazioni associate')
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.Azione = 'I'
				AND m.Tipo = 'M'
				AND EXISTS (SELECT 1 FROM dbo.tblRifiutiOperazioniRelazioni x WHERE x.Id = m.IdOperazione)
				AND NOT EXISTS (
					SELECT 1
					FROM dbo.tblRentriImportazioniRelazioni l
					WHERE l.IdImportazione = @Id AND l.PadreAnno = m.Anno AND l.PadreProgressivo = m.Progressivo);

			-- Esclusioni a catena, finché ce ne sono: anomalia bloccante -> esclusa; rettifica o annullamento di un
			-- originale escluso; registrazione che associa una registrazione esclusa
			DECLARE @nuove INT = 1;
			WHILE @nuove > 0
			BEGIN
				UPDATE m
				SET Azione = 'X'
				FROM dbo.tblRentriImportazioniMovimenti m
				WHERE
					m.IdImportazione = @Id
					AND m.Azione = 'I'
					AND EXISTS (
						SELECT 1
						FROM dbo.tblRentriImportazioniAnomalie a
						WHERE a.IdImportazione = @Id AND a.Anno = m.Anno AND a.Progressivo = m.Progressivo AND a.Livello = 'E');

				INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
				SELECT
					@Id, m.Anno, m.Progressivo, 'E', 'ORIGINALE_ESCLUSO',
					CONCAT('La registrazione n. ', o.Progressivo, '/', o.Anno, ' che ', IIF(m.Tipo = 'A', 'annulla', 'rettifica'), ' non può essere importata')
				FROM
					dbo.tblRentriImportazioniMovimenti m
					INNER JOIN dbo.tblRentriImportazioniMovimenti o
						ON o.IdImportazione = m.IdImportazione AND o.Anno = m.RettificaAnno AND o.Progressivo = m.RettificaProgressivo
				WHERE
					m.IdImportazione = @Id
					AND m.Azione = 'I'
					AND o.Azione = 'X';
				SET @nuove = @@ROWCOUNT;

				INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
				SELECT DISTINCT
					@Id, p.Anno, p.Progressivo, 'E', 'ASSOCIATA_ESCLUSA',
					CONCAT('La registrazione associata n. ', f.Progressivo, '/', f.Anno, ' non può essere importata')
				FROM
					dbo.tblRentriImportazioniRelazioni l
					INNER JOIN dbo.tblRentriImportazioniMovimenti p
						ON p.IdImportazione = l.IdImportazione AND p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
					INNER JOIN dbo.tblRentriImportazioniMovimenti f
						ON f.IdImportazione = l.IdImportazione AND f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
				WHERE
					l.IdImportazione = @Id
					AND p.Azione = 'I'
					AND f.Azione = 'X';
				SET @nuove = @nuove + @@ROWCOUNT;
			END

			-- ── 8. Avvisi ─────────────────────────────────────────────────────────────────────────
			-- Registrazioni recuperate fuori dall'intervallo perché richiamate da quelle dell'intervallo
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, m.Anno, m.Progressivo, 'W', 'FUORI_INTERVALLO',
				'Registrazione fuori dall''intervallo indicato, recuperata da RENTRI perché richiamata da una registrazione dell''intervallo'
			FROM dbo.tblRentriImportazioniMovimenti m
			WHERE
				m.IdImportazione = @Id
				AND m.IsIntervallo = 0
				AND m.Azione = 'I';

			-- Numeri mancanti su RENTRI dentro l'intervallo letto (dal primo numero richiesto all'ultimo trovato)
			;WITH n AS (
				SELECT
					m.Anno, m.Progressivo,
					Precedente = LAG(m.Progressivo) OVER (PARTITION BY m.Anno ORDER BY m.Progressivo)
				FROM dbo.tblRentriImportazioniMovimenti m
				WHERE m.IdImportazione = @Id AND m.IsIntervallo = 1
			)
			INSERT dbo.tblRentriImportazioniAnomalie (IdImportazione, Anno, Progressivo, Livello, Codice, Messaggio)
			SELECT
				@Id, n.Anno, NULL, 'W', 'NUMERI_MANCANTI',
				IIF(x.Dal = x.Al,
					CONCAT('Su RENTRI non c''è la registrazione n. ', x.Dal, '/', n.Anno),
					CONCAT('Su RENTRI non ci sono le registrazioni dal n. ', x.Dal, ' al n. ', x.Al, '/', n.Anno))
			FROM
				n
				CROSS APPLY (
					SELECT
						Dal = ISNULL(n.Precedente + 1, IIF(n.Anno = @dalAnno, @dalNumero, 1)),
						Al = n.Progressivo - 1
				) x
			WHERE x.Dal <= x.Al;

		COMMIT TRANSACTION;

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

-- ===== 3. uspRentriImportazioni_ins
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: crea l'area temporanea con i movimenti letti da RENTRI per un registro collegato e ne
-- esegue l'analisi (uspRentriImportazioni_upd_Analisi). Non scrive nulla nel registro: le registrazioni nascono
-- solo dall'esecuzione definitiva.
--
-- @Movimenti: array JSON preparato dall'app con i movimenti restituiti dall'hub, ognuno con
--   anno, progressivo, identificativo, isIntervallo (1 = nell'intervallo richiesto, 0 = recuperato perché
--   richiamato da un movimento dell'intervallo), json (movimento corrente come restituito da RENTRI),
--   jsonDettaglio (dettaglio con le variazioni, solo per le registrazioni rettificate o annullate),
--   jsonFormulario e formularioStato (D formulario digitale letto, N non trovato: solo per le registrazioni con numero
--   di formulario ma senza trasportatore o destinatario su RENTRI, da cui l'analisi li recupera).
-- I JSON di RENTRI si salvano così come arrivano e non si modificano più (copia originale).
--
-- @Modalita: F tutte le registrazioni fino ad @AlNumero/@AlAnno (letti tutti gli anni dal 2020: @DalAnno 2020,
-- @DalNumero 1), I solo l'intervallo indicato.
-- Un'importazione in preparazione per registro: quella precedente non eseguita viene sostituita.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_ins]
	@IdSessione CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL,
	@Modalita CHAR(1) = NULL,
	@DalAnno SMALLINT = NULL,
	@DalNumero INT = NULL,
	@AlAnno SMALLINT = NULL,
	@AlNumero INT = NULL,
	@Movimenti NVARCHAR(MAX) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');
		SET @Modalita = NULLIF(LTRIM(RTRIM(@Modalita)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Selezionare il registro';
			GOTO BRANCH_END;
		END
		IF @Modalita IS NULL OR @Modalita NOT IN ('F', 'I')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Modalita non è valido';
			GOTO BRANCH_END;
		END
		IF @DalAnno IS NULL OR @DalNumero IS NULL OR @AlAnno IS NULL OR @AlNumero IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Indicare numero e anno di inizio e di fine delle registrazioni da importare';
			GOTO BRANCH_END;
		END
		IF @DalAnno < 2020 OR @AlAnno > 2050 OR @DalNumero < 1 OR @AlNumero < 1
			OR @DalAnno > @AlAnno OR (@DalAnno = @AlAnno AND @DalNumero > @AlNumero)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''intervallo delle registrazioni da importare non è valido';
			GOTO BRANCH_END;
		END
		IF @Movimenti IS NULL OR ISJSON(@Movimenti) = 0
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Movimenti non è valido';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità)
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRifiutiRegistri g
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE
				g.Id = @IdRegistro
				AND g.Lock = 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.tblRentriRegistri WHERE Id = @IdRegistro AND IdRentri IS NOT NULL)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il registro non è collegato a RENTRI';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16) = (SELECT IdUtente FROM dbo.tblSessioni WHERE Id = @IdSessione);

		-- Movimenti letti dall'hub (un movimento per anno e numero: eventuali doppioni dell'app si scartano)
		SELECT
			j.Anno, j.Progressivo, j.Identificativo, ISNULL(j.IsIntervallo, 0) AS IsIntervallo, j.Json, j.JsonDettaglio, j.JsonFormulario, j.FormularioStato,
			rn = ROW_NUMBER() OVER (PARTITION BY j.Anno, j.Progressivo ORDER BY ISNULL(j.IsIntervallo, 0) DESC)
		INTO #movimenti
		FROM
			OPENJSON(@Movimenti)
			WITH (
				Anno SMALLINT '$.anno',
				Progressivo INT '$.progressivo',
				Identificativo VARCHAR(50) '$.identificativo',
				IsIntervallo BIT '$.isIntervallo',
				Json NVARCHAR(MAX) '$.json',
				JsonDettaglio NVARCHAR(MAX) '$.jsonDettaglio',
				JsonFormulario NVARCHAR(MAX) '$.jsonFormulario',
				FormularioStato CHAR(1) '$.formularioStato'
			) j;

		IF EXISTS (
			SELECT 1
			FROM #movimenti
			WHERE
				Anno IS NULL OR Progressivo IS NULL OR Json IS NULL OR ISJSON(Json) = 0
				OR (JsonDettaglio IS NOT NULL AND ISJSON(JsonDettaglio) = 0))
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'I movimenti ricevuti da RENTRI non sono validi';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (SELECT 1 FROM #movimenti WHERE IsIntervallo = 1)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Nessuna registrazione trovata su RENTRI nell''intervallo indicato';
			GOTO BRANCH_END;
		END

		DECLARE @id CHAR(16);
		EXEC dbo.uspId_get @IdSessione = @IdSessione, @Id = @id OUTPUT;

		BEGIN TRANSACTION;

			-- Una sola importazione in preparazione per registro
			DELETE dbo.tblRentriImportazioni
			WHERE
				IdRegistro = @IdRegistro
				AND Stato = 'P';

			INSERT dbo.tblRentriImportazioni (Id, IdRegistro, IdUtente, Modalita, DalAnno, DalNumero, AlAnno, AlNumero, Stato, DataCreazione)
			VALUES (@id, @IdRegistro, @idUtente, @Modalita, @DalAnno, @DalNumero, @AlAnno, @AlNumero, 'P', SYSDATETIME());

			INSERT dbo.tblRentriImportazioniMovimenti (IdImportazione, Anno, Progressivo, Identificativo, IsIntervallo, Json, JsonDettaglio, JsonFormulario, FormularioStato)
			SELECT @id, Anno, Progressivo, Identificativo, IsIntervallo, Json, JsonDettaglio, JsonFormulario, FormularioStato
			FROM #movimenti
			WHERE rn = 1;

		COMMIT TRANSACTION;

		EXEC dbo.uspRentriImportazioni_upd_Analisi @IdSessione = @IdSessione, @Id = @id;

		SELECT rtn = @id;

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

-- ===== 3. uspRentriImportazioni_get
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: testata e riepilogo dell'importazione (anteprima). Con @Id NULL restituisce l'importazione
-- in preparazione del registro @IdRegistro, se c'è (ripresa del lavoro dopo aver lasciato la pagina).
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_get]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdRegistro CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @IdRegistro = NULLIF(LTRIM(RTRIM(@IdRegistro)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL AND @IdRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		IF @Id IS NULL
			SELECT TOP 1 @Id = Id
			FROM dbo.tblRentriImportazioni
			WHERE IdRegistro = @IdRegistro AND Stato = 'P'
			ORDER BY DataCreazione DESC;

		-- Controlla il permesso sul record (titolarità) tramite il registro; nessuna importazione = nessuna riga
		SELECT
			m.Id,
			m.IdRegistro,
			RegistroNome = g.Nome,
			m.Modalita,
			m.DalAnno,
			m.DalNumero,
			m.AlAnno,
			m.AlNumero,
			m.Stato,
			m.FinoAlPrimoProblema,
			m.DataCreazione,
			m.DataAnalisi,
			m.DataEsecuzione,
			UtenteNome = LTRIM(RTRIM(CONCAT(u.Nome, ' ', u.Cognome))),
			Movimenti = s.Movimenti,
			DaImportare = s.DaImportare,
			GiaPresenti = s.GiaPresenti,
			Escluse = s.Escluse,
			FuoriIntervallo = s.FuoriIntervallo,
			Rettifiche = s.Rettifiche,
			Annullamenti = s.Annullamenti,
			Errori = a.Errori,
			Avvisi = a.Avvisi,
			Relazioni = (SELECT COUNT(*) FROM dbo.tblRentriImportazioniRelazioni z WHERE z.IdImportazione = m.Id),
			RelazioniModificate = (SELECT COUNT(DISTINCT CONCAT(z.PadreAnno, '/', z.PadreProgressivo)) FROM dbo.tblRentriImportazioniRelazioni z WHERE z.IdImportazione = m.Id AND z.IsModificata = 1)
		FROM
			dbo.tblRentriImportazioni m
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			LEFT JOIN dbo.tblUtenti u ON m.IdUtente = u.Id
			CROSS APPLY (
				SELECT
					Movimenti = COUNT(*),
					DaImportare = ISNULL(SUM(IIF(x.Azione = 'I', 1, 0)), 0),
					GiaPresenti = ISNULL(SUM(IIF(x.Azione = 'P', 1, 0)), 0),
					Escluse = ISNULL(SUM(IIF(x.Azione = 'X', 1, 0)), 0),
					FuoriIntervallo = ISNULL(SUM(IIF(x.IsIntervallo = 0, 1, 0)), 0),
					Rettifiche = ISNULL(SUM(IIF(x.Tipo = 'R', 1, 0)), 0),
					Annullamenti = ISNULL(SUM(IIF(x.Tipo = 'A', 1, 0)), 0)
				FROM dbo.tblRentriImportazioniMovimenti x
				WHERE x.IdImportazione = m.Id
			) s
			CROSS APPLY (
				SELECT
					Errori = ISNULL(SUM(IIF(y.Livello = 'E', 1, 0)), 0),
					Avvisi = ISNULL(SUM(IIF(y.Livello = 'W', 1, 0)), 0)
				FROM dbo.tblRentriImportazioniAnomalie y
				WHERE y.IdImportazione = m.Id
			) a
		WHERE m.Id = @Id;

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

-- ===== 3. uspRentriImportazioni_get_Movimenti_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: movimenti dell'anteprima, in ordine di anno e numero, con l'azione prevista e le anomalie
-- di ciascuno (la più grave determina il Livello: E bloccante, W avviso, I informazione).
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_get_Movimenti_List]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRentriImportazioni m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Importazione non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			m.Anno,
			m.Progressivo,
			m.Identificativo,
			m.Data,
			m.DataTrasmissione,
			m.Tipo,
			TipoNome =
				CASE m.Tipo
					WHEN 'R' THEN CONCAT('Rettifica della n. ', m.RettificaProgressivo, '/', m.RettificaAnno)
					WHEN 'A' THEN CONCAT('Annullamento della n. ', m.RettificaProgressivo, '/', m.RettificaAnno)
					ELSE NULL
				END,
			m.Causale,
			m.IdOperazione,
			OperazioneNome = o.Nome,
			m.Eer,
			m.StatoFisico,
			m.Quantita,
			m.UnitaMisura,
			m.IsAnnullato,
			m.IsRettificato,
			m.IsIntervallo,
			m.Azione,
			Livello = CASE x.Ordine WHEN 1 THEN 'E' WHEN 2 THEN 'W' WHEN 3 THEN 'I' ELSE NULL END,
			Anomalie = x.Anomalie
		FROM
			dbo.tblRentriImportazioniMovimenti m
			LEFT JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			OUTER APPLY (
				SELECT
					Ordine = MIN(CASE y.Livello WHEN 'E' THEN 1 WHEN 'W' THEN 2 ELSE 3 END),
					Anomalie = STRING_AGG(CAST(y.Messaggio AS NVARCHAR(MAX)), N' - ') WITHIN GROUP (ORDER BY y.Id)
				FROM dbo.tblRentriImportazioniAnomalie y
				WHERE y.IdImportazione = m.IdImportazione AND y.Anno = m.Anno AND y.Progressivo = m.Progressivo
			) x
		WHERE m.IdImportazione = @Id
		ORDER BY m.Anno, m.Progressivo;

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

-- ===== 3. uspRentriImportazioni_get_Anomalie_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: anomalie dell'anteprima, prima le bloccanti (E), poi gli avvisi (W) e le informazioni (I).
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_get_Anomalie_List]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRentriImportazioni m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Importazione non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			a.Anno,
			a.Progressivo,
			a.Livello,
			a.Codice,
			a.Messaggio
		FROM dbo.tblRentriImportazioniAnomalie a
		WHERE a.IdImportazione = @Id
		ORDER BY
			CASE a.Livello WHEN 'E' THEN 1 WHEN 'W' THEN 2 ELSE 3 END,
			a.Anno,
			a.Progressivo,
			a.Id;

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

-- ===== 3. uspRentriImportazioni_get_Relazioni_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: relazioni carico/scarico proposte (ripartizione FIFO) o corrette dall'utente, una riga per
-- coppia padre/figlio, in ordine di padre (data e numero) e di figlio. Padre = la registrazione che associa (scarico
-- che preleva, Operazione S; carico K/M che deriva dallo scarico R, Operazione C); figlio = l'associata, letta da
-- RENTRI (area temporanea) o già presente in Ecomatico.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_get_Relazioni_List]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRentriImportazioni m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Importazione non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			l.PadreAnno,
			l.PadreProgressivo,
			PadreData = p.Data,
			PadreCausale = p.Causale,
			PadreQuantita = p.Quantita,
			PadreUnitaMisura = p.UnitaMisura,
			PadreAzione = p.Azione,
			PadreIsAnnullato = p.IsAnnullato,
			l.Operazione,
			l.FiglioAnno,
			l.FiglioProgressivo,
			FiglioData = ISNULL(f.Data, r.Data),
			FiglioCausale = ISNULL(f.Causale, o.Codice),
			FiglioQuantita = ISNULL(f.Quantita, e.Quantita),
			FiglioAzione = f.Azione,
			IsFiglioInEcomatico = CAST(IIF(f.Azione IS NULL OR f.Azione = 'P', IIF(l.IdRegistrazioneFiglio IS NULL, 0, 1), 0) AS BIT),
			l.Pos,
			l.DisponibilePrima,
			l.QuantitaProposta,
			l.Quantita,
			l.IsModificata,
			Figli = COUNT(*) OVER (PARTITION BY l.PadreAnno, l.PadreProgressivo)
		FROM
			dbo.tblRentriImportazioniRelazioni l
			INNER JOIN dbo.tblRentriImportazioniMovimenti p
				ON p.IdImportazione = l.IdImportazione AND p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
			LEFT JOIN dbo.tblRentriImportazioniMovimenti f
				ON f.IdImportazione = l.IdImportazione AND f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
			LEFT JOIN dbo.tblRifiutiRegistrazioni r ON l.IdRegistrazioneFiglio = r.Id
			LEFT JOIN dbo.tblRifiutiMovimenti v ON r.IdMovimento = v.Id
			LEFT JOIN dbo.tblRifiutiOperazioni o ON v.IdOperazione = o.Id
			LEFT JOIN dbo.viewRifiutiRegistrazioniEffettive e ON r.Id = e.Id
		WHERE l.IdImportazione = @Id
		ORDER BY p.Data, l.PadreAnno, l.PadreProgressivo, ISNULL(f.Data, r.Data), l.FiglioAnno, l.FiglioProgressivo;

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

-- ===== 3. uspRentriImportazioni_upd_Relazione
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: l'utente corregge le quantità attribuite da una registrazione (padre) alle sue associate
-- (figli che RENTRI riporta: non se ne aggiungono altri), oppure ripristina la proposta FIFO (@Ripristina = 1).
-- @Quantita: array JSON [{ "figlioAnno": 2025, "figlioProgressivo": 12, "quantita": 10.5 }, ...].
-- Le quantità corrette restano anche rileggendo l'analisi (IsModificata); i controlli (disponibilità, somma uguale
-- alla quantità della registrazione) sono quelli dell'analisi, rilanciata subito dopo.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_upd_Relazione]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@PadreAnno SMALLINT = NULL,
	@PadreProgressivo INT = NULL,
	@Quantita NVARCHAR(MAX) = NULL,
	@Ripristina BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Ripristina = ISNULL(@Ripristina, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @PadreAnno IS NULL OR @PadreProgressivo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @PadreAnno/@PadreProgressivo non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Ripristina = 0 AND (@Quantita IS NULL OR ISJSON(@Quantita) = 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Quantita non è valido';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		DECLARE @stato CHAR(1);
		SELECT @stato = m.Stato
		FROM
			dbo.tblRentriImportazioni m
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE m.Id = @Id;

		IF @stato IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Importazione non trovata';
			GOTO BRANCH_END;
		END
		IF @stato <> 'P'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importazione è già stata eseguita';
			GOTO BRANCH_END;
		END

		IF NOT EXISTS (
			SELECT 1
			FROM dbo.tblRentriImportazioniRelazioni
			WHERE IdImportazione = @Id AND PadreAnno = @PadreAnno AND PadreProgressivo = @PadreProgressivo)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'La registrazione non ha registrazioni associate';
			GOTO BRANCH_END;
		END

		CREATE TABLE #quantita (FiglioAnno SMALLINT, FiglioProgressivo INT, Quantita DECIMAL(18, 4), Testo NVARCHAR(40));

		IF @Ripristina = 0
		BEGIN
			INSERT #quantita (FiglioAnno, FiglioProgressivo, Quantita, Testo)
			SELECT j.FiglioAnno, j.FiglioProgressivo, TRY_CONVERT(DECIMAL(18, 4), j.Testo), j.Testo
			FROM
				OPENJSON(@Quantita)
				WITH (
					FiglioAnno SMALLINT '$.figlioAnno',
					FiglioProgressivo INT '$.figlioProgressivo',
					Testo NVARCHAR(40) '$.quantita'
				) j;

			IF EXISTS (SELECT 1 FROM #quantita WHERE Quantita IS NULL OR Quantita < 0)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare quantità non negative';
				GOTO BRANCH_END;
			END
			IF EXISTS (SELECT 1 FROM #quantita WHERE Quantita <> ROUND(Quantita, 2))
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Le quantità possono avere al massimo 2 decimali';
				GOTO BRANCH_END;
			END
			IF EXISTS (
				SELECT 1
				FROM #quantita q
				WHERE NOT EXISTS (
					SELECT 1
					FROM dbo.tblRentriImportazioniRelazioni l
					WHERE
						l.IdImportazione = @Id AND l.PadreAnno = @PadreAnno AND l.PadreProgressivo = @PadreProgressivo
						AND l.FiglioAnno = q.FiglioAnno AND l.FiglioProgressivo = q.FiglioProgressivo))
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Si possono indicare quantità solo per le registrazioni associate su RENTRI';
				GOTO BRANCH_END;
			END
		END

		BEGIN TRANSACTION;

			IF @Ripristina = 1
				UPDATE dbo.tblRentriImportazioniRelazioni
				SET IsModificata = 0
				WHERE IdImportazione = @Id AND PadreAnno = @PadreAnno AND PadreProgressivo = @PadreProgressivo;
			ELSE
				UPDATE l
				SET
					Quantita = ISNULL(q.Quantita, l.Quantita),
					IsModificata = 1
				FROM
					dbo.tblRentriImportazioniRelazioni l
					LEFT JOIN #quantita q ON q.FiglioAnno = l.FiglioAnno AND q.FiglioProgressivo = l.FiglioProgressivo
				WHERE l.IdImportazione = @Id AND l.PadreAnno = @PadreAnno AND l.PadreProgressivo = @PadreProgressivo;

		COMMIT TRANSACTION;

		EXEC dbo.uspRentriImportazioni_upd_Analisi @IdSessione = @IdSessione, @Id = @Id;

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

-- ===== 3. uspRentriImportazioni_get_Soggetti_List
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: soggetti delle registrazioni lette da RENTRI (sezione "Soggetti" dell'anteprima), con lo
-- stato dell'abbinamento: A abbinato, N autorizzazione da aggiungere a una sede esistente, M da completare,
-- U scelto dall'utente, C da creare con i dati completati dall'utente. Prima quelli da completare.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_get_Soggetti_List]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRentriImportazioni m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Importazione non trovata';
			GOTO BRANCH_END;
		END

		SELECT
			x.Id,
			x.Ruolo,
			RuoloNome = CASE x.Ruolo WHEN 'P' THEN 'Produttore' WHEN 'T' THEN 'Trasportatore' WHEN 'D' THEN 'Destinatario' ELSE 'Intermediario' END,
			x.CodiceFiscale,
			Numero = NULLIF(x.Numero, ''),
			x.Denominazione,
			x.Stato,
			x.IsModificato,
			x.IdAutorizzazione,
			AutorizzazioneNome = IIF(a.Id IS NULL, NULL, CONCAT(sa.NomeCompleto, IIF(a.Numero IS NULL, ' - nessuna autorizzazione', CONCAT(' - n. ', a.Numero)))),
			x.IdSede,
			SedeNome = s.NomeCompleto,
			x.Nome,
			x.PartitaIva,
			x.IdNazione,
			x.IdComune,
			ComuneNome = k.Nome,
			x.Localita,
			x.CAP,
			x.Indirizzo,
			x.NumeroCivico,
			Registrazioni = (SELECT COUNT(DISTINCT CONCAT(ms.Anno, '/', ms.Progressivo)) FROM dbo.tblRentriImportazioniMovimentiSoggetti ms WHERE ms.IdSoggetto = x.Id)
		FROM
			dbo.tblRentriImportazioniSoggetti x
			LEFT JOIN dbo.tblRifiutiAutorizzazioni a ON x.IdAutorizzazione = a.Id
			LEFT JOIN dbo.tblSedi sa ON a.IdSede = sa.Id
			LEFT JOIN dbo.tblSedi s ON x.IdSede = s.Id
			LEFT JOIN dbo.tblComuni k ON x.IdComune = k.Id
		WHERE x.IdImportazione = @Id
		ORDER BY IIF(x.Stato = 'M', 0, 1), x.CodiceFiscale, x.Ruolo, x.Numero;

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

-- ===== 3. uspRentriImportazioni_get_Abbinamenti_SelectList
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: anagrafiche di Ecomatico a cui abbinare un soggetto letto da RENTRI. Tipo A: autorizzazione
-- del ruolo del soggetto (usata così com'è); Tipo S: sede a cui aggiungere, all'importazione, l'autorizzazione con il
-- numero di RENTRI. Solo sedi visibili all'azienda interna del registro (stesso calcolo dell'abbinamento automatico);
-- prima quelle con lo stesso codice fiscale o partita IVA del soggetto. Al massimo 50 righe.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_get_Abbinamenti_SelectList]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdSoggetto INT = NULL,
	@Search VARCHAR(50) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Search = dbo.ufnStringhe_get_SenzaSpazi(@Search, 0, 1);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL OR @IdSoggetto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 1 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		DECLARE @idAziendaInterna CHAR(16), @ruolo CHAR(1), @codiceFiscale VARCHAR(20);
		SELECT
			@idAziendaInterna = sr.IdAziendaInterna,
			@ruolo = x.Ruolo,
			@codiceFiscale = x.CodiceFiscale
		FROM
			dbo.tblRentriImportazioniSoggetti x
			INNER JOIN dbo.tblRentriImportazioni m ON x.IdImportazione = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi sr ON g.IdSede = sr.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			m.Id = @Id
			AND x.Id = @IdSoggetto;

		IF @ruolo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Soggetto non trovato';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16) = (SELECT IdUtente FROM dbo.tblSessioni WHERE Id = @IdSessione);

		;WITH sedi AS (
			SELECT s.Id, s.NomeCompleto, s.IndirizzoCompleto, s.CodiceFiscale, s.PartitaIva,
				Stesso = IIF(UPPER(s.CodiceFiscale) = @codiceFiscale OR UPPER(s.PartitaIva) = @codiceFiscale, 1, 0)
			FROM
				dbo.ufnSedi_get_SediByUtente_List(@idUtente) u
				INNER JOIN dbo.tblSedi s ON u.Id = s.Id
			WHERE
				u.Disabilitata = 0
				AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
				AND s.Disabilitata = 0
				AND s.Lock < 2
				AND (
					@Search IS NULL
					OR s.NomeCompleto LIKE '%' + @Search + '%'
					OR s.CodiceFiscale LIKE '%' + @Search + '%'
					OR s.PartitaIva LIKE '%' + @Search + '%')
		),
		opzioni AS (
			SELECT
				Tipo = 'A', a.Id, s.Stesso,
				Testo = CONCAT(s.NomeCompleto, IIF(a.Numero IS NULL, ' - nessuna autorizzazione', CONCAT(' - n. ', a.Numero)),
					IIF(s.IndirizzoCompleto IS NULL, '', CONCAT(' - ', s.IndirizzoCompleto)))
			FROM
				dbo.tblRifiutiAutorizzazioni a
				INNER JOIN sedi s ON a.IdSede = s.Id
			WHERE
				a.IdRuolo = @ruolo
				AND a.Disabilitata = 0
				AND a.Lock < 2
			UNION ALL
			SELECT
				Tipo = 'S', s.Id, s.Stesso,
				Testo = CONCAT(s.NomeCompleto, IIF(s.IndirizzoCompleto IS NULL, '', CONCAT(' - ', s.IndirizzoCompleto)), ' (nuova autorizzazione)')
			FROM sedi s
		)
		SELECT TOP 50 Tipo, Id, Testo
		FROM opzioni
		ORDER BY Stesso DESC, Tipo, Testo
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

-- ===== 3. uspRentriImportazioni_upd_Soggetto
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: risoluzione di un soggetto letto da RENTRI (sezione "Soggetti" dell'anteprima).
--   @Azione 'A' abbina: @IdAutorizzazione (autorizzazione esistente del ruolo, usata com'è) oppure @IdSede (sede
--               esistente a cui aggiungere all'importazione l'autorizzazione con il numero di RENTRI);
--   @Azione 'C' completa: dati obbligatori per creare il soggetto che manca (nome, partita IVA, comune o località
--               estera, CAP, indirizzo). Valgono per tutti i soggetti con lo stesso codice fiscale ancora da
--               completare: il soggetto si crea una volta sola, con un'autorizzazione per ogni ruolo e numero;
--   @Azione 'R' ripristina l'abbinamento automatico.
-- Codice fiscale, denominazione e numeri restano quelli di RENTRI. Nessun dato viene scritto nell'anagrafica: lo fa
-- l'esecuzione dell'importazione. Subito dopo si rilancia l'analisi.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_upd_Soggetto]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@IdSoggetto INT = NULL,
	@Azione CHAR(1) = NULL,
	@IdAutorizzazione CHAR(16) = NULL,
	@IdSede CHAR(16) = NULL,
	@Nome VARCHAR(50) = NULL,
	@PartitaIva VARCHAR(20) = NULL,
	@IdNazione CHAR(3) = NULL,
	@IdComune VARCHAR(50) = NULL,
	@Localita VARCHAR(50) = NULL,
	@CAP VARCHAR(10) = NULL,
	@Indirizzo VARCHAR(50) = NULL,
	@NumeroCivico VARCHAR(10) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @Azione = NULLIF(LTRIM(RTRIM(@Azione)), '');
		SET @IdAutorizzazione = NULLIF(LTRIM(RTRIM(@IdAutorizzazione)), '');
		SET @IdSede = NULLIF(LTRIM(RTRIM(@IdSede)), '');
		SET @IdNazione = ISNULL(NULLIF(LTRIM(RTRIM(@IdNazione)), ''), '380');
		SET @Nome = NULLIF(LTRIM(RTRIM(@Nome)), '');
		SET @PartitaIva = NULLIF(UPPER(LTRIM(RTRIM(@PartitaIva))), '');
		SET @IdComune = NULLIF(LTRIM(RTRIM(@IdComune)), '');
		SET @Localita = NULLIF(LTRIM(RTRIM(@Localita)), '');
		SET @CAP = NULLIF(LTRIM(RTRIM(@CAP)), '');
		SET @Indirizzo = NULLIF(LTRIM(RTRIM(@Indirizzo)), '');
		SET @NumeroCivico = NULLIF(LTRIM(RTRIM(@NumeroCivico)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL OR @IdSoggetto IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Azione IS NULL OR @Azione NOT IN ('A', 'C', 'R')
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Azione non è valido';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		DECLARE @stato CHAR(1), @ruolo CHAR(1), @codiceFiscale VARCHAR(20), @idAziendaInterna CHAR(16);
		SELECT
			@stato = m.Stato,
			@ruolo = x.Ruolo,
			@codiceFiscale = x.CodiceFiscale,
			@idAziendaInterna = sr.IdAziendaInterna
		FROM
			dbo.tblRentriImportazioniSoggetti x
			INNER JOIN dbo.tblRentriImportazioni m ON x.IdImportazione = m.Id
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi sr ON g.IdSede = sr.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			m.Id = @Id
			AND x.Id = @IdSoggetto;

		IF @ruolo IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Soggetto non trovato';
			GOTO BRANCH_END;
		END
		IF @stato <> 'P'
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'L''importazione è già stata eseguita';
			GOTO BRANCH_END;
		END

		IF @Azione = 'A'
		BEGIN
			IF (@IdAutorizzazione IS NULL AND @IdSede IS NULL) OR (@IdAutorizzazione IS NOT NULL AND @IdSede IS NOT NULL)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Selezionare l''autorizzazione o la sede da abbinare';
				GOTO BRANCH_END;
			END

			-- Solo anagrafiche visibili all'azienda interna del registro
			DECLARE @idUtente CHAR(16) = (SELECT IdUtente FROM dbo.tblSessioni WHERE Id = @IdSessione);
			DECLARE @idSedeVerifica CHAR(16) = @IdSede;

			IF @IdAutorizzazione IS NOT NULL
				SELECT @idSedeVerifica = a.IdSede
				FROM dbo.tblRifiutiAutorizzazioni a
				WHERE a.Id = @IdAutorizzazione AND a.IdRuolo = @ruolo AND a.Disabilitata = 0 AND a.Lock < 2;

			IF @idSedeVerifica IS NULL OR NOT EXISTS (
				SELECT 1
				FROM
					dbo.ufnSedi_get_SediByUtente_List(@idUtente) u
					INNER JOIN dbo.tblSedi s ON u.Id = s.Id
				WHERE
					u.Id = @idSedeVerifica
					AND u.Disabilitata = 0
					AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
					AND s.Disabilitata = 0
					AND s.Lock < 2)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'L''autorizzazione o la sede selezionata non è disponibile';
				GOTO BRANCH_END;
			END
		END

		IF @Azione = 'C'
		BEGIN
			IF @Nome IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare il nome';
				GOTO BRANCH_END;
			END
			IF NOT EXISTS (SELECT 1 FROM dbo.tblNazioni WHERE Id = @IdNazione)
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Nazione non valida';
				GOTO BRANCH_END;
			END
			IF @IdNazione = '380' AND (@IdComune IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.tblComuni WHERE Id = @IdComune))
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare il comune';
				GOTO BRANCH_END;
			END
			IF @IdNazione <> '380' AND @Localita IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare il paese estero';
				GOTO BRANCH_END;
			END
			IF @CAP IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare il CAP';
				GOTO BRANCH_END;
			END
			IF @IdNazione = '380' AND (LEN(@CAP) <> 5 OR @CAP LIKE '%[^0-9]%')
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'CAP non corretto';
				GOTO BRANCH_END;
			END
			IF @Indirizzo IS NULL
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Indicare l''indirizzo';
				GOTO BRANCH_END;
			END
			IF @IdNazione = '380' AND @PartitaIva IS NOT NULL AND (LEN(@PartitaIva) <> 11 OR @PartitaIva LIKE '%[^0-9]%')
			BEGIN
				SET @returnValue = -1;
				SET @returnMessage = 'Partita Iva non corretta';
				GOTO BRANCH_END;
			END
		END

		BEGIN TRANSACTION;

			IF @Azione = 'A'
				UPDATE dbo.tblRentriImportazioniSoggetti
				SET
					Stato = 'U',
					IsModificato = 1,
					IdAutorizzazione = @IdAutorizzazione,
					IdSede = @IdSede
				WHERE IdImportazione = @Id AND Id = @IdSoggetto;

			-- Il completamento vale per tutti i soggetti con lo stesso codice fiscale ancora da completare (o già
			-- completati): un solo soggetto in anagrafica
			IF @Azione = 'C'
				UPDATE dbo.tblRentriImportazioniSoggetti
				SET
					Stato = 'C',
					IsModificato = 1,
					IdAutorizzazione = NULL,
					IdSede = NULL,
					Nome = @Nome,
					PartitaIva = @PartitaIva,
					IdNazione = @IdNazione,
					IdComune = IIF(@IdNazione = '380', @IdComune, NULL),
					Localita = IIF(@IdNazione = '380', NULL, @Localita),
					CAP = @CAP,
					Indirizzo = @Indirizzo,
					NumeroCivico = @NumeroCivico
				WHERE
					IdImportazione = @Id
					AND CodiceFiscale = @codiceFiscale
					AND (Id = @IdSoggetto OR Stato IN ('M', 'C'));

			IF @Azione = 'R'
				UPDATE dbo.tblRentriImportazioniSoggetti
				SET IsModificato = 0
				WHERE IdImportazione = @Id AND Id = @IdSoggetto;

		COMMIT TRANSACTION;

		EXEC dbo.uspRentriImportazioni_upd_Analisi @IdSessione = @IdSessione, @Id = @Id;

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

-- ===== 3. uspRentriImportazioni_esegui
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: esecuzione definitiva. Scrive nel registro le registrazioni dell'anteprima, in un'unica
-- transazione (tutto o niente) con il registro bloccato come al salvataggio (R11.2 delle rettifiche):
--   1. rilancia l'analisi dentro la transazione (dati del registro e anagrafiche letti dopo il blocco);
--   2. registrazioni da importare: azione I. Con anomalie bloccanti (azione X) si procede solo con
--      @FinoAlPrimoProblema = 1, importando le registrazioni numerate prima della prima esclusa (registro senza buchi);
--   3. soggetti: autorizzazione abbinata (A, U), autorizzazione nuova su una sede esistente (N, U con sede), soggetto
--      nuovo con le sue autorizzazioni (C, uno per codice fiscale, dell'azienda interna del registro); per il produttore
--      senza numero l'autorizzazione "Nessuna" della sede; produttore assente su RENTRI ma previsto nella sede del
--      registro (ProduttoreSede): la "Nessuna" della sede del registro. Come uspSedi_ins/_upd e la migrazione 3.1;
--   4. movimenti e registrazioni con i valori trasmessi in origine (JsonValori), numero, data, identificativo e data di
--      trasmissione RENTRI: risultano già inviate e non si ritrasmettono (RentriIdentificativo/RentriData);
--   5. relazioni carico/scarico con le quantità dell'anteprima;
--   6. rettifiche e annullamenti (tblRentriRegistrazioniRettifiche) in ordine cronologico, con i valori operativi
--      calcolati come alla conferma nell'app (ufnRifiutiRegistrazioni_get_RettificaOperativa, come la migrazione 3.1).
-- Importazioni contemporanee: registri diversi non si aspettano, tranne per l'anagrafica. Due importazioni della stessa
-- azienda interna (registri diversi) si mettono in fila con un blocco applicativo sull'azienda, preso dopo il registro
-- e prima dell'analisi; un soggetto da creare che nel frattempo esiste già (stesso codice fiscale o partita IVA, unico
-- tra le sedi visibili) si riusa invece di crearne un doppione.
-- I JSON dell'area temporanea restano come storico, con l'Id della registrazione creata.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_esegui]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL,
	@FinoAlPrimoProblema BIT = 0
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');
		SET @FinoAlPrimoProblema = ISNULL(@FinoAlPrimoProblema, 0);

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		DECLARE @idRegistro CHAR(16), @idSedeRegistro CHAR(16), @idAziendaInterna CHAR(16);
		SELECT
			@idRegistro = m.IdRegistro,
			@idSedeRegistro = g.IdSede,
			@idAziendaInterna = s.IdAziendaInterna
		FROM
			dbo.tblRentriImportazioni m
			INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
			INNER JOIN dbo.tblSedi s ON g.IdSede = s.Id
			INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
		WHERE
			m.Id = @Id
			AND g.Lock = 0;

		IF @idRegistro IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Importazione non trovata';
			GOTO BRANCH_END;
		END

		DECLARE @idUtente CHAR(16) = (SELECT IdUtente FROM dbo.tblSessioni WHERE Id = @IdSessione);
		DECLARE @adesso DATETIME2(0) = SYSDATETIME();

		BEGIN TRANSACTION;

			-- Registro bloccato per primo (R11.2, R11.4), poi l'importazione
			DECLARE @blocco INT;
			SELECT @blocco = 1
			FROM dbo.tblRifiutiRegistri WITH (UPDLOCK, HOLDLOCK)
			WHERE Id = @idRegistro;

			UPDATE dbo.tblRentriImportazioni WITH (UPDLOCK, HOLDLOCK)
			SET DataEsecuzione = DataEsecuzione
			WHERE Id = @Id AND Stato = 'P';

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'L''importazione è già stata eseguita';
				GOTO BRANCH_END;
			END

			-- Anagrafica: una importazione alla volta per azienda interna (stesso ordine per tutti: registro, poi azienda)
			DECLARE @risorsa NVARCHAR(255) = CONCAT(N'RentriImportazione_', @idAziendaInterna), @blocco2 INT;
			EXEC @blocco2 = sp_getapplock @Resource = @risorsa, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 20000; -- entro il limite di 30 s dei comandi dell'app: oltre, il messaggio qui sotto
			IF @blocco2 < 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Un''altra importazione della stessa azienda è in corso: riprovare tra qualche minuto';
				GOTO BRANCH_END;
			END

			EXEC dbo.uspRentriImportazioni_upd_Analisi @IdSessione = @IdSessione, @Id = @Id;

			-- ── 2. Registrazioni da importare ─────────────────────────────────────────────────────
			DECLARE @limiteAnno SMALLINT, @limiteProgressivo INT;
			SELECT TOP 1 @limiteAnno = Anno, @limiteProgressivo = Progressivo
			FROM dbo.tblRentriImportazioniMovimenti
			WHERE IdImportazione = @Id AND Azione = 'X'
			ORDER BY Anno, Progressivo;

			IF @limiteAnno IS NOT NULL AND @FinoAlPrimoProblema = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Ci sono registrazioni escluse: risolvere le anomalie oppure importare fino al primo problema';
				GOTO BRANCH_END;
			END

			SELECT
				m.Anno, m.Progressivo, m.Identificativo, m.Tipo, m.RettificaAnno, m.RettificaProgressivo, m.Data, m.DataTrasmissione,
				m.IdOperazione, m.IdEer, m.IdMateriale, m.IdStatoFisico, m.IdUnitaMisura, Quantita = CAST(m.Quantita AS DECIMAL(18, 2)),
				m.JsonValori,
				o.Operazione, IsProduttore = ISNULL(o.IsProduttore, 0), ProduttoreSede = ISNULL(o.ProduttoreSede, 0),
				IsEsito = ISNULL(o.IsEsito, 0),
				IdMovimento = CAST(NULL AS CHAR(16)), IdRegistrazione = CAST(NULL AS CHAR(16))
			INTO #imp
			FROM
				dbo.tblRentriImportazioniMovimenti m
				INNER JOIN dbo.tblRifiutiOperazioni o ON m.IdOperazione = o.Id
			WHERE
				m.IdImportazione = @Id
				AND m.Azione = 'I'
				AND (@limiteAnno IS NULL OR m.Anno < @limiteAnno OR (m.Anno = @limiteAnno AND m.Progressivo < @limiteProgressivo));

			IF NOT EXISTS (SELECT 1 FROM #imp)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Nessuna registrazione da importare';
				GOTO BRANCH_END;
			END

			CREATE UNIQUE CLUSTERED INDEX IX_imp ON #imp (Anno, Progressivo);

			-- Id nuovi, nello stesso formato di uspId_get, registrati in tblId e tblIdLog (inserimento dell'utente)
			CREATE TABLE #id (Chiave VARCHAR(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY, Id CHAR(16) COLLATE DATABASE_DEFAULT NULL);

			-- ── 3. Soggetti ───────────────────────────────────────────────────────────────────────
			SELECT DISTINCT
				x.Id, x.Ruolo, x.CodiceFiscale, x.Numero, x.Stato, x.IdAutorizzazione, x.IdSede, x.Nome, x.PartitaIva, x.IdNazione,
				x.IdComune, x.Localita, x.CAP, x.Indirizzo, x.NumeroCivico,
				IdSedeFinale = CAST(NULL AS CHAR(16)), IdAutorizzazioneFinale = CAST(NULL AS CHAR(16))
			INTO #sogg
			FROM
				dbo.tblRentriImportazioniMovimentiSoggetti ms
				INNER JOIN #imp i ON ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo
				INNER JOIN dbo.tblRentriImportazioniSoggetti x ON ms.IdSoggetto = x.Id
			WHERE ms.IdImportazione = @Id;

			IF EXISTS (SELECT 1 FROM #sogg WHERE Stato = 'M')
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Ci sono soggetti da completare';
				GOTO BRANCH_END;
			END

			UPDATE #sogg SET IdAutorizzazioneFinale = IdAutorizzazione WHERE Stato IN ('A', 'U') AND IdAutorizzazione IS NOT NULL;
			UPDATE #sogg SET IdSedeFinale = IdSede WHERE IdAutorizzazioneFinale IS NULL AND IdSede IS NOT NULL;

			-- Soggetti nuovi (C): uno per codice fiscale, con i dati del primo completamento
			SELECT
				CodiceFiscale,
				Nome = MIN(Nome), PartitaIva = MIN(PartitaIva), IdNazione = ISNULL(MIN(IdNazione), '380'), IdComune = MIN(IdComune),
				Localita = MIN(Localita), CAP = MIN(CAP), Indirizzo = MIN(Indirizzo), NumeroCivico = MIN(NumeroCivico)
			INTO #nuoviSoggetti
			FROM #sogg
			WHERE Stato = 'C'
			GROUP BY CodiceFiscale;

			-- Soggetto creato nel frattempo (da un'altra importazione o a mano): si riusa la sede se è l'unica con quel codice
			SELECT n.CodiceFiscale, IdSede = MIN(s.Id)
			INTO #esistenti
			FROM
				#nuoviSoggetti n
				INNER JOIN dbo.tblSedi s ON UPPER(s.CodiceFiscale) = n.CodiceFiscale OR UPPER(s.PartitaIva) = n.CodiceFiscale
				INNER JOIN dbo.ufnSedi_get_SediByUtente_List(@idUtente) u ON u.Id = s.Id
			WHERE
				s.Disabilitata = 0
				AND s.Lock < 2
				AND u.Disabilitata = 0
				AND (u.IdAziendaInterna = @idAziendaInterna OR u.Condivisa = 1)
			GROUP BY n.CodiceFiscale
			HAVING COUNT(DISTINCT s.Id) = 1;

			UPDATE x
			SET IdSedeFinale = e.IdSede
			FROM
				#sogg x
				INNER JOIN #esistenti e ON e.CodiceFiscale = x.CodiceFiscale
			WHERE
				x.Stato = 'C'
				AND x.IdAutorizzazioneFinale IS NULL;

			DELETE n
			FROM #nuoviSoggetti n
			WHERE EXISTS (SELECT 1 FROM #esistenti e WHERE e.CodiceFiscale = n.CodiceFiscale);

			INSERT #id (Chiave)
			SELECT 'S:' + CodiceFiscale FROM #nuoviSoggetti
			UNION ALL
			SELECT 'X:' + CodiceFiscale FROM #nuoviSoggetti;

			-- Produttore della sede del registro: per le registrazioni senza produttore su RENTRI ma con il produttore
			-- previsto nella sede del registro (ProduttoreSede), come uspRifiutiRegistrazioni_upd
			DECLARE @serveNessunaRegistro BIT = IIF(EXISTS (
				SELECT 1
				FROM #imp i
				WHERE
					i.IsProduttore = 1
					AND i.ProduttoreSede = 1
					AND NOT EXISTS (
						SELECT 1
						FROM dbo.tblRentriImportazioniMovimentiSoggetti ms
						WHERE ms.IdImportazione = @Id AND ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo AND ms.Ruolo = 'P')), 1, 0);

			-- Autorizzazioni da usare o creare, una per sede, ruolo e numero (produttore senza numero: "Nessuna")
			SELECT DISTINCT
				IdSede = ISNULL(s.IdSedeFinale, 'S:' + s.CodiceFiscale),
				s.Ruolo,
				s.Numero,
				IdAutorizzazione = CAST(NULL AS CHAR(16))
			INTO #aut
			FROM #sogg s
			WHERE s.IdAutorizzazioneFinale IS NULL;

			IF @serveNessunaRegistro = 1 AND NOT EXISTS (SELECT 1 FROM #aut WHERE IdSede = @idSedeRegistro AND Ruolo = 'P' AND Numero = '')
				INSERT #aut (IdSede, Ruolo, Numero) VALUES (@idSedeRegistro, 'P', '');

			-- Autorizzazioni già esistenti sulle sedi esistenti
			UPDATE a
			SET IdAutorizzazione = (
				SELECT TOP 1 z.Id
				FROM dbo.tblRifiutiAutorizzazioni z
				WHERE
					z.IdSede = a.IdSede
					AND z.Lock < 2
					AND z.Disabilitata = 0
					AND (
						(a.Numero = '' AND a.Ruolo = 'P' AND z.Nessuna = 1)
						OR (a.Numero <> '' AND z.IdRuolo = a.Ruolo AND ISNULL(z.Nessuna, 0) = 0 AND UPPER(REPLACE(z.Numero, ' ', '')) = a.Numero))
				ORDER BY z.Lock, z.Id)
			FROM #aut a
			WHERE a.IdSede NOT LIKE 'S:%';

			INSERT #id (Chiave)
			SELECT CONCAT('A:', IdSede, ':', Ruolo, ':', Numero)
			FROM #aut
			WHERE IdAutorizzazione IS NULL;

			-- Movimenti e registrazioni
			INSERT #id (Chiave)
			SELECT CONCAT('M:', Anno, '/', Progressivo) FROM #imp
			UNION ALL
			SELECT CONCAT('R:', Anno, '/', Progressivo) FROM #imp;

			UPDATE #id SET Id = LOWER(LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 16));

			DECLARE @tentativi INT = 0;
			WHILE @tentativi < 10
			BEGIN
				;WITH doppi AS (
					SELECT Chiave, n = ROW_NUMBER() OVER (PARTITION BY Id ORDER BY Chiave)
					FROM #id
				)
				UPDATE i
				SET Id = LOWER(LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 16))
				FROM
					#id i
					INNER JOIN doppi d ON i.Chiave = d.Chiave
				WHERE
					d.n > 1
					OR i.Id LIKE '000000000000000[0-9a-f]'
					OR EXISTS (SELECT 1 FROM dbo.tblId t WITH (UPDLOCK, HOLDLOCK) WHERE t.Id = i.Id);

				IF @@ROWCOUNT = 0 BREAK;
				SET @tentativi += 1;
			END

			IF @tentativi >= 10
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Impossibile generare Id univoci';
				GOTO BRANCH_END;
			END

			INSERT dbo.tblId (Id) SELECT Id FROM #id;
			INSERT dbo.tblIdLog (Id, Operazione, [Data], IdUtente) SELECT Id, 'I', @adesso, @idUtente FROM #id;

			-- Soggetti nuovi: sede esterna radice dell'azienda interna del registro, con indirizzo (come uspSedi_ins/_upd)
			INSERT dbo.tblOsepe (Id, Tipo)
			SELECT k.Id, 'S'
			FROM #nuoviSoggetti n INNER JOIN #id k ON k.Chiave = 'S:' + n.CodiceFiscale;

			INSERT dbo.tblSedi (Id, IdParent, InternaEsterna, IdTipo, Nome, Cognome, CodiceFiscale, PartitaIva, Codice, Note, Disabilitata, UnitaLocale, Lock)
			SELECT
				k.Id, NULL, 'E', IIF(n.PartitaIva IS NULL, 'P', 'L'), n.Nome, NULL, n.CodiceFiscale, n.PartitaIva, NULL,
				'Creato dall''importazione delle registrazioni da RENTRI', 0, 1, 0
			FROM #nuoviSoggetti n INNER JOIN #id k ON k.Chiave = 'S:' + n.CodiceFiscale;

			INSERT dbo.tblSediEsterne (Id, IdSedeInterna)
			SELECT k.Id, @idAziendaInterna
			FROM #nuoviSoggetti n INNER JOIN #id k ON k.Chiave = 'S:' + n.CodiceFiscale;

			INSERT dbo.tblIndirizzi (Id, Indirizzo, NumeroCivico, CAP, Localita, IdComune, IdNazione)
			SELECT k.Id, n.Indirizzo, n.NumeroCivico, n.CAP, n.Localita, n.IdComune, n.IdNazione
			FROM #nuoviSoggetti n INNER JOIN #id k ON k.Chiave = 'X:' + n.CodiceFiscale;

			INSERT dbo.tblSediIndirizzi (Id, IdIndirizzo)
			SELECT ks.Id, ki.Id
			FROM
				#nuoviSoggetti n
				INNER JOIN #id ks ON ks.Chiave = 'S:' + n.CodiceFiscale
				INNER JOIN #id ki ON ki.Chiave = 'X:' + n.CodiceFiscale;

			UPDATE s
			SET
				NomeCompleto = COALESCE(s.Cognome + ' ' + s.Nome, s.Nome),
				IndirizzoCompleto = CASE WHEN i.IdNazione = '380' THEN ISNULL(i.Indirizzo + ISNULL(', ' + i.NumeroCivico, '') + ' - ', '') + ISNULL(i.Localita + ' - ', '') + ISNULL(i.CAP + ' ', '') + ISNULL(c.Nome + ' (' + p.Sigla + ')', '') ELSE ISNULL(i.Indirizzo + ISNULL(', ' + i.NumeroCivico, '') + ' - ', '') + ISNULL(i.CAP + ' ', '') + ISNULL(i.Localita + ' ', '') + ISNULL(na.Nome, '') END,
				IdAziendaInterna = @idAziendaInterna
			FROM
				#nuoviSoggetti n
				INNER JOIN #id k ON k.Chiave = 'S:' + n.CodiceFiscale
				INNER JOIN dbo.tblSedi s ON s.Id = k.Id
				INNER JOIN dbo.tblSediIndirizzi si ON s.Id = si.Id
				INNER JOIN dbo.tblIndirizzi i ON si.IdIndirizzo = i.Id
				LEFT JOIN dbo.tblComuni c ON i.IdComune = c.Id
				LEFT JOIN dbo.tblProvince p ON c.IdProvincia = p.Id
				LEFT JOIN dbo.tblNazioni na ON i.IdNazione = na.Id;

			-- Autorizzazioni nuove: dati di RENTRI (ruolo e numero); tipo, date e codici EER si completano in anagrafica
			UPDATE a
			SET IdAutorizzazione = k.Id
			FROM
				#aut a
				INNER JOIN #id k ON k.Chiave = CONCAT('A:', a.IdSede, ':', a.Ruolo, ':', a.Numero)
			WHERE a.IdAutorizzazione IS NULL;

			INSERT dbo.tblRifiutiAutorizzazioni
				(Id, IdSede, IdRuolo, IdTipo, IdNumeroTipo, Numero, Identificativo, DataInizio, DataFine, Note, Nessuna, Disabilitata, Lock)
			SELECT
				a.IdAutorizzazione,
				ISNULL(ks.Id, a.IdSede),
				a.Ruolo,
				NULL,
				IIF(a.Numero <> '' AND a.Ruolo IN ('T', 'I'), 'A', NULL),
				NULLIF(a.Numero, ''),
				NULL,
				IIF(a.Numero = '' AND a.Ruolo = 'P', '19000101', NULL),
				IIF(a.Numero = '' AND a.Ruolo = 'P', '20501231', NULL),
				IIF(a.Numero = '' AND a.Ruolo = 'P', NULL, 'Creata dall''importazione delle registrazioni da RENTRI: completare tipo, date e codici EER'),
				IIF(a.Numero = '' AND a.Ruolo = 'P', 1, 0),
				0,
				0
			FROM
				#aut a
				INNER JOIN #id k ON k.Chiave = CONCAT('A:', a.IdSede, ':', a.Ruolo, ':', a.Numero)
				LEFT JOIN #id ks ON a.IdSede = ks.Chiave;

			UPDATE s
			SET IdAutorizzazioneFinale = a.IdAutorizzazione
			FROM
				#sogg s
				INNER JOIN #aut a ON a.IdSede = ISNULL(s.IdSedeFinale, 'S:' + s.CodiceFiscale) AND a.Ruolo = s.Ruolo AND a.Numero = s.Numero
			WHERE s.IdAutorizzazioneFinale IS NULL;

			IF EXISTS (SELECT 1 FROM #sogg WHERE IdAutorizzazioneFinale IS NULL)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Autorizzazione di un soggetto non risolta';
				GOTO BRANCH_END;
			END

			DECLARE @idNessunaRegistro CHAR(16) = (SELECT TOP 1 IdAutorizzazione FROM #aut WHERE IdSede = @idSedeRegistro AND Ruolo = 'P' AND Numero = '');

			-- ── 4. Movimenti e registrazioni ──────────────────────────────────────────────────────
			UPDATE i
			SET
				IdMovimento = km.Id,
				IdRegistrazione = kr.Id
			FROM
				#imp i
				INNER JOIN #id km ON km.Chiave = CONCAT('M:', i.Anno, '/', i.Progressivo)
				INNER JOIN #id kr ON kr.Chiave = CONCAT('R:', i.Anno, '/', i.Progressivo);

			SELECT
				i.Anno, i.Progressivo,
				IdAttivita = (SELECT TOP 1 t.Id FROM dbo.tblRifiutiAttivitaRecuperoSmaltimento t WHERE t.Codice = j.Attivita),
				IdProvenienza = (SELECT TOP 1 t.Id FROM dbo.tblRifiutiProvenienze t WHERE t.Id = j.Provenienza),
				EerDescrizione = NULLIF(j.EerDescrizione, ''),
				FormularioNumero = NULLIF(j.NumeroFir, ''),
				-- RENTRI usa 0001-01-01 come data assente
				DataInizioTrasporto = IIF(TRY_CONVERT(DATETIMEOFFSET(0), j.DataInizioTrasporto) BETWEEN '19000102' AND '20790601',
					CONVERT(SMALLDATETIME, TRY_CONVERT(DATETIMEOFFSET(0), j.DataInizioTrasporto) AT TIME ZONE 'W. Europe Standard Time'), NULL),
				IdTrasportoTransfrontalieroTipo = (SELECT TOP 1 t.Id FROM dbo.tblRifiutiTrasportiTransfrontalieriTipi t WHERE t.Codice = j.TipoTransfrontaliero),
				IdRaee = (SELECT TOP 1 t.Id FROM dbo.tblRifiutiRaee t WHERE t.Codice = JSON_VALUE(i.JsonValori, '$.rifiuto.categorie_aee[0]')),
				MaterialeDescrizione = NULLIF(j.MaterialeDescrizione, ''),
				VeicoloFuoriUso = ISNULL(j.VeicoloFuoriUso, 0),
				VeicoloFuoriUsoNumero = NULLIF(j.VeicoloNumero, ''),
				VeicoloFuoriUsoData = IIF(TRY_CONVERT(DATE, LEFT(j.VeicoloData, 10)) > '19000101', TRY_CONVERT(DATE, LEFT(j.VeicoloData, 10)), NULL),
				Note = NULLIF(j.Annotazioni, ''),
				-- Esito solo per le operazioni che lo prevedono
				IdEsito = IIF(i.IsEsito = 1 AND j.Esito IS NOT NULL, CASE j.RespingimentoTipo WHEN 'T' THEN 'R' WHEN 'P' THEN 'P' ELSE 'A' END, NULL),
				IdCausaleRespingimento = IIF(i.IsEsito = 1, (SELECT TOP 1 t.Id FROM dbo.tblRifiutiRegistrazioniEsitiCausaliRespingimento t WHERE t.Codice = j.RespingimentoCausale), NULL),
				CausaleRespingimentoAltro = IIF(i.IsEsito = 1, NULLIF(j.RespingimentoCausaleAltro, ''), NULL),
				QuantitaRespinta = IIF(i.IsEsito = 1, TRY_CONVERT(DECIMAL(18, 2), j.RespingimentoQuantita), NULL),
				IdUnitaMisuraQuantitaRespinta = IIF(i.IsEsito = 1, (SELECT TOP 1 t.Id FROM dbo.tblUnitaMisura t WHERE t.Codice = j.RespingimentoUnitaMisura), NULL),
				DataFineTrasporto = IIF(i.IsEsito = 1 AND TRY_CONVERT(DATETIMEOFFSET(0), j.DataFineTrasporto) BETWEEN '19000102' AND '20790601',
					CONVERT(SMALLDATETIME, TRY_CONVERT(DATETIMEOFFSET(0), j.DataFineTrasporto) AT TIME ZONE 'W. Europe Standard Time'), NULL),
				QuantitaVerificata = IIF(i.IsEsito = 1, TRY_CONVERT(DECIMAL(18, 2), j.PesoVerificato), NULL)
			INTO #valori
			FROM
				#imp i
				CROSS APPLY OPENJSON(i.JsonValori)
				WITH (
					Attivita VARCHAR(5) '$.rifiuto.destinato_attivita',
					Provenienza VARCHAR(5) '$.rifiuto.provenienza',
					EerDescrizione VARCHAR(200) '$.rifiuto.descrizione_eer',
					NumeroFir VARCHAR(20) '$.integrazione_fir.numero_fir',
					DataInizioTrasporto VARCHAR(40) '$.integrazione_fir.data_inizio_trasporto',
					TipoTransfrontaliero VARCHAR(5) '$.integrazione_fir.tipo_trasporto_transfrontaliero',
					MaterialeDescrizione VARCHAR(200) '$.materiali.descrizione_materiale',
					VeicoloFuoriUso BIT '$.rifiuto.veicolo_fuori_uso',
					VeicoloNumero VARCHAR(50) '$.rifiuto.veicolo_fuori_uso_reg_pubblica_sicurezza.numero',
					VeicoloData VARCHAR(40) '$.rifiuto.veicolo_fuori_uso_reg_pubblica_sicurezza.data',
					Annotazioni VARCHAR(500) '$.annotazioni',
					Esito NVARCHAR(MAX) '$.esito' AS JSON,
					RespingimentoTipo VARCHAR(5) '$.esito.respingimento.tipo',
					RespingimentoCausale VARCHAR(5) '$.esito.respingimento.causale',
					RespingimentoCausaleAltro VARCHAR(100) '$.esito.respingimento.causale_altro',
					RespingimentoQuantita VARCHAR(40) '$.esito.respingimento.quantita.valore',
					RespingimentoUnitaMisura VARCHAR(5) '$.esito.respingimento.quantita.unita_misura',
					DataFineTrasporto VARCHAR(40) '$.esito.data_fine_trasporto',
					PesoVerificato VARCHAR(40) '$.esito.peso_verificato_destino'
				) j;

			INSERT dbo.tblRifiutiMovimenti
				(Id, IdRegistro, IdOperazione, IdEer, IdStatoFisico, IdAttivita, IdUnitaMisura, IdProvenienza, Quantita, EerDescrizione,
				 FormularioNumero, DataInizioTrasporto)
			SELECT
				i.IdMovimento, @idRegistro, i.IdOperazione, i.IdEer, i.IdStatoFisico, v.IdAttivita, i.IdUnitaMisura, v.IdProvenienza, i.Quantita,
				v.EerDescrizione, v.FormularioNumero, v.DataInizioTrasporto
			FROM
				#imp i
				INNER JOIN #valori v ON v.Anno = i.Anno AND v.Progressivo = i.Progressivo;

			INSERT dbo.tblRifiutiRegistrazioni
				(Id, IdMovimento, IdEsito, IdRaee, IdCausaleRespingimento, IdTrasportoTransfrontalieroTipo, IdMateriale, IdAttivitaProvenienza,
				 IdUnitaMisuraQuantitaRespinta, CausaleRespingimentoAltro, QuantitaRespinta, DataFineTrasporto, Operazione, [Data], Numero,
				 QuantitaVerificata, VeicoloFuoriUso, VeicoloFuoriUsoNumero, VeicoloFuoriUsoData, MaterialeDescrizione, RentriIdentificativo,
				 RentriData, Note, Lock)
			SELECT
				i.IdRegistrazione, i.IdMovimento, v.IdEsito, v.IdRaee, v.IdCausaleRespingimento, v.IdTrasportoTransfrontalieroTipo, i.IdMateriale, NULL,
				v.IdUnitaMisuraQuantitaRespinta, v.CausaleRespingimentoAltro, v.QuantitaRespinta, v.DataFineTrasporto, i.Operazione, i.[Data], i.Progressivo,
				v.QuantitaVerificata, v.VeicoloFuoriUso, v.VeicoloFuoriUsoNumero, v.VeicoloFuoriUsoData, v.MaterialeDescrizione, i.Identificativo,
				i.DataTrasmissione, v.Note, 0
			FROM
				#imp i
				INNER JOIN #valori v ON v.Anno = i.Anno AND v.Progressivo = i.Progressivo;

			-- Caratteristiche di pericolo
			INSERT dbo.tblRifiutiMovimentiClassiPericolo (Id, IdClasse)
			SELECT DISTINCT i.IdMovimento, c.Id
			FROM
				#imp i
				CROSS APPLY OPENJSON(i.JsonValori, '$.rifiuto.caratteristiche_pericolo') h
				INNER JOIN dbo.tblRifiutiClassiPericolo c ON c.Codice = h.value;

			-- Ruoli (come la migrazione 3.1 e uspRifiutiRegistrazioni_upd)
			INSERT dbo.tblRifiutiMovimentiProduttori (Id, IdAutorizzazione, Quantita, Pos)
			SELECT i.IdMovimento, s.IdAutorizzazioneFinale, i.Quantita, 0
			FROM
				#imp i
				INNER JOIN dbo.tblRentriImportazioniMovimentiSoggetti ms ON ms.IdImportazione = @Id AND ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo AND ms.Ruolo = 'P'
				INNER JOIN #sogg s ON ms.IdSoggetto = s.Id
			UNION ALL
			SELECT i.IdMovimento, @idNessunaRegistro, i.Quantita, 0
			FROM #imp i
			WHERE
				i.IsProduttore = 1
				AND i.ProduttoreSede = 1
				AND @idNessunaRegistro IS NOT NULL
				AND NOT EXISTS (
					SELECT 1
					FROM dbo.tblRentriImportazioniMovimentiSoggetti ms
					WHERE ms.IdImportazione = @Id AND ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo AND ms.Ruolo = 'P');

			INSERT dbo.tblRifiutiMovimentiDestinatari (Id, IdAutorizzazione, Pos)
			SELECT i.IdMovimento, s.IdAutorizzazioneFinale, 0
			FROM
				#imp i
				INNER JOIN dbo.tblRentriImportazioniMovimentiSoggetti ms ON ms.IdImportazione = @Id AND ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo AND ms.Ruolo = 'D'
				INNER JOIN #sogg s ON ms.IdSoggetto = s.Id;

			INSERT dbo.tblRifiutiMovimentiTrasportatori (Id, IdAutorizzazione, Pos, IdTipo)
			SELECT i.IdMovimento, s.IdAutorizzazioneFinale, ms.Pos - 1, NULL
			FROM
				#imp i
				INNER JOIN dbo.tblRentriImportazioniMovimentiSoggetti ms ON ms.IdImportazione = @Id AND ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo AND ms.Ruolo = 'T'
				INNER JOIN #sogg s ON ms.IdSoggetto = s.Id;

			INSERT dbo.tblRifiutiMovimentiIntermediari (Id, IdAutorizzazione, Pos)
			SELECT i.IdMovimento, s.IdAutorizzazioneFinale, ms.Pos - 1
			FROM
				#imp i
				INNER JOIN dbo.tblRentriImportazioniMovimentiSoggetti ms ON ms.IdImportazione = @Id AND ms.Anno = i.Anno AND ms.Progressivo = i.Progressivo AND ms.Ruolo = 'I'
				INNER JOIN #sogg s ON ms.IdSoggetto = s.Id;

			-- Sedi del movimento dalle autorizzazioni dei ruoli, come uspRifiutiRegistrazioni_upd
			UPDATE m
			SET
				IdSedeProduttoreDetentore = ap.IdSede,
				IdSedeDestinatario = ad.IdSede,
				IdSedeTrasportatore1 = ar.IdSede,
				IdSedeIntermediario1 = ai.IdSede
			FROM
				#imp x
				INNER JOIN dbo.tblRifiutiMovimenti m ON x.IdMovimento = m.Id
				LEFT JOIN dbo.tblRifiutiMovimentiProduttori p ON p.Id = m.Id AND p.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ap ON p.IdAutorizzazione = ap.Id
				LEFT JOIN dbo.tblRifiutiMovimentiDestinatari d ON d.Id = m.Id AND d.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ad ON d.IdAutorizzazione = ad.Id
				LEFT JOIN dbo.tblRifiutiMovimentiTrasportatori t ON t.Id = m.Id AND t.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ar ON t.IdAutorizzazione = ar.Id
				LEFT JOIN dbo.tblRifiutiMovimentiIntermediari n ON n.Id = m.Id AND n.Pos = 0
				LEFT JOIN dbo.tblRifiutiAutorizzazioni ai ON n.IdAutorizzazione = ai.Id;

			-- ── 5. Relazioni carico/scarico ───────────────────────────────────────────────────────
			IF EXISTS (
				SELECT 1
				FROM
					dbo.tblRentriImportazioniRelazioni l
					INNER JOIN #imp p ON p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
					LEFT JOIN #imp f ON f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
				WHERE
					l.IdImportazione = @Id
					AND f.Anno IS NULL
					AND l.IdRegistrazioneFiglio IS NULL)
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'Una registrazione da importare è associata a una registrazione che non viene importata';
				GOTO BRANCH_END;
			END

			INSERT dbo.tblRifiutiRegistrazioniRelazioni (Id, IdParent, Operazione, Quantita, Pos)
			SELECT
				ISNULL(f.IdRegistrazione, l.IdRegistrazioneFiglio),
				p.IdRegistrazione,
				p.Operazione,
				CAST(ISNULL(l.Quantita, 0) AS DECIMAL(18, 2)),
				ROW_NUMBER() OVER (PARTITION BY p.IdRegistrazione ORDER BY l.FiglioAnno, l.FiglioProgressivo) - 1
			FROM
				dbo.tblRentriImportazioniRelazioni l
				INNER JOIN #imp p ON p.Anno = l.PadreAnno AND p.Progressivo = l.PadreProgressivo
				LEFT JOIN #imp f ON f.Anno = l.FiglioAnno AND f.Progressivo = l.FiglioProgressivo
			WHERE l.IdImportazione = @Id;

			-- ── 6. Rettifiche e annullamenti, in ordine cronologico ────────────────────────────────
			DECLARE @idOriginale CHAR(16), @idRettifica CHAR(16), @annullata BIT;

			DECLARE cr CURSOR LOCAL FAST_FORWARD FOR
				SELECT
					ISNULL(o.IdRegistrazione, om.IdRegistrazione),
					r.IdRegistrazione,
					IIF(r.Tipo = 'A', 1, 0)
				FROM
					#imp r
					LEFT JOIN #imp o ON o.Anno = r.RettificaAnno AND o.Progressivo = r.RettificaProgressivo
					LEFT JOIN dbo.tblRentriImportazioniMovimenti om
						ON om.IdImportazione = @Id AND om.Anno = r.RettificaAnno AND om.Progressivo = r.RettificaProgressivo AND om.Azione = 'P'
				WHERE r.Tipo IN ('R', 'A')
				ORDER BY r.[Data], r.Anno, r.Progressivo;

			OPEN cr;
			FETCH cr INTO @idOriginale, @idRettifica, @annullata;
			WHILE @@FETCH_STATUS = 0
			BEGIN
				IF @idOriginale IS NULL
				BEGIN
					CLOSE cr;
					DEALLOCATE cr;
					ROLLBACK TRANSACTION;
					SET @returnValue = -1;
					SET @returnMessage = 'Registrazione originale di una rettifica non trovata';
					GOTO BRANCH_END;
				END

				INSERT dbo.tblRentriRegistrazioniRettifiche (Id, IdRettifica, Annullata)
				VALUES (@idOriginale, @idRettifica, @annullata);

				IF @annullata = 1
					UPDATE t
					SET
						t.IdEer = o.IdEer,
						t.EerDescrizione = o.EerDescrizione,
						t.IdStatoFisico = o.IdStatoFisico,
						t.IdUnitaMisura = o.IdUnitaMisura,
						t.Quantita = IIF(o.IsOperativa = 1, 0, o.Quantita)
					FROM
						dbo.tblRentriRegistrazioniRettifiche t
						CROSS APPLY dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(t.IdRettifica, NULL, NULL, NULL, NULL) o
					WHERE t.IdRettifica = @idRettifica;
				ELSE
					UPDATE t
					SET
						t.IdEer = IIF(o.IsOperativa = 1, m.IdEer, o.IdEer),
						t.EerDescrizione = IIF(o.IsOperativa = 1, m.EerDescrizione, o.EerDescrizione),
						t.IdStatoFisico = IIF(o.IsOperativa = 1, m.IdStatoFisico, o.IdStatoFisico),
						t.IdUnitaMisura = IIF(o.IsOperativa = 1, m.IdUnitaMisura, o.IdUnitaMisura),
						t.Quantita = IIF(o.IsOperativa = 1, m.Quantita, o.Quantita)
					FROM
						dbo.tblRentriRegistrazioniRettifiche t
						INNER JOIN dbo.tblRifiutiRegistrazioni r ON t.IdRettifica = r.Id
						INNER JOIN dbo.tblRifiutiMovimenti m ON r.IdMovimento = m.Id
						CROSS APPLY dbo.ufnRifiutiRegistrazioni_get_RettificaOperativa(t.IdRettifica, m.IdEer, m.IdStatoFisico, m.IdUnitaMisura, m.Quantita) o
					WHERE t.IdRettifica = @idRettifica;

				FETCH cr INTO @idOriginale, @idRettifica, @annullata;
			END
			CLOSE cr;
			DEALLOCATE cr;

			-- ── 7. Storico ────────────────────────────────────────────────────────────────────────
			UPDATE m
			SET IdRegistrazione = i.IdRegistrazione
			FROM
				dbo.tblRentriImportazioniMovimenti m
				INNER JOIN #imp i ON m.Anno = i.Anno AND m.Progressivo = i.Progressivo
			WHERE m.IdImportazione = @Id;

			UPDATE dbo.tblRentriImportazioni
			SET
				Stato = 'E',
				FinoAlPrimoProblema = @FinoAlPrimoProblema,
				DataEsecuzione = @adesso
			WHERE Id = @Id;

			DECLARE
				@importate INT = (SELECT COUNT(*) FROM #imp),
				@soggettiCreati INT = (SELECT COUNT(*) FROM #nuoviSoggetti),
				@autorizzazioniCreate INT = (SELECT COUNT(*) FROM #aut a INNER JOIN #id k ON k.Chiave = CONCAT('A:', a.IdSede, ':', a.Ruolo, ':', a.Numero)),
				@relazioni INT = (SELECT COUNT(*) FROM dbo.tblRifiutiRegistrazioniRelazioni x INNER JOIN #imp p ON x.IdParent = p.IdRegistrazione),
				@rettifiche INT = (SELECT COUNT(*) FROM #imp WHERE Tipo IN ('R', 'A'));

		COMMIT TRANSACTION;

		SELECT
			ReturnValue = @returnValue,
			Importate = @importate,
			GiaPresenti = (SELECT COUNT(*) FROM dbo.tblRentriImportazioniMovimenti WHERE IdImportazione = @Id AND Azione = 'P'),
			NonImportate = (SELECT COUNT(*) FROM dbo.tblRentriImportazioniMovimenti WHERE IdImportazione = @Id AND Azione IN ('I', 'X') AND IdRegistrazione IS NULL),
			Rettifiche = @rettifiche,
			Relazioni = @relazioni,
			SoggettiCreati = @soggettiCreati,
			AutorizzazioniCreate = @autorizzazioniCreate,
			PrimaEsclusaAnno = @limiteAnno,
			PrimaEsclusaProgressivo = @limiteProgressivo;

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

-- ===== 3. uspRentriImportazioni_del
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Rentri > Importazione: scarta un'importazione in preparazione (area temporanea). Nel registro non c'è nulla da
-- togliere: le registrazioni nascono solo dall'esecuzione. Un'importazione eseguita resta come storico.
CREATE OR ALTER PROCEDURE [dbo].[uspRentriImportazioni_del]
	@IdSessione CHAR(16) = NULL,
	@Id CHAR(16) = NULL
AS
BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	BEGIN TRY
		DECLARE @returnValue INT = 0;
		DECLARE @returnMessage NVARCHAR(200) = NULL;

		SET @IdSessione = NULLIF(LTRIM(RTRIM(@IdSessione)), '');
		SET @Id = NULLIF(LTRIM(RTRIM(@Id)), '');

		IF @IdSessione IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @IdSessione non può essere vuoto';
			GOTO BRANCH_END;
		END
		IF @Id IS NULL
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Il parametro @Id non può essere vuoto';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sulla funzione: configurazione RENTRI (RNT), riservata agli amministratori
		DECLARE @permesso TINYINT;
		EXEC dbo.uspSessione_get_FunzionePermesso
			@Id = @IdSessione,
			@IdFunzione = 'RNT',
			@Permesso = @permesso OUTPUT;
		IF 2 > ISNULL(@permesso, 0)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Non si dispone dei diritti necessari';
			GOTO BRANCH_END;
		END

		-- Controlla il permesso sul record (titolarità) tramite il registro
		IF NOT EXISTS (
			SELECT 1
			FROM
				dbo.tblRentriImportazioni m
				INNER JOIN dbo.tblRifiutiRegistri g ON m.IdRegistro = g.Id
				INNER JOIN dbo.ufnSedi_get_SediInterneBySessione_List(@IdSessione) i ON g.IdSede = i.Id
			WHERE m.Id = @Id)
		BEGIN
			SET @returnValue = -1;
			SET @returnMessage = 'Importazione non trovata';
			GOTO BRANCH_END;
		END

		BEGIN TRANSACTION;

			DELETE dbo.tblRentriImportazioni
			WHERE
				Id = @Id
				AND Stato = 'P';

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION;
				SET @returnValue = -1;
				SET @returnMessage = 'L''importazione è già stata eseguita e non può essere scartata';
				GOTO BRANCH_END;
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
