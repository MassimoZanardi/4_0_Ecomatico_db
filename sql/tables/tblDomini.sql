SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblDomini](
	[Id] [char](16) COLLATE Latin1_General_CI_AS NOT NULL,
	[IdStato] [char](2) COLLATE Latin1_General_CI_AS NULL,
	[Nome] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Riferimento] [varchar](50) COLLATE Latin1_General_CI_AS NULL,
	[Registrazione] [smalldatetime] NULL,
	[Scadenza] [date] NULL,
	[ScadenzaAuto] [bit] NULL,
	[Master] [bit] NULL,
	[UtentiMax] [int] NULL,
	[AziendeMax] [int] NULL,
	[SediMax] [int] NULL,
	[RegistriMax] [int] NULL,
	[MagazziniMax] [int] NULL,
	[ServiziMax] [int] NULL,
	[RentriMax] [int] NULL,
	[ConservazioniMax] [int] NULL,
	[ConservazioniXfirMax] [int] NULL,
	[Demo] [bit] NULL,
	[Codice] [char](5) COLLATE Latin1_General_CI_AS NULL,
	[Logo] [varbinary](max) NULL,
	[Url] [varchar](200) COLLATE Latin1_General_CI_AS NULL,
	[Lock] [tinyint] NULL,
 CONSTRAINT [PK_tblDomini] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO

ALTER TABLE [dbo].[tblDomini]  WITH CHECK ADD  CONSTRAINT [FK_tblDomini_tblDominiStati] FOREIGN KEY([IdStato])
REFERENCES [dbo].[tblDominiStati] ([Id])
GO

ALTER TABLE [dbo].[tblDomini] CHECK CONSTRAINT [FK_tblDomini_tblDominiStati]
GO
