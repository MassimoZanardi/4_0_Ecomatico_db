SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Modulo Email (EML): coda e registro delle email (una riga = un messaggio a un indirizzo). Creata da tools/email_modulo.sql
CREATE TABLE [dbo].[tblEmail](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdDominio] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[Tipo] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdUtente] [char](16) COLLATE Latin1_General_CI_AS NULL,
	[Indirizzo] [varchar](250) COLLATE Latin1_General_CI_AS NOT NULL,
	[Mittente] [nvarchar](100) COLLATE Latin1_General_CI_AS NULL,
	[RispondiA] [varchar](250) COLLATE Latin1_General_CI_AS NULL,
	[Oggetto] [nvarchar](250) COLLATE Latin1_General_CI_AS NOT NULL,
	[Contenuto] [nvarchar](max) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdStato] [char](1) COLLATE Latin1_General_CI_AS NOT NULL,
	[Tentativi] [tinyint] NOT NULL CONSTRAINT [DF_tblEmail_Tentativi] DEFAULT (0),
	[Creazione] [datetime2](0) NOT NULL CONSTRAINT [DF_tblEmail_Creazione] DEFAULT (GETDATE()),
	[ProssimoTentativo] [datetime2](0) NOT NULL CONSTRAINT [DF_tblEmail_ProssimoTentativo] DEFAULT (GETDATE()),
	[Presa] [datetime2](0) NULL,
	[Invio] [datetime2](0) NULL,
	[Nota] [nvarchar](500) COLLATE Latin1_General_CI_AS NULL,
	[QuotaGiorno] [date] NULL,
 CONSTRAINT [PK_tblEmail] PRIMARY KEY CLUSTERED ([Id] ASC)
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IX_tblEmail_Coda] ON [dbo].[tblEmail] ([IdStato], [ProssimoTentativo]) INCLUDE ([Tipo], [IdDominio], [Creazione])
GO
CREATE NONCLUSTERED INDEX [IX_tblEmail_Dominio] ON [dbo].[tblEmail] ([IdDominio], [Creazione])
GO
CREATE NONCLUSTERED INDEX [IX_tblEmail_Presa] ON [dbo].[tblEmail] ([Presa])
GO
